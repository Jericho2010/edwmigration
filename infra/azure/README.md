# infra/azure/ — Azure SQL EDW provisioning

Provision and tear down the free Azure SQL EDW used as the migration source.
Full operator path: [docs/runbook.md](../../docs/runbook.md).

## Files

| File | Purpose |
|---|---|
| `bootstrap.sh` | RG, SQL server, free DB, firewall, bacpac import, warmup, proc/fixture export, Databricks secret scope |
| `teardown.sh` | Deletes the resource group (idempotent) |
| `.env.example` | Copy to repo-root `.env` (gitignored) |

## Quickstart

```bash
cp infra/azure/.env.example .env
$EDITOR .env
set -a; . ./.env; set +a

./infra/azure/bootstrap.sh --dry-run
./infra/azure/bootstrap.sh             # ~10 min

# After the demo:
./infra/azure/teardown.sh
```

## Free offer constraints

- 100,000 vCore-seconds / month per subscription
- 32 GB data + 32 GB backup per DB
- Up to 10 free DBs per subscription
- `AutoPause` on limit exhaustion (never charges beyond the allowance)
- First free DB locks the region for all free DBs on the subscription

See [docs/limits.md](../../docs/limits.md) for full details.

## Firewall warning

`bootstrap.sh` creates an `AllowDatabricksDemo` rule with `0.0.0.0/0` so
Databricks Free Edition (AWS-hosted) can reach the SQL server. This opens the
server to the public internet. **Run `teardown.sh` after the demo.** See
[docs/firewall.md](../../docs/firewall.md) for the risk and an optional 2h
auto-delete safety net.
