#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
DOMAIN=$1
EMAIL=$2
AUTH_URL=$3
SALAMANDER_PASS=$4
STATS_PASS=$5

sudo apt update
sudo apt install certbot -y

sudo certbot certonly --standalone -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email --non-interactive

bash <(curl -fsSL https://get.hy2.sh/)

sudo chmod -R 755 /etc/letsencrypt/live/
sudo chmod -R 755 /etc/letsencrypt/archive/


sudo tee /etc/hysteria/config.yaml > /dev/null <<EOF
listen: :443
tls:
  cert: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
  key: /etc/letsencrypt/live/$DOMAIN/privkey.pem
auth:
  type: http
  http:
    url: $AUTH_URL
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
bandwidth:
  up: 100 mbps
  down: 100 mbps
ignoreClientBandwidth: false
speedTest: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: tls
  tls:
    addr: 1.1.1.1:853
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
obfs:
  type: salamander
  salamander:
    password: $SALAMANDER_PASS
trafficStats:
  listen: :26328
  secret: $STATS_PASS
EOF

sudo systemctl daemon-reload
sudo systemctl start hysteria-server.service
sudo systemctl enable hysteria-server.service
