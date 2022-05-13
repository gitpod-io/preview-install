all: generate_certs install

generate_certs: 
	@echo "Generatign certs"
	mkdir -p ./certs
	openssl req -x509 \
	            -sha256 -days 356 \
	            -nodes \
	            -newkey rsa:2048 \
	            -subj "/CN=${DOMAIN}/C=US/L=San Fransisco" \
	            -keyout ./certs/CA.key -out ./certs/CA.pem 	

	openssl genrsa -out ./certs/${DOMAIN}.key 2048
	openssl req -new -key ./certs/${DOMAIN}.key -out ./certs/${DOMAIN}.csr -subj "/C=US/ST=CA/L=SF/O=Gitpod/OU=client/CN=`hostname -f`/emailAddress=example@gitpod.io"	

	echo "authorityKeyIdentifier=keyid,issuer" > ./certs/${DOMAIN}.ext
	echo "basicConstraints=CA:FALSE" >> ./certs/${DOMAIN}.ext
	echo "keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment" >> ./certs/${DOMAIN}.ext
	echo "subjectAltName = @alt_names" >> ./certs/${DOMAIN}.ext
	echo "[alt_names]" >> ./certs/${DOMAIN}.ext
	echo "DNS.1 = ${DOMAIN}" >> ./certs/${DOMAIN}.ext
	echo "DNS.2 = *.${DOMAIN}" >> ./certs/${DOMAIN}.ext
	echo "DNS.3 = *.ws.${DOMAIN}" >> ./certs/${DOMAIN}.ext
	echo "DNS.4 = reg.${DOMAIN}" >> ./certs/${DOMAIN}.ext

	openssl x509 -req -in ./certs/${DOMAIN}.csr -CA ./certs/CA.pem -CAkey ./certs/CA.key -CAcreateserial \
	-out ./certs/${DOMAIN}.crt -days 825 -sha256 -extfile ./certs/${DOMAIN}.ext

install:
	docker run --name gitpod \
	--privileged --rm -it \
	-e DOMAIN=${DOMAIN} \
	-v /tmp/workspaces:/var/gitpod/workspaces \
	-v $(shell pwd)/certs:/certs \
	5000-csweichel-gitpoddockerk-f77i3oemb58.ws-us45.gitpod.io/gitpod-k3s:latest

.PHONY: install