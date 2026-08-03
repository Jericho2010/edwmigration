# Capture storyboard

Record three screenshots and one short video for the docs.

## Before you start

- Repo root open in Cursor
- `edw-demo-guide` available
- Logged into Azure + Databricks
- Control Plane and Genie already set up (`make setup` done earlier)

## Screenshots

Save over these files:

| Shot | File | What to show |
|---|---|---|
| 1 | `docs/img/cursor_open_repo.png` | File tree with `README.md`, `Makefile`, `.cursor` |
| 2 | `docs/img/cursor_pick_agent.png` | `edw-demo-guide` selected |
| 3 | `docs/img/cursor_kickoff.png` | Chat with: `Set up the EDW demo and walk me through the migration.` |

PNG, Cursor window only. No secrets on screen.

## Video (~40 seconds)

Record your screen. Save as `docs/media/hero.mp4`.

1. Cursor — select `edw-demo-guide`, paste the kickoff line, send. Show tools start, then cut.
2. Terminal — `make print-urls` (show the two links).
3. Browser — Control Plane dashboard.
4. Browser — Genie: ask `Did the last run ship?` Show the answer.

Cut out waiting. Gate does not need to be green.

Optional: make `docs/img/hero.gif` from the MP4 for the README, or leave that to the agent.

## Done

Tell the agent:

> Capture complete. Insert per docs/media/storyboard.md
>
> Files: cursor_*.png, docs/media/hero.mp4 (, hero.gif if you made one)
