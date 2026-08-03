# How to capture screenshots and the hero video

You need **two things**:

1. **Three screenshots** of Cursor (replace the fake ones in the docs).
2. **One short video** (Cursor → Databricks dashboard → Genie).

When you’re done, put the files where this page says and tell the agent: *insert per storyboard*.

Use **Track A** (guided demo). Real UI only — no mockups.

---

## Do this today (checklist)

**First — setup (once)**

- [ ] Open this repo’s **root** in Cursor (you should see `README.md`, `Makefile`, `.cursor`).
- [ ] Agent **`edw-demo-guide`** is available (`make sync-prompts` if not).
- [ ] Logged in: `az login` and Databricks (or PAT in `.env`).
- [ ] You can open Databricks in a browser (serverless warehouse exists).
- [ ] Control Plane + Genie already work from a prior `make setup`.  
  If not: finish [guided demo](../guided-demo.md) setup first, then come back.  
  You do **not** need a perfect Gate pass to record.

**Then — screenshots (about 15 minutes)**

- [ ] S1 → save as `docs/img/cursor_open_repo.png`
- [ ] S2 → save as `docs/img/cursor_pick_agent.png`
- [ ] S3 → save as `docs/img/cursor_kickoff.png`

**Then — video (about 20–40 minutes including cuts)**

- [ ] Record four short clips (or one continuous take — see below).
- [ ] Export final as `docs/media/hero.mp4`
- [ ] GIF is optional; skip it unless you want it. The agent can make one later.

**Then — hand off**

- [ ] Message the agent with the handoff block at the bottom of this page.

---

## Screenshots

**Rules for all three**

- PNG.
- Roughly widescreen (e.g. 1920×1080).
- Cursor window only.
- Text readable when the image is shrunk on GitHub.
- Don’t show `.env`, tokens, or passwords.

### S1 — Repo root

**Save as:** `docs/img/cursor_open_repo.png`

1. File → Open Folder → this repo’s root.
2. Show the file tree.
3. Make sure these are visible: `README.md`, `Makefile`, `.cursor`.
4. Screenshot.

### S2 — Pick the agent

**Save as:** `docs/img/cursor_pick_agent.png`

1. Open Agent / Chat.
2. Select **`edw-demo-guide`** (it must be obviously selected).
3. If you can also see `edw-coordinator` in the list, good.
4. Screenshot.

### S3 — Kickoff line

**Save as:** `docs/img/cursor_kickoff.png`

1. Start a clean chat with `edw-demo-guide`.
2. Paste exactly:

   `Set up the EDW demo and walk me through the migration.`

3. Screenshot with that text visible (before or as you send is fine).
4. Don’t screenshot a huge failed log.

---

## Video

**Save as:** `docs/media/hero.mp4`  
**Length:** about 35–50 seconds after edits. Silent is fine; captions help.

### Easiest path: four short clips

Record each, stop, start the next. Name them anything on your machine; finals matter more than raw names.

| Order | Record this | Stop when |
|---|---|---|
| 1 | Cursor: `edw-demo-guide` + paste/send the kickoff line | Message is sent / tools start |
| 2 | Cursor or terminal: something that shows setup progressing or `make print-urls` output | URLs or “setup complete” visible |
| 3 | Browser: Control Plane dashboard | Gate / inventory / migration widgets visible |
| 4 | Browser: Genie — ask **Did the last run ship?** | Answer is on screen |

Stitch 1→2→3→4 into `docs/media/hero.mp4`.  
Jump-cut any long waits. Don’t sit through bacpac import on camera.

### If you prefer one continuous recording

Same order on one timeline:

1. Cursor + kickoff (send it).
2. Brief tools activity (cut the boring middle).
3. Switch to Control Plane.
4. Switch to Genie question + answer.
5. Stop.

### If Gate isn’t green

Still film Control Plane and Genie. A real “not shipped / blocked” answer is better than faking a pass.

### Recording settings (keep simple)

- 1080p if you can, 720p minimum.
- MP4 (H.264).
- Zoom the browser a bit so dashboard text is readable.

Skip YouTube, ffmpeg, and GIF for now unless you already know how.

---

## Privacy

**Hide or crop:** tokens, passwords, connection strings, subscription IDs.  
**Fine to show:** agent names, kickoff sentence, catalog name like `edw_migration`, demo/WWI-style answers.

---

## When you’re done — send this

```text
CAPTURE COMPLETE
Date:
Cursor version:
Gate green: yes/no

Files:
- docs/img/cursor_open_repo.png
- docs/img/cursor_pick_agent.png
- docs/img/cursor_kickoff.png
- docs/media/hero.mp4

Notes:
```

Then: *Insert these into README and cursor-ui per docs/media/storyboard.md*

---

## For the person editing the repo (not you while recording)

1. Overwrite the three `docs/img/cursor_*.png` files.
2. Add `docs/media/hero.mp4` (and `docs/img/hero.gif` only if someone makes one).
3. Under README Status, add a short “See it” blurb linking the video/GIF.
4. In `cursor-ui.md`, drop any “illustration / mock” wording.
5. Set the Status date to the capture day.
6. If `hero.mp4` is huge for git, put the video on a release or unlisted YouTube and keep a small GIF in-repo.

---

## Related

- [Guided demo](../guided-demo.md)
- [Using Cursor](../cursor-ui.md)
