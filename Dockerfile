FROM eu.gcr.io/gitpod-core-dev/build/installer:main.3413 AS installer

FROM rancher/k3s:v1.22.9-rc4-k3s1

ADD https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64 /bin/mkcert
RUN chmod +x /bin/mkcert

ADD https://github.com/krallin/tini/releases/download/v0.19.0/tini-static /tini
RUN chmod +x /tini

ADD https://github.com/cert-manager/cert-manager/releases/download/v1.8.0/cert-manager.yaml /var/lib/rancher/k3s/server/manifests/cert-manager.yaml

ADD https://github.com/mikefarah/yq/releases/download/v4.25.1/yq_linux_amd64 /bin/yq 
RUN chmod +x /bin/yq

COPY manifests/* /app/manifests/
COPY --from=installer /app/installer /gitpod-installer

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/tini", "--", "/entrypoint.sh" ]
