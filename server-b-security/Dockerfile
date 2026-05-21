# syntax=docker/dockerfile:1

# =============================================================
# Build stage
# =============================================================
FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -trimpath \
    -o /security-api ./cmd/server

# =============================================================
# Runtime stage
# =============================================================
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata wget \
    && addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /security-api .
RUN chown -R app:app /app

USER app

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8081/health || exit 1

CMD ["./security-api"]
