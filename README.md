# Gitpod in a Docker container with k3s

**This is merely a starting point**

Things that are working:
- latest installer is integrated
- PVCs are provisioned using `local-path`
- All containers start

Things that are missing:
- generating self-signed certs in the entrypoint.sh
- all the DNS setup, e.g. patching CoreDNS in the entrypoint

Things that are not working:
- the `builtin-registry-certs` secret seems to be missing