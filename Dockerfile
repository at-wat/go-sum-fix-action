FROM golang:1.27-alpine

RUN apk add --no-cache git bash findutils

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
