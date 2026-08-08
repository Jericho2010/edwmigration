# Capture storyboard

Record three screenshots and one short video for the docs.

## Before you start

- Repo root open in Cursor
- `edw-start` / `edw-demo-guide` available (`make sync-prompts` if needed)
- You can log into Azure + Databricks when preflight asks
- Optional: Control Plane and Genie already set up from a prior run (`make setup`)

## Screenshots

Save over these files:

| Shot | File | What to show |
|---|---|---|
| 1 | `docs/img/cursor_open_repo.png` | File tree with `README.md`, `Makefile`, `.cursor` |
| 2 | `docs/img/cursor_pick_agent.png` | **`edw-start`** selected (or Agent chat ready for `start`) |
| 3 | `docs/img/cursor_kickoff.png` | Chat after `start`: soft status + numbered phrase menu (highlight reply **`1`**) |

PNG, Cursor window only. No secrets on screen.

Until reshot: docs caption the older images as “prefer `start`” in [cursor-ui.md](../cursor-ui.md).

## Video (~40 seconds)

Record your screen. Save as `docs/media/hero.mp4`.

1. Cursor — type `start`, show status + menu, reply `1`, allow tools, then cut.  
2. Terminal — `make print-urls` (show the two links).  
3. Browser — Control Plane dashboard.  
4. Browser — Genie: ask `Did the last run ship?` Show the answer.

Cut out waiting. Gate does not need to be green.

Optional: make `docs/img/hero.gif` from the MP4 for the README, or leave that to the agent.

## Done

Tell the agent:

> Screenshots and hero video are in place — refresh docs if captions still mention the old kickoff-only flow.
