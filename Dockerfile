FROM golang:1.13-alpine

RUN apk add --no-cache git bash jq

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
