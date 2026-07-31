# Agent-converted notebooks

Convert stage output lands here so **baseline** `databricks/silver/` and
`databricks/gold/` files used by the medallion job DAG stay intact.

When Assess/Convert maps a proc to a path that already has a baseline file,
write `databricks/converted/<same-basename>.sql` instead and report that path
in mapping notes (`ops.proc_conversion_map`).

See [agents/prompts/02_convert.md](../agents/prompts/02_convert.md).
