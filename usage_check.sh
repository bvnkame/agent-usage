#!/bin/bash
# Prints remaining quota (percent LEFT) for Claude / Codex / Agy from the Agent Usage server. Use before delegating work.
# Delegation rule (Games/CLAUDE.md): Codex only while 5h AND weekly left > 20%; else agy; then Claude directly.
cd "$(dirname "$0")"
PORT=${PORT:-4777}
started=0
if ! curl -s --max-time 2 "http://127.0.0.1:$PORT/api/usage" -o /tmp/usage.json; then
  (PORT=$PORT node server.js >/dev/null 2>&1 &); started=1; sleep 3
  curl -s --max-time 40 "http://127.0.0.1:$PORT/api/usage" -o /tmp/usage.json
fi
[ $started = 1 ] && pkill -f "node server.js"
python3 - <<'PY'
import json
for a in json.load(open("/tmp/usage.json")):
    lim = a.get("limits") or []
    if not lim: print(f'{a["agent"]:7} (no quota API) {a.get("note","")}'); continue
    print(f'{a["agent"]:7}', " | ".join(f'{l["label"]}: {100-float(l["percent"]):.0f}% left, resets {l["resetsAt"][:16]}' for l in lim if "Credits" not in l["label"]))
PY
