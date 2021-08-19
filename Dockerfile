FROM golang:1.17-alpine

RUN apk add --no-cache git bash

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
