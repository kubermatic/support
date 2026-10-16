FROM alpine:3.22

RUN apk add --no-cache util-linux-misc

ARG VERSION=dev
ENV COLLECTOR_VERSION=${VERSION}

COPY --chmod=0755 collect.sh entrypoint.sh /opt/kubermatic/

ENTRYPOINT ["/opt/kubermatic/entrypoint.sh"]
