---
name: prometheus-metrics-need-a-second-request
description: Claude Code's Prometheus endpoint does carry tokens and cost, but a metric family only appears once it has been recorded, and tokens are recorded on the session's second API request — so a one-request session serves the session counter alone, however long it lives
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232, WSL2, OTEL_METRICS_EXPORTER=prometheus, three headless controls on separate ports plus one live interactive session"
recheck: "Run a session with CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus, make it issue at least two API requests (any tool call does), and `curl localhost:9464/metrics | grep '^# TYPE'` while it is alive"
invalidated_by: "A release that registers the metric families at startup rather than on first record, or that adds a counter for API requests"
---

# The Prometheus endpoint fills up on the second request, not the first

## The fact

A Prometheus scrape of Claude Code carries tokens, cost, lines of code, edit-tool
decisions and active time — with `model` and `session_id` labels, so per-model and
per-subagent cost is on it. Seven families in a working session:

```
target_info, claude_code_session_count_total, claude_code_lines_of_code_count_total,
claude_code_cost_usage_total, claude_code_token_usage_total,
claude_code_code_edit_tool_decision_total, claude_code_active_time_total
```

But **a family appears on the endpoint only after it has been recorded at least
once**, and tokens and cost are not recorded when the first response completes. A
session that answers one question and exits serves exactly two families —
`target_info` and the session counter, 816 bytes — and it does so no matter how long
it stays alive.

This is the trap, because the shortest way to try the exporter is one headless
`claude -p`, and that is precisely the shape that shows nothing.

## Why it is not obvious

Everything about the failure looks like the metrics are absent rather than unwritten.
The scrape succeeds, the target is `up`, the body parses, the TSDB fills — with one
series. Nothing distinguishes "this counter does not exist here" from "this counter
has not been recorded yet", and the natural next hypothesis is wrong twice over: it is
not the transport (the console exporter shows the same counters, so they clearly
exist), and it is not the process being too short-lived (waiting does not help).

## Evidence

MEASURED, three headless controls, each on its own exporter port so as not to contend
with a live session for 9464:

| run | API requests | lifetime | families on the endpoint |
|---|---|---|---|
| one question, short answer | 1 | 7 s | **2** (816 bytes) |
| one question, 900-word answer | 1 | > 120 s | **2** |
| three `echo` calls via `--allowedTools` | ≥ 2 | 12 s | **4** — `token_usage` and `cost_usage` appeared at t=10 s |

The first row reproduces the earlier measurement that this note supersedes: that
observation was correct, its explanation was not. The second row kills "the headless
process is too short-lived for the counter to land" — two minutes of life at one
request is not enough either. The third isolates what was actually missing: a second
request.

MEASURED, interactive session, same version, sampled live: 17 815 bytes, all seven
families. `input` 1 941, `output` 21 861, `cacheRead` 1 687 181, `cacheCreation`
139 277 tokens; `claude_code_cost_usage_total` summing to $2.2595 across three models
in one session, since subagents carry their own `model` label.

Note the two families that appear latest — `lines_of_code_count_total` and
`code_edit_tool_decision_total` — register only once the session actually edits a
file. Same rule: recorded once, then visible.

MEASURED, still true: **there is no counter for API requests in any family.** How many
turns a command took lives in the log event `claude_code.api_request` (with
`request_id`, `session.id`, `prompt.id`, four token classes, `cost_usd`,
`duration_ms`, `query_source`), and Prometheus pulls metrics, never events.

## How to re-check

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus \
OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0 claude --allowedTools 'Bash(echo:*)' \
  -p 'Run `echo one`, then `echo two`, and say what printed.' &
sleep 10 && curl -s localhost:9464/metrics | grep -E '^# TYPE'
```

Four TYPE lines or more means this note still holds. Two means the tool call did not
happen — check the run, not the exporter. The endpoint lives exactly as long as the
process, so an interactive session is the easier place to look.

## What it costs you not to know

You conclude from one headless probe that the exporter carries nothing but a session
counter, and you write off Prometheus for cost dashboards. It would in fact answer
"what did this week cost, by model" perfectly well. What it will not answer is "how
many turns did this command take" — that one is an event, and needs OTLP and a log
store, or the transcripts on disk, which have the advantage of working retroactively.

Decide which question you have before choosing the transport. Live cost trends across
a team: this endpoint. Per-command turns: not this endpoint, and not any metric.

## See also

[[otel-prometheus-host-must-be-ipv4]] — the bind that makes the scrape work at all.
[[plugin-prefix-breaks-command-search]] — the other way a transcript measurement goes
quietly wrong.
