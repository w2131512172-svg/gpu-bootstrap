#!/usr/bin/env bash
set -euo pipefail

: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:?need CF_LOCAL_PORT}"

mkdir -p /root/.cloudflared

sed \
  -e "s#__CF_TUNNEL_UUID__#${CF_TUNNEL_UUID}#g" \
  -e "s#__CF_HOSTNAME__#${CF_HOSTNAME}#g" \
  -e "s#__CF_LOCAL_PORT__#${CF_LOCAL_PORT}#g" \
  config.template.yml > /root/.cloudflared/config.yml

if grep -q "service: service:" /root/.cloudflared/config.yml; then
  echo "[ERROR] bad tunnel config: duplicated service:"
  exit 1
fi

echo "[OK] rendered: /root/.cloudflared/config.yml"
cat /root/.cloudflared/config.yml
