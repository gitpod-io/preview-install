FROM eu.gcr.io/gitpod-core-dev/build/installer:cw-misc-installer.0 AS installer

FROM rancher/k3s:v1.21.12-k3s1

ADD https://github.com/krallin/tini/releases/download/v0.19.0/tini-static /tini
RUN chmod +x /tini


ADD https://github.com/mikefarah/yq/releases/download/v4.25.1/yq_linux_amd64 /yq 
RUN chmod +x /yq

COPY --from=installer /app/installer /gitpod-installer

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/tini", "--", "/entrypoint.sh" ]
