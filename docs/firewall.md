# Firewall: Free Edition reachability

## Track A demo (Azure SQL)

`infra/azure/bootstrap.sh` creates two firewall rules on the Azure SQL logical server:

1. **`AllowClientLoad`** — your current public IP only. Used by `SqlPackage` / `sqlcmd`.
2. **`AllowDatabricksDemo`** — `0.0.0.0/0`. Used by Databricks Free Edition (AWS-hosted) to reach Azure SQL via Federation.

### Why `0.0.0.0/0`?

Free Edition outbound NAT IPs are not a stable allowlist. Azure “Allow Azure services” does **not** allow AWS → Azure SQL. For the **sample** DW only, open public access; tear down after the demo.

### Mitigations

1. Tear down when done (`make teardown`).
2. Strong admin password from `materialize_demo_env.sh`.
3. Optional early close:

```bash
az sql server firewall-rule delete \
  --resource-group "$AZ_RG" \
  --server "$AZ_SQL_SERVER" \
  --name AllowDatabricksDemo
```

## Track B — Azure MySQL Flexible Server

Same Free Edition physics: the warehouse must reach `SOURCE_HOST:3306`.

Demo one-liner (prefer lock-down for real data):

```bash
az mysql flexible-server firewall-rule create \
  --resource-group <rg> \
  --name <mysql-server-name> \
  --rule-name AllowDatabricksDemo \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 255.255.255.255
```

Also enable public access on the server if it is private-only. Prefer your client IP + known egress when possible.

SSL is required for MySQL Federation. This repo defaults `SOURCE_TRUST_SERVER_CERTIFICATE=true` for demo friction; set `false` when you have a proper trust path.

## Existing Azure SQL (non-demo)

Do **not** open `0.0.0.0/0` for real data. Use private link, VNet rules, or an allowlisted egress path for your Databricks tier.
