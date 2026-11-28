# RAG Evaluation – Environment Snapshot

> Frozen state of data, code and configuration used for this evaluation round.
> Do not run the Databricks Job while this snapshot is active.

## Round

| Item | Value |
|---|---|
| Round | `v1` |
| Snapshot taken | `2026-11-15` |
| Author | `Lu` |

## Code

| Item | Value |
|---|---|
| Git commit | `1c9f780` (`main` after PR #9; same tree as `5144796`, docs-only merge) |
| Branch | `eval/rag-v1`, cut from `main` at `1c9f780` |

## Data

| Item | Value |
|---|---|
| Last Job run (start time) | `2026-11-15 16:17 CET` |
| Job run ID | `457112251035204` |
| Documents in manifest | 74 |
| Documents in `silver.doc_chunks` | 69 |
| Chunks in `silver.doc_chunks` | 157 |
| Chunking version | `v1` |

Excluded as not relevant (not indexed): D0010, D0039, D0064, D0065, D0070.

## Vector index

| Item | Value |
|---|---|
| Index | `humanoid_robotics.silver.doc_chunks_index` |
| Endpoint | `humanoid_vs_endpoint` (STANDARD) |
| Status | `ONLINE` |
| Indexed rows | `157` (must equal chunk count above) |
| Last synced | `2026-11-15 16:22:41 CET` (must be after the Job run) |
| Index subtype | `HYBRID` (keyword + vector search available without a rebuild) |

Verified on 2026-11-15 with the Databricks CLI, not copied from the UI:

- `silver.doc_chunks` was last overwritten at 16:22:14 CET (Delta version 18, `CREATE OR REPLACE TABLE AS SELECT`).
- The index sync pipeline update `6f430cc2` started at 16:22:41 CET, after that overwrite, and completed.
- Job run `457112251035204` ran 16:17:29–16:22:46 CET and succeeded. No later run exists.
- None of the three pipeline jobs in the workspace has a schedule or trigger, so there is nothing to pause. The job is not run by hand during the evaluation. CD (`bundle deploy`) only deploys the job definition and does not run it.

## Models

| Item | Value |
|---|---|
| Embedding model | `databricks-gte-large-en` |
| LLM | `databricks-gpt-oss-120b` |

## RAG configuration (baseline)

| Item | Value |
|---|---|
| top_k | 5 |
| Max chunks per document | none |
| Retrieval type | vector only (ANN) |
| Prompt version | `v1` |

## Change log during evaluation

| Date | Commit | Change | Reason |
|---|---|---|---|
| 2026-11-27 | `7bfc8fa` | Generation runs use ANN, k = 10, cap 1 and cap 2 (via script arguments; `rag.py` defaults unchanged) | Retrieval run `20261127_1314`: k = 10 is the knee; cap 1 best recall |
| 2026-11-27 | (next commit) | Add system prompt v2 in `rag.py` (`PROMPTS`, `--prompt-version`); default stays v1 | Generation run `20261127_1454_cap2`: all-or-nothing refusals (Q05, Q18), facts moved to wrong year (Q12, Q13) |
| 2026-11-28 | (next commit) | `rag.py` defaults: top_k 10, max 2 chunks per doc, ANN, prompt v2; API default top_k and Streamlit slider set to 10 | Generation run `20261128_1202_v2`: over-refusal 1/26 (v1: 3/26), correct refusals 4/4 |
