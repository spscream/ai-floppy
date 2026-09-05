---
name: otel-prometheus-host-must-be-ipv4
description: Claude Code's Prometheus exporter binds dual-stack `*:9464`, which a container cannot reach even though curl from the host answers — OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0 is required, and the symptom points at the network instead
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232 on WSL2 (net.ipv6.bindv6only=0), Docker Desktop 29.7.2, prom/prometheus:latest with --add-host=host.docker.internal:host-gateway"
recheck: "Start a session with OTEL_METRICS_EXPORTER=prometheus and no host override, then `ss -ltn | grep 9464` (shows `*:9464`) and check the Prometheus target: down with `connection refused` while `curl localhost:9464/metrics` on the host answers"
invalidated_by: "A release that binds the exporter to 0.0.0.0 by default, or a Docker networking change that routes to dual-stack listeners"
---

# The Prometheus exporter binds an address your container cannot reach

## The fact

By default the exporter listens on `*:9464` — a dual-stack socket. From the host,
`curl localhost:9464/metrics` answers. From a container reaching the host through
`host.docker.internal`, the scrape fails:

```
Get "http://host.docker.internal:9464/metrics":
  dial tcp 192.168.65.254:9464: connect: connection refused
```

Setting `OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0` changes the listener to `0.0.0.0:9464`
and the target goes `up` immediately, same everything else.

## Why it is not obvious

Every part of the symptom points somewhere else. "Connection refused" from inside a
container reads as a Docker networking problem, so you go and check `host.docker.internal`
resolution, the gateway, the firewall — and each of those checks *passes*. Meanwhile the
one check that would exonerate the network, curling the endpoint from the host, also
passes, which makes the endpoint look healthy. Both halves work; only the pair fails.

`ss` reporting `*:9464` reinforces the wrong conclusion, because `*` reads as "all
interfaces", and on a box with `net.ipv6.bindv6only=0` a dual-stack socket usually does
accept IPv4. Here it did not.

## Evidence

MEASURED. Same host, same container, two listeners on adjacent ports:

```
$ ss -ltn | grep 9464
LISTEN 0 512        *:9464        *:*      # claude, exporter default
$ ss -ltn | grep 9465
LISTEN 0 5    0.0.0.0:9465  0.0.0.0:*      # python3 -m http.server --bind 0.0.0.0
```

The control server on 9465 was reachable from inside the Prometheus container (it
answered `404 File not found` for `/metrics`, which is correct for `http.server`). The
exporter on 9464 was refused, at the same moment, from the same container. That pairing
is what identified the address family; `sysctl net.ipv6.bindv6only` was `0`, so the
usual explanation did not apply.

MEASURED. With `OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0` the bind becomes
`0.0.0.0:9464`, the target reports `up` with an empty `lastError`, and samples land in
the TSDB.

## How to re-check

Run a session without the override and confirm `*:9464` plus a refused scrape; add the
override and confirm `0.0.0.0:9464` plus `up`. Both take one session each.

## What it costs you not to know

An afternoon spent debugging container networking that is not broken. The neighbouring
trap on the same path costs the same way and looks identical: under Docker Desktop on
WSL2, `--network host` does not give the container the WSL distro's network, so
Prometheus logs `Server is ready to receive web requests` and nothing is listening on
the published port. Two different causes, one symptom — "the container cannot reach the
thing" — and neither is the network.

## See also

[[prometheus-metrics-need-a-second-request]] — what you get once the scrape works, and
why the first probe shows almost none of it.
