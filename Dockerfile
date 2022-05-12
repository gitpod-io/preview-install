FROM eu.gcr.io/gitpod-core-dev/build/installer:cw-misc-installer.0 AS installer

FROM rancher/k3s:v1.21.12-k3s1 AS k3s

FROM alpine

RUN apk add --no-cache \
    yq \
    openssl

ADD https://github.com/krallin/tini/releases/download/v0.19.0/tini-static /tini
RUN chmod +x /tini

COPY --from=installer /app/installer /gitpod-installer
COPY --from=k3s /bin/k3s /bin/k3s
COPY --from=k3s /bin/kubectl /bin/kubectl


COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/tini", "--", "/entrypoint.sh" ]
