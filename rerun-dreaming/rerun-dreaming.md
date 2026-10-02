# Re-run: is "stuck in `indexing`" explained by `dreaming: instant|dynamic`?

Run date: 2026-10-02 (IST), 21:33–21:47. supermemory-server 0.0.8 (lite, `workflow rivet`), local embeddings,
CPU-only box, mock OpenAI-compatible LLM (`mock_llm.py`). Each run used a fresh data dir and its own server/mock ports.
No API key is used or shown (server auto-applies a localhost key; any key in the logs is redacted).

## Setup
- Mock LLM answers the container-description call (`"description of a Supermemory container"`) after `DESC_DELAY` seconds, everything else instantly.
- One doc per run: `{"content":"I am vegetarian.","containerTag":"u1","dreaming":<mode>}`.
- Status polled via `GET /v3/documents/<id>` and search via `POST /v3/search {"q":"vegetarian","containerTags":["u1"]}` every ~10 s.
- The three runs were executed in parallel (separate servers/data dirs/ports).

| Run | dreaming | description delay | poll duration |
|---|---|---|---|
| A | `"instant"` | 35 s (> 30 s step timeout) | 420 s |
| B | `"dynamic"` (explicit) | 35 s | 840 s (14 min) |
| C (control) | `"dynamic"` (explicit) | 0 s | 420 s |

## Commands (exact)
```
cd /workspace/founder-outreach/supermemory
./rerun_dreaming.sh A_instant instant 35 6781 11581 420 &
./rerun_dreaming.sh B_dynamic dynamic 35 6782 11582 840 &
./rerun_dreaming.sh C_dynamic_nodelay dynamic 0 6783 11583 420 &
# args: label dreaming desc_delay_s server_port mock_port poll_seconds
# outputs: rerun_<label>/{timeline.txt,server.log,mock_llm.log,final_doc.json,request_body.json}
```
(Underlying calls: `curl localhost:$PORT/v3/documents -H 'Content-Type: application/json' -d '<body>'`, then `GET /v3/documents/$ID` and `POST /v3/search`.)

## Results
| Run | Status over time | Final status | Time to `done` | Search finds doc? |
|---|---|---|---|---|
| A instant, 35 s delay | queued (t+7s) → `indexing` from t+17s to t+411s (40 polls, never changed) | `indexing` | never (411 s observed) | yes, 1 hit from t+17s |
| B dynamic, 35 s delay | queued (t+7s) → `indexing` from t+17s to t+835s (82 polls, never changed) | `indexing` | never (835 s ≈ 14 min observed) | yes, 1 hit from t+17s |
| C dynamic, 0 s delay | queued (t+7s) → `done` at t+17s | `done` | ~17 s (first poll after queue) | yes |

### Server log lines
A and B (identical pattern):
```
[Workflow] Document <id> embedding 1 chunks (1 batches)
[Workflow] Document <id> stored 1 embedded chunks
[workflow] maintain-container-description ✗ Step "maintain-container-description" timed out after 30000ms
[Workflow] Document <id> embedding 1 chunks (1 batches)      <- re-run of earlier steps after the failure
[Workflow] Document <id> stored 1 embedded chunks
[workflow] maintain-container-description ✗ Rollback traversal halted
```
No "starting memory agent" / "finalized" line ever appears in A or B, even after 14 min. Nothing further is logged after "Rollback traversal halted".
Mock log: exactly one `desc` call (21:33:39) and no further LLM calls, in both A and B (so no retry, and the memory agent / dream step never calls the LLM).

C (control, no delay):
```
[Workflow] Document <id> embedding 1 chunks (1 batches)
[Workflow] Document <id> stored 1 embedded chunks
[Workflow] Document <id> starting memory agent (1 chunks)
[Workflow] Document <id> memory agent completed (32ms, 0 memories)
[21:33:39] [Workflow] Document <id> finalized: 1 chunks, 0 memories
```

## Docs on dream-cycle timing
- `apps/docs/concepts/how-it-works.mdx` ("Dreaming"): status `done` means chunks are indexed for search; memories come from a second phase, dreaming. `dynamic` (default) groups related documents; "Memory extraction may continue **after** `status: "done"`". `instant` dreams the doc on its own right away and bills one extra operation.
- `apps/docs/ingestion/add-memories.mdx` ("Processing Modes"): same description; `dreaming` parameter table says default `"dynamic"`.
- Neither page gives a dream-cycle interval or says that `indexing` can persist while waiting for a dream. Per the docs, dreaming affects when *memories* appear **after** `done`, not whether the document reaches `done`.

## Conclusion
- The stuck `indexing` is **not explained by dreaming mode**. With the container-description call taking > 30 s, the document stays `indexing` in both `instant` and `dynamic` (14 min observed for dynamic, no self-recovery). With the same `dynamic` mode and a fast description call (control C), the doc reaches `done` in ~17 s. So the variable is the description step timing out, not the dreaming flag.
- The document is searchable throughout; only the status is wrong/stuck. The workflow halts at "Rollback traversal halted" and never reaches the memory-agent/finalize step. (Earlier repro, `repro_stuck_indexing.sh`: restart with a fast LLM moved the same doc to `done`.)
- Caveats: single doc per run, no concurrent related documents (a real dynamic dream cycle groups related docs; I did not test how long a multi-doc batch would wait); the mock LLM returns "Nothing to store" for non-description calls so no memories are created in any run; `GET /v3/documents/<id>` did not echo a `dreaming` field (null in all three), so I can't confirm from the response that the server recorded the flag. Observed limit: 14 min for B — I can't rule out recovery beyond that, though the log shows the workflow halted.
