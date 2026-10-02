# Supermemory

Notes from self-hosting `supermemory-server` 0.0.8 (the single-binary "lite" server from <https://supermemory.ai/install>) on a CPU-only
Linux box, with a local OpenAI-compatible LLM endpoint and no real keys, and ingesting and searching per-user facts by
`containerTag`.

What worked: the one-command install, a fast start (about 3 s to ready), search, and per-tag isolation, which held in my run.
This repository records three rough edges, all re-checked on 2 Oct 2026.

## Environment

| | |
|---|---|
| Server | `supermemory-server` 0.0.8, the latest release tag on 2 Oct 2026. Its `--version` prints `1.3.4`, which is the bun runtime version, not the release (issue #1704's environment line shows the same; I am not claiming it as a bug) |
| Docs | `supermemoryai/supermemory` @ `bce2d0d` (1 Oct 2026), `apps/docs/self-hosting/quickstart.mdx` |
| LLM | a deterministic mock OpenAI-compatible server, [`mock_llm.py`](mock_llm.py), so no key and no model are needed for the repros |
| Embeddings | local, `Xenova/bge-base-en-v1.5` (768d), as the server's start-up banner says |

## Rough edges

### 1. The installer dies without a controlling terminal

```bash
./repro_install_no_tty.sh
```
`curl -fsSL https://supermemory.ai/install | bash`, or the saved script, run from CI, Docker without `-t` or an agent shell, reaches
"Pick a provider ... 4) Skip for now" and then exits 1 with `install.sh: line 254: /dev/tty: No such device or address`.
The script's `have_tty()` only tests the `-r` and `-w` permission bits on `/dev/tty`, which pass even when there is no controlling
terminal. The workaround is `SUPERMEMORY_NO_PROMPT=1`, which the output does not mention.

Patch: [`supermemory-installer-notty.patch`](supermemory-installer-notty.patch) actually tries to open `/dev/tty`. It also makes the
"already installed" short-circuit require the symlink in `BIN_DIR` to exist. It is against the install script as served for 0.0.8,
not a git checkout. Known? I searched the issues for `/dev/tty` and `NO_PROMPT` and found nothing.

### 2. A document stays in `indexing` when the LLM is slow

```bash
SM_BIN=/path/to/supermemory-server ./repro_stuck_indexing.sh      # about 5 minutes; no external keys
```
If the container-description LLM call takes longer than 30 s, which is plausible for a CPU-only local model, the server logs

```
[workflow] maintain-container-description ✗ Step "maintain-container-description" timed out after 30000ms
[workflow] maintain-container-description ✗ Rollback traversal halted
```
and the document stays at `status: indexing` for at least 180 s. It is already searchable (1 hit), but after the restart the same
data directory moves it to `done`. The repro uses a mock LLM that delays only the description call by 35 s. The 2 Oct run matched
the earlier one: [`evidence/repro_stuck_indexing_2oct.out`](evidence/repro_stuck_indexing_2oct.out) and
[`evidence/repro_stuck_indexing_earlier_run.out`](evidence/repro_stuck_indexing_earlier_run.out). The server log of the final run, with
the auto-generated local API key redacted, is in [`evidence/repro_server_2oct.log`](evidence/repro_server_2oct.log) (that run's log
shows the fast path after the restart).

Known? I searched for `maintain-container-description`, `30000` and "stuck"; #1455 ("stuck queued", v0.0.6) is a different bug.
There is no patch for this one; I have not looked for the right fix (a longer step timeout, or not rolling back the document status).

### 3. The self-hosting quickstart's search call returns nothing

`apps/docs/self-hosting/quickstart.mdx` searches `/v3/search` with `"containerTag": "user_dhravya"`. That returns HTTP 200 with
`{"results":[],"total":0}`, while `"containerTags": ["user_dhravya"]` returns the document. This is **already reported as #1704**
(open, 27 Sep 2026), but the docs still had it on 2 Oct. [`supermemory-docs-v3-search-containerTags.patch`](supermemory-docs-v3-search-containerTags.patch)
is the one-line doc fix.

## Files

| Path | What |
|---|---|
| `repro_install_no_tty.sh`, `supermemory-installer-notty.patch` | rough edge 1 |
| `repro_stuck_indexing.sh`, `mock_llm.py` | rough edge 2 (the script starts the server and the mock itself) |
| `supermemory-docs-v3-search-containerTags.patch` | rough edge 3 |
| `evidence/` | outputs of the 2 Oct run, with the local API key redacted |

Not included: the server binary and runtime (hundreds of MB), local data directories, and the upstream source clone.
