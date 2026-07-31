# Makefile — one-command orchestration for the EDW migration demo.
#
#   make demo       — full path: prereqs → Azure → federation → deploy → job run
#   make teardown   — delete the Azure resource group
#
# Requires .env (cp infra/azure/.env.example .env and edit). The .env file is
# included below, so its variables are visible to every target; keep values
# free of '#' and trailing spaces (Make comment rules apply).
# Detail and failure modes: docs/runbook.md.

SHELL := /usr/bin/env bash

-include .env
export

# DAB takes the warehouse as a bundle variable, not a plain env var.
BUNDLE_VAR_warehouse_id := $(DATABRICKS_WAREHOUSE_ID)
export BUNDLE_VAR_warehouse_id

TOOLS := az sqlcmd SqlPackage databricks jq curl python3

.PHONY: check bootstrap federation deploy run demo teardown offline-gate

check: ## Verify tools and .env
	@for t in $(TOOLS); do \
		command -v $$t >/dev/null 2>&1 || { echo "missing tool: $$t — see docs/prerequisites.md" >&2; exit 1; }; \
	done
	@test -f .env || { echo ".env missing — cp infra/azure/.env.example .env and edit it" >&2; exit 1; }
	@test -n "$(AZ_SUBSCRIPTION_ID)" || { echo "AZ_SUBSCRIPTION_ID not set (source .env first: set -a; . ./.env; set +a)" >&2; exit 1; }
	@echo "prereqs OK ($(TOOLS))"

bootstrap: check ## Provision Azure SQL + load the bacpac + export procs/fixtures
	./infra/azure/bootstrap.sh

federation: check ## UC federation setup + ops tables
	./agents/tools/render_federation_sql.sh > /tmp/01_fed.sql
	./agents/tools/run_sql.sh --file /tmp/01_fed.sql
	./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql

deploy: check ## Bundle validate + deploy (dev target)
	databricks bundle validate -t dev
	databricks bundle deploy -t dev

run: ## Run the medallion job
	databricks bundle run edw_migration_medallion -t dev

demo: bootstrap federation deploy run ## Full end-to-end setup
	@echo
	@echo "Infra ready. Next: open this repo in Cursor and launch edw-coordinator"
	@echo "(kickoff text in docs/runbook.md §6). Watch the AI/BI dashboard"
	@echo "'[dev] EDW Migration Agent Events'."

teardown: ## Delete the Azure resource group
	./infra/azure/teardown.sh

offline-gate: ## Seed sample artifacts for the offline Gate demo (no Azure)
	RUN_ID=00000000-0000-4000-8000-000000000001; \
	mkdir -p "agents/out/$$RUN_ID"; \
	cp agents/samples/run/* "agents/out/$$RUN_ID/"; \
	echo "$$RUN_ID" > agents/out/CURRENT_RUN; \
	./agents/tools/render_manifest_table.py "agents/out/$$RUN_ID/migration_manifest.json"
