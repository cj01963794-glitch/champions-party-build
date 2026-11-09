# Frontier Battle Lab — Render deployment

This branch is isolated from the analysis/research default branch.
It contains the unchanged original Frontier battle engine and bundled web application 1.5 M-C + 423 ranker teams.

* `app.tar.br`: brotli-compressed tar of web app JS, CSS, HTML, team roster, original runtime adapters.
* `frontier.tar.gz`: exact Git blob shared with the existing research archive, SHA256 556c58cc4d55c05d7aef48785bf4907242fb0fbdc1ab5c402dbc1a72b6b9aabf.
* `Dockerfile`: builds node 24 runtime; no network downloads at startup.
* `render.yaml`: free preview blueprint. Free disk is ephemeral; persistent battle records need a separate paid persistent-disk plan.

Runtime requires environment variable FRONTIER_PASSWORD (at least 12 characters). Browser HTTP Basic authentication username: lab.
Health endpoint: /healthz. App records: /var/data/frontier.sqlite.
