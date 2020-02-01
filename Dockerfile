FROM golang:1.13-alpine

RUN apk add --no-cache git

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
