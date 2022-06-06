# Gitpod Preview Installation

This repo helps users to try out and preview self-hosted Gitpod **locally** without all the things
needed for a production instance. The aim is to provide an installation mechanism as minimal and
simple as possible.

## Installation

```bash
sudo docker run --privileged --name gitpod --rm -it -v /tmp/workspaces:/var/gitpod/workspaces 5000-gitpodio-previewinstall-ox4ypumem4w.ws-us46.gitpod.io/gitpod-k3s:latest
```

Once the above command is ran, Your gitpod instance can be accessed at `172-17-17-172.nip.io`. [nip.io](https://nip.io/) is just wildcard DNS for local addresses, So all
of this is local, and cannot be accessed over the internet.

## Known Issues

- Prebuilds don't work as they require webhooks support over the internet.
