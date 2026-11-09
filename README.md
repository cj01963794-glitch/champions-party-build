# Frontier Battle Lab 1.5 MC423 — Render Web

Public URL: https://frontier-battle-lab-web.onrender.com

Deployed to Render Free in the Singapore region from this isolated branch. The original Frontier battle engine and AI are not changed.

## Update 2026-11-10: login removed + OOM mitigation

* No username/password is required. Anyone with the URL can access the site and edit/delete parties or launch battles.
* Root cause of the original `Unexpected token 'S', Starting F...` failure: the server was killed when it exceeded the 512 MiB Render Free memory limit. During restart `/api/state` returned non-JSON text.
* The HTTP process now loads a verified static snapshot of the original editor/legal-move catalog instead of initializing an entire duplicate battle engine. The original engine is still used in the battle worker.
* Start Node.js with `--expose-gc --max-old-space-size=256`; release temporary forecast objects at turn boundaries, leaving AI decisions and combat logic unchanged.
* During startup the API returns a valid JSON 503 error, and the client interprets non-JSON 502/503/504 replies properly.
* App package: `app.tar.br` (Brotli TAR); original engine: `frontier.tar.gz`.
* Persistent battle data is **not** guaranteed on Render Free: restarting/redeploying the server can erase games and party edits.
* Do not use this freely accessible site for private data or sensitive credentials.

Worker memory is materially lower in a local bounded-heap test. This does not guarantee all team matchups will remain within Render's 512MiB limit; monitor Render events for `oomKilled`. 
