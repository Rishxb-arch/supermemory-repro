#!/usr/bin/env bash
# Repro: supermemory-server v0.0.8 document stuck in "indexing" when the container-description LLM call takes >30 s.
# Needs: supermemory-server on PATH (or SM_BIN), python3. No external keys; uses mock_llm.py.
set -u; cd "$(dirname "$0")"; SM_BIN=${SM_BIN:-./sm-bin/supermemory-server}; PORT=6768
DATA=$(mktemp -d); mock() { (DESC_DELAY=$1 python3 mock_llm.py >> mock_llm.log 2>&1 &) ; sleep 1; }; mock ${DESC_DELAY:-35}
smkill() { pkill -f "bin/supermemory-server" ; sleep 3; }
start() { (cd "$DATA" && SUPERMEMORY_PORT=$PORT SUPERMEMORY_NO_UPDATE_CHECK=1 OPENAI_BASE_URL=http://127.0.0.1:11501/v1 OPENAI_API_KEY=x OPENAI_MODEL=mock nohup "$OLDPWD/$SM_BIN" > "$OLDPWD/repro_server.log" 2>&1 &); sleep 30; }
st() { curl -s localhost:$PORT/v3/documents/$1 | python3 -c "import sys,json;print(json.load(sys.stdin)['status'])"; }
start
ID=$(curl -s localhost:$PORT/v3/documents -H 'Content-Type: application/json' -d '{"content":"I am vegetarian.","containerTag":"u1"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
for t in 20 60 120 180; do sleep $(( t - ${prev:-0} )); prev=$t; echo "t+${t}s status=$(st $ID)"; done
echo "search (containerTags) hits: $(curl -s localhost:$PORT/v3/search -H 'Content-Type: application/json' -d '{"q":"vegetarian","containerTags":["u1"]}' | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])")"
grep -E 'timed out|sleep until|Rollback' repro_server.log | head -4
echo "--- restarting server on the same data dir, LLM now answers the description call instantly"
smkill; pkill -f mock_llm.py; mock 0; start; sleep 20; echo "after restart status=$(st $ID)"
smkill; pkill -f mock_llm.py; echo "data dir: $DATA"
