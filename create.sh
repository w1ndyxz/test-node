#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
DOMAIN=$1
EMAIL=$2
AUTH_URL=$3
SALAMANDER_PASS=$4
STATS_PASS=$5
ENDPOINT_SENDER=$6

sudo apt update
sudo apt install certbot -y

sudo certbot certonly --standalone -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email --non-interactive --deploy-hook "systemctl restart hysteria-server.service"

curl -O https://bootstrap.pypa.io/get-pip.py
sudo python3 get-pip.py
sudo pip install psutil requests pyyaml



bash <(curl -fsSL https://get.hy2.sh/)

sudo chmod -R 755 /etc/letsencrypt/live/
sudo chmod -R 755 /etc/letsencrypt/archive/

sudo mkdir -p /etc/hysteria/sender


sudo tee /etc/hysteria/sender/sender.py > /dev/null <<EOF
import time
import psutil
import requests
import logging
import yaml

def load_yaml(file):
    with open(file, "r") as f:
        return yaml.safe_load(f)

logging.basicConfig(level=logging.INFO)

def get_uptime():
    uptime_seconds = int(time.time() - psutil.boot_time())
    days, s = divmod(uptime_seconds, 86400)
    hours, s = divmod(s, 3600)
    minutes, s = divmod(s, 60)
    return days, hours, minutes, uptime_seconds

def get_stats():
    vm = psutil.virtual_memory()
    netio = psutil.net_io_counters()
    days, hours, minutes, uptime_seconds = get_uptime()
    return {
        "cpu": int(psutil.cpu_percent()),
        "ram_total": vm.total,
        "ram_used": vm.used,
        "uptime": {"days": days, "hours": hours, "minutes": minutes, "timestamp": uptime_seconds},
        "traffic": {"boot_up": netio.bytes_sent, "boot_down": netio.bytes_recv},
    }

try:
    r = requests.post(
        load_yaml('/etc/hysteria/sender/mini.yaml').get('endpoint'),
        json=get_stats(),
        # headers={"Authorization": f"{secret}"},
        timeout=10,
    )
    logging.info(f"OK -> {r.status_code}")
except Exception as e:
    logging.error(f"Error: {e}")
EOF

sudo tee /etc/hysteria/sender/mini.yaml > /dev/null <<EOF
endpoint: $ENDPOINT_SENDER
EOF


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



sudo tee /etc/systemd/system/panel-sender.service > /dev/null <<EOF
[Unit]
Description=Panel Stats Sender

[Service]
ExecStart=/usr/bin/python3 /etc/hysteria/sender/sender.py
User=root
EOF

sudo tee /etc/systemd/system/panel-sender.timer > /dev/null <<EOF
[Unit]
Description=Run Panel Sender every 10 minutes

[Timer]
OnBootSec=30
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable panel-sender.timer
sudo systemctl start panel-sender.timer

sudo systemctl daemon-reload
sudo systemctl start hysteria-server.service
sudo systemctl enable hysteria-server.service
