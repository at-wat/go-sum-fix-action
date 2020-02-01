FROM golang:1.13-alpine

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
