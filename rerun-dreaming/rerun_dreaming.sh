#!/usr/bin/env bash
# Usage: rerun_dreaming.sh <label> <dreaming|none> <desc_delay_s> <sm_port> <mock_port> <duration_s>
# Starts a fresh supermemory-server 0.0.8 (fresh data dir) against mock_llm.py, adds one doc, polls status every 10s.
set -u; cd "$(dirname "$0")"
L=$1; MODE=$2; DELAY=$3; PORT=$4; MPORT=$5; DUR=$6
OUT=rerun_$L; mkdir -p $OUT; DATA=$(mktemp -d)
MOCK_PORT=$MPORT DESC_DELAY=$DELAY python3 mock_llm.py > $OUT/mock_llm.log 2>&1 & MPID=$!
sleep 1
(cd "$DATA" && SUPERMEMORY_PORT=$PORT SUPERMEMORY_NO_UPDATE_CHECK=1 OPENAI_BASE_URL=http://127.0.0.1:$MPORT/v1 OPENAI_API_KEY=x OPENAI_MODEL=mock \
  exec "$OLDPWD/sm-install/bin/supermemory-server" > "$OLDPWD/$OUT/server.raw.log" 2>&1) & SPID=$!
until curl -s localhost:$PORT/v3/documents/x >/dev/null 2>&1; do sleep 2; done; sleep 5
if [ "$MODE" = none ]; then BODY='{"content":"I am vegetarian.","containerTag":"u1"}'; else BODY="{\"content\":\"I am vegetarian.\",\"containerTag\":\"u1\",\"dreaming\":\"$MODE\"}"; fi
echo "$BODY" > $OUT/request_body.json
T0=$(date +%s); echo "T0 $(date +%H:%M:%S) add body: $BODY" > $OUT/timeline.txt
RESP=$(curl -s localhost:$PORT/v3/documents -H 'Content-Type: application/json' -d "$BODY"); echo "add response: $RESP" >> $OUT/timeline.txt
ID=$(echo "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
DONE=""
while [ $(( $(date +%s) - T0 )) -lt $DUR ]; do
  S=$(curl -s localhost:$PORT/v3/documents/$ID | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['status'])")
  H=$(curl -s localhost:$PORT/v3/search -H 'Content-Type: application/json' -d '{"q":"vegetarian","containerTags":["u1"]}' | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])")
  E=$(( $(date +%s) - T0 )); echo "t+${E}s status=$S search_hits=$H" >> $OUT/timeline.txt
  if [ "$S" = done ] && [ -z "$DONE" ]; then DONE=$E; echo "DONE_AT $E" >> $OUT/timeline.txt; fi
  sleep 10
done
curl -s localhost:$PORT/v3/documents/$ID | python3 -m json.tool > $OUT/final_doc.json
echo "FINAL doc: $(python3 -c "import json;d=json.load(open('$OUT/final_doc.json'));print({k:d.get(k) for k in ('status','dreaming','createdAt','updatedAt')})")" >> $OUT/timeline.txt
kill $SPID $MPID 2>/dev/null; sleep 2; pkill -P $SPID 2>/dev/null
sed -E 's/sm_[A-Za-z0-9_]{20,}/sm_<redacted>/g' $OUT/server.raw.log > $OUT/server.log; rm -f $OUT/server.raw.log
echo finished >> $OUT/timeline.txt
