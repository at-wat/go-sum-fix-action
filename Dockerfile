FROM golang:1.16-alpine

COPY .git/refs/heads/master /version
RUN echo /version

RUN apk add --no-cache git bash

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
