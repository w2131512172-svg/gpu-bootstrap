#!/usr/bin/env bash
set -euo pipefail

# ===== 参数校验 =====
: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:?need CF_LOCAL_PORT}"

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_FILE="${TEMPLATE_DIR}/config.template.yml"
OUTPUT_FILE="/root/.cloudflared/config.yml"

mkdir -p /root/.cloudflared

sed \
  -e "s#__CF_TUNNEL_UUID__#${CF_TUNNEL_UUID}#g" \
  -e "s#__CF_HOSTNAME__#${CF_HOSTNAME}#g" \
  -e "s#__CF_LOCAL_PORT__#${CF_LOCAL_PORT}#g" \
  "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "[OK] rendered: $OUTPUT_FILE"
echo "----------------------------------------"
cat "$OUTPUT_FILE"
