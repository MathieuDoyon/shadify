FROM golang:1.27.3-alpine AS base
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

FROM base AS dev
RUN go install github.com/cespare/reflex@v0.3.1
COPY . .
EXPOSE 5000
CMD ["reflex", "-r", "\\.go$", "-s", "--", "go", "run", "./cmd/server"]

FROM base AS build
ENV CGO_ENABLED=0
ARG MDBOOK_VERSION=0.4.25
RUN set -eu; \
    case "$(uname -m)" in \
      x86_64|aarch64) arch="$(uname -m)" ;; \
      *) echo "Unsupported mdBook architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    wget -O /tmp/mdbook.tar.gz "https://github.com/rust-lang/mdBook/releases/download/v${MDBOOK_VERSION}/mdbook-v${MDBOOK_VERSION}-${arch}-unknown-linux-musl.tar.gz"; \
    tar -xzf /tmp/mdbook.tar.gz -C /usr/local/bin mdbook; \
    rm /tmp/mdbook.tar.gz
COPY cmd ./cmd
COPY internal ./internal
COPY pkg ./pkg
COPY docs ./docs
COPY book.toml ./
RUN go build -trimpath -ldflags="-s -w" -o /out/shadify ./cmd/server
RUN mdbook build

FROM alpine:3.23 AS prod
RUN apk add --no-cache ca-certificates \
    && addgroup -S -g 10001 shadify \
    && adduser -S -D -H -u 10001 -G shadify shadify
WORKDIR /app
COPY --from=build /out/shadify ./shadify
COPY --from=build /app/book ./book
COPY data ./data
COPY LICENSE ./LICENSE
ENV PORT=5000
USER 10001:10001
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/" || exit 1
CMD ["./shadify"]
