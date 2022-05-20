#!/bin/sh

set -eux -o pipefile

if [ -z "$DOMAIN" ]; then
    >&2 echo "Error: Environment variable DOMAIN is missing."
    exit 1;
fi



FN_CACERT="/certs/ca.pem"
FN_SSLCERT="/certs/ssl.crt"
FN_SSLKEY="/certs/ssl.key"
FN_CAKEY="/certs/ca.key"
FN_CSREXT="/certs/cert.ext"

if [ ! -f "$FN_CACERT" ] && [ ! -f "$FN_SSLCERT" ] && [ ! -f "$FN_SSLKEY" ]; then
    [ ! -d /certs ] && mkdir -p /certs

    /bin/mkcert \
      -cert-file "$FN_SSLCERT" \
      -key-file "$FN_SSLKEY" \
      "*.ws.${DOMAIN}" "*.${DOMAIN}" "${DOMAIN}" "ws-manager" "wsdaemon"
    CAROOT="/certs" /bin/mkcert -install
    mv /certs/rootCA.pem "$FN_CACERT"
fi

mkdir -p /var/lib/rancher/k3s/server/manifests/gitpod

CACERT=$(base64 -w0 < "$FN_CACERT")
SSLCERT=$(base64 -w0 < "$FN_SSLCERT")
SSLKEY=$(base64 -w0 < "$FN_SSLKEY")

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/customCA-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-cert
  labels:
    app: gitpod
data:
  ca.crt: $CACERT
EOF

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/https-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: https-cert
  labels:
    app: gitpod
data:
  tls.crt: $SSLCERT
  tls.key: $SSLKEY
EOF

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/registry-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: builtin-registry-certs
  labels:
    app: gitpod
data:
  ca.crt: $CACERT
  tls.crt: $SSLCERT
  tls.key: $SSLKEY
EOF

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/manager-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ws-manager-client-tls
  labels:
    app: gitpod
data:
  ca.crt: $CACERT
  tls.crt: $SSLCERT
  tls.key: $SSLKEY
EOF

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/ws-manager-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ws-manager-tls
  labels:
    app: gitpod
data:
  ca.crt: $CACERT
  tls.crt: $SSLCERT
  tls.key: $SSLKEY
EOF

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/ws-daemon-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ws-daemon-tls
  labels:
    app: gitpod
data:
  ca.crt: $CACERT
  tls.crt: $SSLCERT
  tls.key: $SSLKEY
EOF

/gitpod-installer init > config.yaml
yq e -i '.domain = "'"$DOMAIN"'"' config.yaml
yq e -i ".certificate.name = \"https-cert\"" config.yaml
yq e -i ".certificate.kind = \"secret\"" config.yaml
yq e -i ".customCACert.name = \"ca-cert\"" config.yaml
yq e -i ".customCACert.kind = \"secret\"" config.yaml
yq e -i '.workspace.runtime.containerdSocket = "/run/k3s/containerd/containerd.sock"' config.yaml
yq e -i '.workspace.runtime.containerdRuntimeDir = "/var/lib/rancher/k3s/agent/containerd/io.containerd.runtime.v2.task/k8s.io/"' config.yaml

/gitpod-installer render --config config.yaml --output-split-files /var/lib/rancher/k3s/server/manifests/gitpod
for f in /var/lib/rancher/k3s/server/manifests/gitpod/*.yaml; do (cat "$f"; echo) >> /var/lib/rancher/k3s/server/gitpod.debug; done
rm /var/lib/rancher/k3s/server/manifests/gitpod/*NetworkPolicy*
for f in /var/lib/rancher/k3s/server/manifests/gitpod/*PersistentVolumeClaim*.yaml; do yq e -i '.spec.storageClassName="local-path"' "$f"; done
yq eval-all -i '. as $item ireduce ({}; . *+ $item)' /var/lib/rancher/k3s/server/manifests/gitpod/*_StatefulSet_messagebus.yaml /app/manifests/messagebus.yaml 
for f in /var/lib/rancher/k3s/server/manifests/gitpod/*StatefulSet*.yaml; do yq e -i '.spec.volumeClaimTemplates[0].spec.storageClassName="local-path"' "$f"; done
 
for f in /var/lib/rancher/k3s/server/manifests/gitpod/*.yaml; do (cat "$f"; echo) >> /var/lib/rancher/k3s/server/manifests/gitpod.yaml; done
rm -rf /var/lib/rancher/k3s/server/manifests/gitpod

# gitpod-helm-installer.yaml needs access to kubernetes by the public host IP.
kubeconfig_replacip() {
    while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do sleep 1; done
    HOSTIP=$(hostname -i)
    sed "s+127.0.0.1+$HOSTIP+g" /etc/rancher/k3s/k3s.yaml > /etc/rancher/k3s/k3s_.yaml
}
kubeconfig_replacip &

installation_completed_hook() {
    echo "Waiting for pods to be ready ..."
    kubectl wait --for=condition=ready pod -l app=gitpod --timeout 30s

    echo "Removing network policies ..."
    kubectl delete networkpolicies.networking.k8s.io --all

    echo "Removing installer manifest ..."
    rm -f /var/lib/rancher/k3s/server/manifests/gitpod.yaml
}
installation_completed_hook &

# add HTTPS certs secret
if [ -f /certs/chain.pem ] && [ -f /certs/dhparams.pem ] && [ -f /certs/fullchain.pem ] && [ -f /certs/privkey.pem ]; then
  CHAIN=$(base64 --wrap=0 < /certs/chain.pem)
  DHPARAMS=$(base64 --wrap=0 < /certs/dhparams.pem)
  FULLCHAIN=$(base64 --wrap=0 < /certs/fullchain.pem)
  PRIVKEY=$(base64 --wrap=0 < /certs/privkey.pem)
  cat << EOF > /var/lib/rancher/k3s/server/manifests/proxy-config-certificates.yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxy-config-certificates
  labels:
    app: gitpod
data:
  chain.pem: $CHAIN
  dhparams.pem: $DHPARAMS
  fullchain.pem: $FULLCHAIN
  privkey.pem: $PRIVKEY
EOF
fi


# patch DNS config
# if [ -n "$DOMAIN" ] && [ -n "$DNSSERVER" ]; then
#     patchdns() {
#         echo "Waiting for CoreDNS to patch config ..."
#         while [ -z "$(kubectl get pods -n kube-system | grep coredns | grep Running)" ]; do sleep 10; done

#         DOMAIN=$1
#         DNSSERVER=$2

#         if [ -z "$(kubectl get configmap -n kube-system coredns -o json | grep $DOMAIN)" ]; then
#             echo "Patching CoreDNS config ..."

#             kubectl get configmap -n kube-system coredns -o json | \
#                 sed -e "s+.:53+$DOMAIN {\\\\n  forward . $DNSSERVER\\\\n}\\\\n.:53+g" | \
#                 kubectl apply -f -
#             echo "CoreDNS config patched."
#         else
#             echo "CoreDNS has been patched already."
#         fi
#     }
#     patchdns "$DOMAIN" "$DNSSERVER" &
# fi


# start k3s
/bin/k3s server --disable traefik \
  --node-label gitpod.io/workload_meta=true \
  --node-label gitpod.io/workload_ide=true \
  --node-label gitpod.io/workload_workspace_services=true \
  --node-label gitpod.io/workload_workspace_regular=true \
  --node-label gitpod.io/workload_workspace_headless=true
