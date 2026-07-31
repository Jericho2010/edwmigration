# docs/media — demo recordings

Terminal scenes behind the five GIFs in the [root README](../../README.md#watch-it-run).
Everything is recorded **live** against a real Databricks Free Edition
workspace (offline mode — no Azure); nothing is staged or typed over.

| Scene | Cast | GIF | Shows |
|---|---|---|---|
| `seed` | [casts/seed.cast](casts/seed.cast) | [../img/demo_seed.gif](../img/demo_seed.gif) | `seed_source.sh` — generated WWI CSVs → `source_fed` Delta tables |
| `job` | [casts/job.cast](casts/job.cast) | [../img/demo_job.gif](../img/demo_job.gif) | `databricks bundle run edw_migration_medallion -t dev` |
| `fault` | [casts/fault.cast](casts/fault.cast) | [../img/demo_fault.gif](../img/demo_fault.gif) | inject drift → reconcile 9/10 → Genie explains → revert → 10/10 |
| `genie` | [casts/genie.cast](casts/genie.cast) | [../img/demo_genie.gif](../img/demo_genie.gif) | `ask_genie.sh` — NL questions over gold marts |
| `manifest` | [casts/manifest.cast](casts/manifest.cast) | [../img/demo_manifest.gif](../img/demo_manifest.gif) | `make offline-gate` — the gate manifest as a table |

## Re-record

Prereqs: `asciinema` (pip) and `agg` (GitHub release binary) on `PATH`, plus
the usual repo env (`.env` or exported `DATABRICKS_*`), and `GENIE_SPACE_ID`
(from `make genie`).

```bash
export GENIE_SPACE_ID=<space id>
./docs/media/record_demo.sh all      # record + convert every scene, in order
./docs/media/record_demo.sh fault    # just one scene
./docs/media/record_demo.sh gif      # re-convert existing casts to GIFs
```

Record in the listed order so the data tells a coherent story (the fault arc
ends green, so re-recording is idempotent). Long warehouse waits are capped by
asciinema's `--idle-time-limit`; the narration typing speed is `TYPE_DELAY` in
`record_demo.sh`.

Replay any cast without recording:

```bash
asciinema play docs/media/casts/fault.cast
```

## The Genie questions in the film

`agents/tools/ask_genie.sh <space_id> "question"` calls the Genie Conversation
API from the terminal — the same space the UI uses
(`databricks/genie/space_config.json`). The fault-scene answer
("expected 1,000,000 vs actual 25,000") is Genie reasoning over
`ops.reconcile_results`, not a scripted line.
