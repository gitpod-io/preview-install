#!/bin/sh

set -eu

if [ -z "$DOMAIN" ]; then
    >&2 echo "Error: Environment variable DOMAIN is missing."
    exit 1;
fi

mkdir -p /var/lib/rancher/k3s/server/manifests/gitpod

# Generate Certificates
# Create a CA cert
openssl req -x509 \
            -sha256 -days 356 \
            -nodes \
            -newkey rsa:2048 \
            -subj "/CN=${DOMAIN}/C=US/L=San Fransisco" \
            -keyout myCA.key -out myCA.pem 

openssl genrsa -out $DOMAIN.key 2048
openssl req -new -key $DOMAIN.key -out $DOMAIN.csr -subj "/C=US/ST=CA/L=SF/O=Gitpod/OU=client/CN=`hostname -f`/emailAddress=example@gitpod.io"

cat > $DOMAIN.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = *.ws.$DOMAIN
EOF

openssl x509 -req -in $DOMAIN.csr -CA ../myCA.pem -CAkey ../myCA.key -CAcreateserial \
-out $DOMAIN.crt -days 825 -sha256 -extfile $DOMAIN.ext 

CACERT=$(base64 < /myCA.pem )
SSLCERT=$(base64 < /$DOMAIN.crt)
SSLKEY=$(base64 < /$DOMAIN.key)

cat << EOF > /var/lib/rancher/k3s/server/manifests/gitpod/customCA-cert.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-cert
  labels:
    app: gitpod
data:
  ca.crt: "$CACERT"
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
  ssl.crt: "$SSLCERT"
  ssl.key: "$SSLKEY"
EOF

/gitpod-installer init > config.yaml
yq e -i '.domain = "'"$DOMAIN"'"' config.yaml
yq e -i ".certificate.name = \"https-cert\"" config.yaml
yq e -i ".certificate.kind = \"secret\"" config.yaml
yq e -i ".customCACert.name = \"ca-cert\"" config.yaml
yq e -i ".customCACert.kind = \"secret\"" config.yaml

/gitpod-installer render --config config.yaml --output-split-files /var/lib/rancher/k3s/server/manifests/gitpod
rm /var/lib/rancher/k3s/server/manifests/gitpod/*NetworkPolicy*
for f in /var/lib/rancher/k3s/server/manifests/gitpod/*PersistentVolumeClaim*.yaml; do yq e -i '.spec.storageClassName="local-path"' "$f"; done
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
