# infra/azure/ — demo-pack Azure SQL provisioning

Provisions and tears down the **optional** free Azure SQL WideWorldImportersDW
source used by the guided demo. Not required for path B (existing Azure SQL).

Operator guide: [docs/runbook.md](../../docs/runbook.md). Demo pack notes: [demo/wwi/README.md](../../demo/wwi/README.md).

## Files

| File | Purpose |
|---|---|
| `bootstrap.sh` | RG, SQL server, free DB, firewall, bacpac import, warmup, proc/fixture export, Databricks secret scope |
| `teardown.sh` | Deletes the resource group (idempotent) |
| `.env.example` | Template for repo-root `.env` (gitignored) |

## Guided demo (preferred)

```bash
# In Cursor (preferred): type start → choose 1
# Or launch edw-demo-guide with the demo phrase.
# Log in only when preflight asks (az login / databricks auth).
```

The guide runs preflight, then `materialize_demo_env.sh` (writes `.env`) then `make bootstrap` for you.

## Scripted

```bash
./agents/tools/materialize_demo_env.sh   # or cp .env.example → .env and edit
make bootstrap                           # ~10 min
make teardown                            # when finished
```

## Free offer constraints

- 100,000 vCore-seconds / month per subscription
- 32 GB data + 32 GB backup per DB
- Up to 10 free DBs; first free DB locks the region
- `AutoPause` on limit exhaustion

See [docs/limits.md](../../docs/limits.md).

## Firewall warning

`bootstrap.sh` creates `AllowDatabricksDemo` (`0.0.0.0/0`) so Databricks Free
Edition can reach Azure SQL. **Tear down after the demo.** See
[docs/firewall.md](../../docs/firewall.md).
