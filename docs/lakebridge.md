# Lakebridge vs. this repo (Cursor + agent pipeline)

The skeptical-prospect question: *"Doesn't Databricks already have a migration
tool? Why would I do it this way?"* Short answer: **Lakebridge and this repo
solve different halves of the same problem — and for a medium-complexity EDW
like WWI DW, Cursor + this repo delivers a Lakebridge-class outcome at the
same price ($0), while adding the operating model Lakebridge doesn't have.**

## What Lakebridge is

[Lakebridge](https://www.databricks.com/solutions/migration/lakebridge) is
Databricks' free, open-source migration toolkit (Databricks Labs, built on
BladeBridge). Four modules:

| Module | What it does |
|---|---|
| **Profiler** | Connects to a live source DB; workload metrics, sizing, TCO estimate |
| **Analyzer** | Parses local SQL files; per-object complexity (LOW → VERY HIGH) |
| **Transpiler** | Three engines: **BladeBridge** (mature, rule-based, broadest dialect + ETL coverage), **Morpheus** (AST-based, correctness guarantees for MSSQL/Snowflake/Synapse), **Switch** (LLM-powered, experimental) |
| **Reconciler** | Row counts, schema, and data values compared between live source and Databricks target |

CLI-first (`databricks labs lakebridge analyze|transpile|reconcile`), human
drives each step. Databricks claims it automates up to 80% of a migration.

## Capability by capability

| Capability | Lakebridge | Cursor + this repo | Verdict |
|---|---|---|---|
| Per-object assessment | Analyzer: complexity grade per SQL file | Assess stage → `ops.migration_backlog` (classification, reads/writes, risk flags per proc, validated against a JSON Schema contract) | **Parity** — theirs grades files; ours produces an actionable, queryable backlog |
| Workload profiling / sizing | Profiler on live DB: usage metrics, cost estimate | — | **Lakebridge wins** (we don't profile) |
| SQL conversion breadth | BladeBridge/Morpheus: Teradata, Oracle, Netezza, SSIS, DataStage, dbt, … | Convert agent: T-SQL → Databricks SQL, one dialect | **Lakebridge wins** on breadth |
| SQL conversion approach | Switch engine = LLM-powered (experimental) | Convert agent = LLM-powered, with full repo context, a written style guide (`convert_style.md`), and conversion contracts | **Parity** — same class of engine; ours carries project context and house style |
| Correctness guarantees | Morpheus: errors/warns rather than silently wrong output | Deterministic reconcile + gate after conversion | **Different mechanism, same goal** — they guarantee at transpile time; we verify at ship time |
| Data validation | Reconciler: value-level diffs vs **live source** | `reconcile.sql`: row counts, keys, aggregates vs staged fixture expectations | **Lakebridge wins** on live value-level diffing; ours is fixture-based but CI-able, repeatable offline, and gate-enforced |
| Ship/no-ship decision | Human judgment | edw-gate: deterministic manifest (blockers, retries, verdict) as a table in the lakehouse | **Repo wins** — Lakebridge has no gate |
| Orchestration | Engineer runs CLI steps in order | Coordinator + stage subagents; Cursor hooks auto-fire retries on failure | **Repo wins** |
| Run observability | Assessment/reconcile dashboards | `ops.agent_events` event stream → AI/BI dashboard **+ Genie copilot** ("why did the gate fail?") | **Repo wins** on breadth |
| Everything as code | Config files + Excel reports | Contracts (JSON Schema), SQL, pipeline, dashboard, Genie space, docs — all git-versioned | **Repo wins** |
| Price | Free | $0 stack (Azure SQL free offer / offline seed + Free Edition) | **Parity** |

## Where Lakebridge is genuinely better — say this out loud

- **Breadth and scale.** Dozens of source dialects, ETL/orchestration tools,
  thousands of objects, GUI tracking. This repo handles one WWI-shaped T-SQL
  warehouse well.
- **Morpheus correctness guarantees.** AST-level equivalence proofs beat an
  LLM's promise for exotic T-SQL.
- **Value-level reconciliation against a live source.** Our fixtures are a
  demo-grade substitute.
- **Official product, partners, roadmap.** This repo is field-built
  enablement, not a supported product.

## Where Cursor + this repo closes the gap (the demo)

Every claim below is runnable code, not slideware:

| Lakebridge module | This repo's answer |
|---|---|
| Analyzer | [Assess stage](../agents/) → `migration_backlog.json` ([contract](../agents/contracts/)) |
| Transpiler (Switch, LLM) | [Convert stage](../agents/) + vendored T-SQL procs in [`legacy/procs/`](../legacy/procs/) |
| Reconciler | [`databricks/tests/reconcile.sql`](../databricks/tests/reconcile.sql) + staged fixture expectations |
| — (doesn't exist) | Deterministic **gate** (`migration_manifest.json`), auto-retry hooks, [`ops.agent_events` observability](../databricks/uc/03_ops_and_views.sql), [Genie copilot](../databricks/genie/space_config.json), [fault-injection self-healing arc](demo-script.md) |

The self-healing arc is the sharpest proof: inject legacy-side drift, the
reconcile check fails, the gate blocks the run, the retry hook fires, the
copilot explains the failure in plain English. That closed loop — convert,
verify, gate, observe, recover — is the operating model, and Lakebridge
leaves all of it to the engineer.

## The punchline: they compose

The honest enterprise answer isn't either/or. Lakebridge is an excellent
**conversion engine**; this repo is the **operating model around any
converter**. Swapping engines is a one-line change to the Convert stage:

```bash
databricks labs lakebridge transpile \
  --source-dialect mssql \
  --input-source legacy/procs/ \
  --output-folder databricks/converted/
```

The backlog contract, reconcile fixtures, deterministic gate, retry hooks,
dashboard, and Genie copilot all keep working unchanged. For a WWI-sized
estate, Cursor agents alone are nearly as good as Lakebridge. For a
thousand-object heterogeneous estate, put Lakebridge *inside* this pipeline
and keep everything else.

## Related

- [demo-script.md](demo-script.md) — objection handling row
- [runbook.md](runbook.md) — end-to-end operator guide
- [Lakebridge docs](https://databrickslabs.github.io/lakebridge/docs/overview/)
