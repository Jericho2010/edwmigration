# infra/azure/ — Azure SQL EDW provisioning

Scripts to provision and tear down the free Azure SQL EDW used as the
migration source.

## Files

- `bootstrap.sh` — provisions RG, SQL server, free-offer DB, firewall rules,
  imports the bacpac, warms up the serverless DB, exports proc source and
  fixtures, and creates the Databricks secrets scope.
- `teardown.sh` — deletes the entire resource group (idempotent).
- `.env.example` — copy to `.env` and fill in values.

## Quickstart

```bash
# 1. Copy .env.example to .env and fill in values
cp infra/azure/.env.example .env
$EDITOR .env

# 2. Source .env
set -a; . ./.env; set +a

# 3. Dry-run to validate
./infra/azure/bootstrap.sh --dry-run

# 4. Real run (~10 min)
./infra/azure/bootstrap.sh

# 5. When done, tear down
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
