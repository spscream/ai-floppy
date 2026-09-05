---
name: prometheus-exporter-carries-only-sessions
description: Claude Code's Prometheus exporter serves one metric, the session counter — tokens, cost and per-request turns are not on it, so a Prometheus-based cost dashboard cannot answer what a command cost
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232, headless `claude -p`, WSL2 + Docker Desktop, prom/prometheus:latest scraping every 5s"
recheck: "Run a session with CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0, then `curl localhost:9464/metrics | grep '^# TYPE'` while it is alive"
invalidated_by: "A release that registers claude_code.token.usage and claude_code.cost.usage with the Prometheus meter provider, or that adds a counter for API requests"
---

# A Prometheus scrape of Claude Code gets the session count and nothing else

## The fact

Claude Code exports OpenTelemetry in three signals, and they do not carry the same
things. The **console** exporter emits `claude_code.token.usage` and
`claude_code.cost.usage`. The **Prometheus** exporter, scraped over its whole lifetime,
serves exactly one series:

```
# TYPE claude_code_session_count_total counter
claude_code_session_count_total{...} 1
```

No tokens, no cost. And the number most often wanted — how many turns a command took —
is not a metric at all in any exporter: it lives in the **log event**
`claude_code.api_request`, one per request, carrying `request_id`, `session.id`,
`prompt.id`, the four token classes, `cost_usd`, `duration_ms` and `query_source`.
Prometheus pulls metrics. It will never see an event.

## Why it is not obvious

The documentation lists the metrics and the events together, under one heading, behind
one enable flag. Choosing `OTEL_METRICS_EXPORTER=prometheus` reads like a transport
decision — where the same data goes — rather than a decision about which data exists.
And the failure is silent in the worst way: the scrape succeeds, the target is `up`, the
TSDB fills, and the dashboard is simply missing rows nobody has written yet.

## Evidence

MEASURED. Prometheus in Docker, `scrape_interval: 5s`, target healthy (`up`, empty
`lastError`). After sessions that completed many API requests, the whole TSDB content
was one series:

```
$ curl -s --data-urlencode 'query={__name__=~"claude_code.*"}' \
    http://localhost:9091/api/v1/query
1 серий
  claude_code_session_count_total = 1
```

MEASURED, same version, console exporter: `claude_code.token.usage` and
`claude_code.cost.usage` both present, alongside events `api_request`, `user_prompt`,
`assistant_response`, `plugin_loaded`, `hook_registered`, `hook_execution_start`,
`hook_execution_complete`, `mcp_server_connection`. So the metrics are produced; they
are not on the pull endpoint.

MEASURED, the endpoint body while the process is alive: 817 bytes, `# TYPE target_info`
and `# TYPE claude_code_session_count_total`, one value line. Stable across a 36-second
run sampled every 3 seconds.

READ, not verified: attribution by `skill`, `agent` and `plugin`. The docs promise those
labels; no run here invoked a skill or a subagent.

## How to re-check

Start any session with the three variables above, and while it is running:

```bash
curl -s localhost:9464/metrics | grep -E '^# TYPE'
```

Two TYPE lines means this note still holds. More means it has been fixed.

Note the endpoint lives exactly as long as the process. A headless `claude -p` run lasts
20–40 seconds, so scraping one is a race; use an interactive session.

## What it costs you not to know

You stand up Prometheus and Grafana to answer "what does our session ritual cost", and
after the infrastructure is running you find that the only question it can answer is how
many sessions started. The turn counts and token sums are in the transcripts on disk the
whole time — where they are also available *retroactively*, which telemetry never is,
because it only knows what happened after you enabled it.

Decide which questions you have before choosing the transport. If they are per-command
turns or per-command cost, read the transcripts. If they are live trends across a team,
you need the OTLP path and a log store, not this one.

## See also

[[otel-prometheus-host-must-be-ipv4]] — the bind that makes the scrape work at all.
[[plugin-prefix-breaks-command-search]] — the other way a transcript measurement goes
quietly wrong.
