#!/bin/sh
# Reproduces the IPv4-only bind of the Tdarr WebUI/server on an IPv6-enabled docker network. Prints the kernel socket tables from inside the container, then probes the same port over IPv4 and IPv6. Expected: both services LISTEN on 0.0.0.0 in /proc/net/tcp, /proc/net/tcp6 has no listeners, and the IPv6 curl fails while IPv4 returns 200.
set -e

docker compose up -d

echo "waiting for Tdarr to come up..."
i=0
until docker compose exec -T prober sh -c \
  "curl -4 -sf http://tdarr:8265/api/v2/get-nodes >/dev/null" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 60 ] && { echo "tdarr never came up"; exit 1; }
  sleep 5
done

TDARR_V6=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}' \
  "$(docker compose ps -q tdarr)")
TDARR_V4=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  "$(docker compose ps -q tdarr)")

echo
echo "== listening sockets inside the tdarr container =="
echo "-- /proc/net/tcp (IPv4) --"
docker compose exec -T tdarr sh -c "cat /proc/net/tcp" | awk 'NR==1 || $4=="0A"'
echo "-- /proc/net/tcp6 (IPv6) --"
docker compose exec -T tdarr sh -c "cat /proc/net/tcp6" | awk 'NR==1 || $4=="0A"'
echo "(0x2049 = port 8265, 0x204A = port 8266)"
echo "container addresses: $TDARR_V4 / $TDARR_V6"

echo
echo "== direct IPv4 to container :8265 =="
docker compose exec -T prober curl -4 -s -o /dev/null -w '%{http_code}\n' \
  "http://$TDARR_V4:8265" --max-time 5

echo "== direct IPv6 to container :8265 =="
docker compose exec -T prober curl -6 -s -o /dev/null -w '%{http_code}\n' \
  "http://[$TDARR_V6]:8265" --max-time 5 || echo FAILED

echo
echo "teardown: docker compose down"
