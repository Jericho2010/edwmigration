# SE demo script

Audience talk track. Product narrative: [Guided demo](guided-demo.md) · [Getting started](getting-started.md) · [Using Cursor](cursor-ui.md).

For platform buyers after the wow: open [Enterprise](enterprise.md) (SoD / no public FW).

## 15 minutes

1. Prospect: open the **repo root** in Cursor (logins come when preflight asks).
2. You: type **`start`** → choose **1** (or launch **`edw-demo-guide`** with the demo phrase).
3. Show Control Plane dashboard hero (Gate / counts) as events appear.
4. After Gate: Genie — “Did the last run ship?” / “Why did the gate fail?”
5. Objection: Lakebridge? → [lakebridge.md](lakebridge.md) — this path wins on operating model for Azure SQL → UC.

## 30–45 minutes

Add: open inventory counts after Assess; after a Convert wave, show two `agents/out/<run_id>/convert/*.json` files plus Control Plane agent events; open a converted silver/gold notebook; inject fault (`inject_fault.sh`) → Gate blocks → revert → green; teardown (menu **5** or ask the guide).

## Takeaways

- User effort is permissions + type `start` + pick a number (fix only what preflight names).
- Engine is not coupled to WWI object names — add tables/procs and re-Assess.
- Observability demystifies the agents.
