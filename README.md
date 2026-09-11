# tdarr-ipv6-repro

Tdarr's WebUI and server ports bind IPv4-only, which breaks them on any IPv6-enabled Docker network. This repo reproduces it in three commands.

## The bug

The Tdarr server (closed-source Rust binary, checked against v2.86.01 via the alexbelgium hassio add-on image) creates IPv4-only listening sockets for both of its ports:

- WebUI on `0.0.0.0:8265`
- server API on `0.0.0.0:8266`

Nothing inside the container listens on IPv6 at all, so when the Docker network has IPv6 enabled and published ports DNAT to the container's global IPv6 address, IPv6 clients get a reset after connect while IPv4 works fine. (The connection-then-reset signature rather than a plain refusal comes from the host-side proxy accepting the v6 connection before its backend dial to the container's v6 address finds no listener.)

Found in the wild on a Home Assistant Yellow: HAOS runs its hassio Docker bridge fully IPv6-enabled (every container gets a real ULA address), and every other add-on's app (nginx, the .NET *arr stack, sshd, qBittorrent) binds dual-stack `[::]`, so Tdarr was the only service on the box unreachable over IPv6.

## Reproduce

Requires docker with IPv6 support in compose (Docker Desktop or any modern Linux daemon), arm64 host (or swap the image tag to `-amd64` in compose.yaml):

```sh
./repro.sh
```

What it does:

1. Brings up a Tdarr container and a curl prober on an `enable_ipv6` network (subnet `fd0c:dead:beef::/64`), so no port publishing or vpnkit is in the way — this probes the container's own addresses directly.
2. Dumps the kernel socket tables from inside the container.
3. Curls the same port over IPv4 and over IPv6.

## Expected output

The socket tables are the diagnosis. IPv4 shows both listeners; IPv6 is empty:

```
-- /proc/net/tcp (IPv4) --
  sl  local_address rem_address   st ...
   1: 00000000:2049 00000000:0000 0A ...   <- 0.0.0.0:8265 WebUI, LISTEN
   2: 00000000:204A 00000000:0000 0A ...   <- 0.0.0.0:8266 server, LISTEN
-- /proc/net/tcp6 (IPv6) --
  sl  local_address ... st ...
                                          <- nothing, ever

== direct IPv4 to container :8265 ==
200
== direct IPv6 to container :8265 ==
000 / FAILED
```

Identical behaviour observed on the original HAOS 18.2 host: direct v4 to the container serves 200, direct v6 to the same port dies, and a second container running nginx (dual-stack) on the same network answers on both.

## Exonerated along the way

- The hassio add-on's elevated flags (SYS_ADMIN, DAC_READ_SEARCH, udev, host_dbus, 61 device mappings) — a stripped local add-on fork with zero flags still fails.
- The alexbelgium packaging in general — a different add-on from the same repo works fine over IPv6.
- The image under Docker Desktop — all variants pass there, because vpnkit always dials the container over IPv4 regardless of how the client connected, which is exactly why this bug hides on Macs and only bites on hosts where v6 traffic reaches the container's own v6 address.

## Workaround

Put a dual-stack reverse proxy (nginx) in front and publish its port instead. On the Home Assistant box this is the Nginx Proxy Manager add-on forwarding to the Tdarr container; IPv6 clients then terminate on nginx and the proxied hop to Tdarr runs over IPv4.
