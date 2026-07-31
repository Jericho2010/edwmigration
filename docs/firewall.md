# Firewall: the `0.0.0.0/0` demo rule

`infra/azure/bootstrap.sh` creates two firewall rules on the Azure SQL
logical server:

1. **`AllowClientLoad`** — your current public IP only. Used by `SqlPackage`
   and `sqlcmd` from your machine.
2. **`AllowDatabricksDemo`** — `0.0.0.0/0` (the entire public internet). Used
   by Databricks Free Edition to reach Azure SQL via Lakehouse Federation.

## Why `0.0.0.0/0`?

Databricks Free Edition is **AWS-hosted**, not Azure-hosted. The Azure SQL
"Allow Azure services" toggle only allows traffic from inside the same
Azure region; it does NOT allow traffic from AWS. Free Edition's outbound
NAT IPs are not published as a stable allowlist, so the only reliable way
to let Free Edition reach Azure SQL is to open the server to the public
internet.

This is acceptable for a **demo database** that contains only public sample
data (WideWorldImporters) and is torn down after the demo. It is **not**
acceptable for any database with real or sensitive data.

## Risk

- Anyone on the internet can attempt to connect to your SQL server on port
  1433.
- They still need the admin username + password (which you set in `.env` and
  never commit), so the data is not directly exposed.
- Brute-force attacks are possible. Azure SQL has built-in brute-force
  protection, but it is not a substitute for a closed firewall.

## Mitigations

1. **Tear down when done.** `./infra/azure/teardown.sh` deletes the entire
   resource group, including the firewall rule.
2. **Use a strong admin password.** `.env.example` reminds you; do not use
   a weak password.
3. **Optional: auto-delete the rule after 2 hours.** Add this to `bootstrap.sh`
   or run it manually:
   ```bash
   nohup bash -c 'sleep 7200 && az sql server firewall-rule delete \
     --resource-group "$AZ_RG" --server "$AZ_SQL_SERVER" --name AllowDatabricksDemo' \
     >/tmp/firewall_autodelete.log 2>&1 &
   ```
4. **Optional: restrict to Databricks egress IPs.** If you can determine the
   current egress IPs for your Free Edition workspace (via a support ticket
   or by observing connection source IPs in `sys.dm_exec_connections`), you
   can replace `0.0.0.0/0` with a tighter CIDR. This is not portable for a
   self-serve demo, so we default to `0.0.0.0/0`.

## What to do if you forget to tear down

```bash
# Just delete the firewall rule (keep the DB if you want to re-run the demo):
az sql server firewall-rule delete \
  --resource-group "$AZ_RG" --server "$AZ_SQL_SERVER" --name AllowDatabricksDemo

# Or delete everything:
./infra/azure/teardown.sh
```

## Free Edition outbound restrictions

Even with `0.0.0.0/0` on the Azure SQL side, Free Edition's own outbound
network is restricted to a small allowlist. Azure SQL (`*.database.windows.net`)
is on the allowlist, so Federation works. If you see
`FAILED_JDBC.CONNECTION` errors that are not caused by a cold DB, they may
be Free Edition outbound restrictions — check the current Free Edition
docs for the allowlist.
