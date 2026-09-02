#!/usr/bin/env bash
set -Eeuo pipefail

echo "LF_PROFILE_RUNTIME_VPS_INSPECTION_V1"
date -u +"utc=%Y-%m-%dT%H:%M:%SZ"
hostnamectl --static 2>/dev/null | sed 's/^/host=/' || hostname | sed 's/^/host=/'
nproc | sed 's/^/cpu_count=/'
awk '/MemTotal|MemAvailable/ {print "memory_" tolower($1) "=" $2 " " $3}' /proc/meminfo
df -h / /opt /var/lib 2>/dev/null | awk 'NR==1 || !seen[$6]++'
if command -v tesseract >/dev/null 2>&1; then
  tesseract --version 2>/dev/null | head -1 | sed 's/^/tesseract=/'
  tesseract --list-langs 2>/dev/null | tail -n +2 | paste -sd, - | sed 's/^/tesseract_languages=/'
else
  echo "tesseract=NOT_FOUND"
fi

echo "llama_processes:"
pgrep -af '(^|/)(llama-server|llama_server)( |$)' || true
echo "candidate_units:"
systemctl list-units --type=service --all --no-legend 2>/dev/null \
  | awk 'tolower($1) ~ /(llama|profile-runtime)/ {print $1, $3, $4}' || true
echo "loopback_listeners:"
ss -ltnp 2>/dev/null | awk '$4 ~ /127\.0\.0\.1:(8080|8090)$/ || $4 ~ /\[::1\]:(8080|8090)$/ {print}' || true

for endpoint in http://127.0.0.1:8080/health http://127.0.0.1:8080/v1/models http://127.0.0.1:8090/health; do
  code="$(curl --silent --show-error --max-time 5 --output /tmp/lf-inspect-response.$$ \
    --write-out '%{http_code}' "$endpoint" 2>/dev/null || true)"
  bytes="$(wc -c </tmp/lf-inspect-response.$$ 2>/dev/null || printf '0')"
  printf 'probe=%s status=%s bytes=%s\n' "$endpoint" "${code:-000}" "$bytes"
done
rm -f "/tmp/lf-inspect-response.$$"

echo "model_candidates:"
find /opt /srv /var/lib -xdev -maxdepth 6 -type f \
  \( -name '*.gguf' -o -name '*.mmproj' \) -printf '%p %s-bytes\n' 2>/dev/null | head -50 || true

echo "classification=INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY"
