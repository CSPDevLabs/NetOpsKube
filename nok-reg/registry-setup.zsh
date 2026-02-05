#!/usr/bin/zsh

CAPASS=080915
PREFIX=certs
SROS_IMAGE=registry.srlinux.dev/pub/nokia_srsim:25.10.R1

mkdir -p ${PREFIX}

cat > $PREFIX/rootCA.cnf <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = IT
ST = Lombardia
L = Monza
O = Nokia
OU = NetOpsKube
CN = myregistry.local
emailAddress = anton.zyablov@nokia.com

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectAltName = @alt_names

[alt_names]
DNS.1 = myregistry.local
DNS.2 = localhost
DNS.3 = registry.srlinux.dev
IP.1 = 127.0.0.1
EOF

openssl genrsa -out ${PREFIX}/rootCA.key -aes256 -passout pass:$CAPASS 4096&& openssl req -new -x509 -key  ${PREFIX}/rootCA.key -config ${PREFIX}/rootCA.cnf -days 365 -out ${PREFIX}/rootCA.pem -passin pass:$CAPASS 
openssl rsa -in ${PREFIX}/rootCA.key -out ${PREFIX}/rootCA.decrypted.key -passin pass:$CAPASS
chmod 600 ${PREFIX}/rootCA.key
chmod 600 ${PREFIX}/rootCA.pem

sudo mkdir -p /etc/docker/certs.d/localhost
sudo cp ${PREFIX}/rootCA.pem /etc/docker/certs.d/localhost/ca.pem

sudo mkdir -p /etc/docker/certs.d/myregistry.local
sudo cp ${PREFIX}/rootCA.pem /etc/docker/certs.d/myregistry.local/ca.pem

docker compose up -d

docker push registry.srlinux.dev/pub/nokia_srsim:25.10.R1

