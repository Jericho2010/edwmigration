# SE demo script

Audience talk track. Product narrative for learners: [Guided demo](guided-demo.md) · [Getting started](getting-started.md).

## 15 minutes

1. Prospect: `az login` + Databricks workspace auth.
2. You: launch **`edw-demo-guide`** — “Set up the EDW demo and walk me through the migration.”
3. Show Control Plane dashboard hero (Gate / counts) as events appear.
4. After Gate: Genie — “Did the last run ship?” / “Why did the gate fail?”
5. Objection: Lakebridge? → [lakebridge.md](lakebridge.md) — this path wins on operating model for Azure SQL → UC.

## 30–45 minutes

Add: open inventory counts after Assess; show a converted silver/gold notebook; inject fault (`inject_fault.sh`) → Gate blocks → revert → green; teardown.

## Takeaways

- User effort is permissions + one sentence to the guide agent.
- Engine is not coupled to WWI object names — add tables/procs and re-Assess.
- Observability demystifies the agents.
