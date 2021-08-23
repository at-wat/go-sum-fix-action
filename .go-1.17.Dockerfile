# This file is auto-generated. Edit Dockerfile instead!!
ARG GO_VERSION=1.17
FROM golang:${GO_VERSION}-alpine

RUN apk add --no-cache git bash

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
