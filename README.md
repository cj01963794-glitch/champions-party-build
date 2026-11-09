# Frontier Battle Lab 1.5 MC423 — Render Web

Public URL: https://frontier-battle-lab-web.onrender.com

This separate branch deploys the original engine with a mobile-friendly web interface, password-free.

## 2026-11-10: live result refresh fix
* Android native select boxes can keep DOM focus after selection. The original 2.3-second poll loop was incorrectly skipped as long as a `SELECT` was focused. This caused battle results to appear only after a manual page refresh.
* The poll now proceeds even if a `SELECT` remains focused. While focused, only the run results section is updated, without destroying and recreating the focused dropdown.
* Each currently running match now shows its current turn count and elapsed wall-clock seconds on screen.
* No battle algorithm, AI decision logic, or game rule has been changed.

## Existing memory mitigation
* Worker count 1, capped Node heap; static editor validation catalog avoids the second copy of the battle engine.
* Original game engine remains in `frontier.tar.gz` and is used by worker.
* A single Render Free 512 MiB/0.15 CPU instance can be **slow** under prolonged AI inference; this UI fix does not raise CPU resources or promise fast execution.
* The free instance can still restart or lose ephemeral saved battle records.
* No user authentication: anybody with the public URL can start battles and modify party data.
