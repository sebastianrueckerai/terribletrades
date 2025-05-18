FROM golang:1.22 as builder

WORKDIR /app
COPY src/ ./
COPY go.mod go.sum ./
RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux go build -o reddit-poller .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/reddit-poller .
CMD ["./reddit-poller"]