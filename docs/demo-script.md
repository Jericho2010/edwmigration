# Demo script (field / SE)

Timed talk tracks for presenting this repo to a technical prospect.
Leave them with: **https://github.com/Jericho2010/edwmigration**

Prep once: complete [runbook](runbook.md) through medallion deploy so the
dashboard and tables exist. Keep Azure warm (`SELECT 1` via sqlcmd) before
the meeting.

---

## 15-minute version (hallway / discovery)

| Min | Screen / cue | Say |
|---|---|---|
| 0–2 | GitHub README | “Self-serve EDW migration demo: free Azure SQL → Databricks Free Edition, Cursor agents, live AI/BI observability. Zero cost if you tear down.” |
| 2–5 | Architecture diagram | “Source is WideWorldImportersDW — real star schema and Integration.* stored procs, not AdventureWorks OLTP. We federate into UC, then bronze → silver → gold.” |
| 5–8 | Job run / Catalog Explorer | “One Lakeflow Job lands and transforms. Reconcile compares gold to fixtures exported from the legacy procs.” |
| 8–12 | Cursor + dashboard | “Coordinator drives Assess → Convert → Test → Gate. Hooks stream agent events into `ops.agent_events` — same dashboard you’d leave with a customer.” |
| 12–15 | Manifest + teardown story | “Gate is deterministic ship/no-ship. Firewall is open for Free Edition egress on sample data only — teardown deletes the RG.” |

**Leave-behind:** clone URL + [prerequisites](prerequisites.md) + “run the runbook weekend.”

---

## 30-minute version (technical deep dive)

| Min | Screen / cue | Say |
|---|---|---|
| 0–3 | README “What you get” | Frame audience: SE enablement + prospect self-serve. |
| 3–8 | Azure portal or bootstrap log | Free offer, AutoPause, why bacpac (not bak), why `0.0.0.0/0` ([firewall.md](firewall.md)). |
| 8–14 | Federation SQL + `wwi_dw_fed` | Lakehouse Federation on serverless; why not Lakeflow Connect on Free Edition ([lakeflow_connect.md](lakeflow_connect.md)). |
| 14–20 | Medallion notebooks + job DAG | Show fan-out under 5 concurrent tasks; SCD2 customer; gold marts mapped to Integration.* outcomes. |
| 20–26 | Cursor agent run (or sample artifacts) | Write model: readonly stages return JSON; Convert lands in `databricks/converted/` so baselines stay job-safe. |
| 26–30 | AI/BI dashboard + manifest | Hooks → Delta → dashboard; Gate blockers; teardown. |

**Optional live path:** kick off `edw-coordinator` mid-meeting and narrate events as they appear (have `CURRENT_RUN` and warehouse warm).

---

## Self-healing arc (10 min, add to the 30/45-min versions)

The gate-is-the-hero segment. Precondition: a green run exists (medallion
job + one coordinator run completed; `ops.fixture_expectations` staged).

| Min | Screen / cue | Say |
|---|---|---|
| 0–1 | Terminal | “The migration pattern only matters if it catches drift. Watch.” Run `./agents/tools/inject_fault.sh --fixture fact_sale_count`. |
| 1–4 | Cursor | “Legacy moved under us — stale export, changed business rule, whatever.” Ask the coordinator to re-run Test and Gate. Reconcile fails `fixture_fact_sale_count`; the manifest comes back `gate: fail` with the blocker. |
| 4–6 | Dashboard | “Nothing shipped. The blocker is a row in `ops.agent_events` and the manifest — not a Slack message.” Show the hook's retry follow-up firing in Cursor. |
| 6–9 | Terminal | “The DBA confirms the export was stale.” Run `./agents/tools/inject_fault.sh --revert`, re-run Test + Gate in Cursor. Manifest flips to `gate: pass`. |
| 9–10 | Manifest | “Deterministic ship/no-ship, human-in-the-loop where it matters, full audit trail in the lakehouse.” |

If the prospect asks “could the agent fix it itself?”: a *logic* fault in a
converted notebook — yes, that's the Convert retry path (`max_retries: 2`).
A *data* fault like this one — correctly no; the gate forces a human
decision. Both answers are the product story.

---

## Genie copilot (5 min, closer)

Natural-language layer over the same tables — the "executive asks a question"
beat. Precondition: medallion job has run, then `make genie` (deploys the
"EDW Migration Copilot" space from `databricks/genie/space_config.json`).

| Min | Screen / cue | Say |
|---|---|---|
| 0–1 | Genie room | "Everything you just saw — the runs, the gate, the marts — is queryable in plain English. No SQL, no dashboard-building." |
| 1–3 | Ask: **"Why did the last migration run fail the gate?"** | Genie answers from `ops.reconcile_results` — the failing check, expected vs actual, the delta. Show the generated SQL: it's the certified example shipped in `space_config.json`, not a guess. |
| 3–4 | Ask: **"Which legacy stored procedures have been converted?"** | Answer comes from `ops.proc_conversion_map`. "The audit trail the gate uses is the same one your stakeholder queries conversationally." |
| 4–5 | Ask: **"Top 10 stock items by gross revenue?"** | Switch domains: same space also serves the migrated gold marts. "One copilot for 'did the migration work' *and* 'was it worth migrating'." |

The space is code: `databricks/genie/space_config.json` holds the table list,
vocabulary instructions, and certified Q&A, deployed idempotently by
`create_genie_space.sh`. Version-control the copilot the same way you
version-control the pipeline.

---

## 45-minute version (workshop)

Follow the [runbook](runbook.md) live with the prospect driving the keyboard where possible.

1. **Configure** (.env) — 5 min  
2. **Bootstrap Azure** (or show pre-provisioned) — 10 min  
3. **Federation + ops tables** — 5 min  
4. **Bundle deploy + job run** — 10 min (narrate DAG while it runs)  
5. **Cursor coordinator** — 10 min  
6. **Inspect gold / reconcile / dashboard / tear down** — 5 min  

Offline fallback if Azure free allowance is exhausted: copy
[agents/samples/run/](../agents/samples/run/) into `agents/out/<run_id>/`
and walk Gate + manifest + dashboard schema.

---

## Objection handling (short)

| Objection | Response |
|---|---|
| “Free Edition isn’t production.” | Correct — this proves the *migration pattern* and agent operating model. Production = same UC/medallion ideas on a paid workspace, often with Lakeflow Connect or private networking. |
| “Opening SQL to 0.0.0.0/0 is crazy.” | Agree for real data. Acceptable only for public sample + teardown. Paid path: private link / allowlisted egress. |
| “Agents will hallucinate SQL.” | Gate + reconcile fixtures are the control plane; Convert is draft; ship/no-ship is deterministic. |
| “Why not dbt / ADF / …?” | Out of scope. The teaching surface is UC + serverless SQL + agent stages + product observability. |

---

## Prospect takeaways (say these explicitly)

1. You can clone and run this without a Databricks AE in the room.  
2. Federation + medallion is the Free Edition–legal path; Connect needs classic compute.  
3. Agent migration is useful when paired with **contracts, reconcile, and a gate**.  
4. Observability belongs in the lakehouse (`ops.agent_events`), not a laptop log file.
