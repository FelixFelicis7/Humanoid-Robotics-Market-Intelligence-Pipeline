-- Relevant documents that still have no successful extraction for the current
-- prompt_version (every attempt failed). Failed attempts stay in the append-only
-- table, so an old error row is fine once a later attempt succeeded; this test
-- only lists documents where NO attempt succeeded.
-- Was: 12_silver_quality_check check 3 (stricter: that check listed every error row).
{{ config(severity='warn') }}
SELECT e.doc_id,
       count(*)          AS n_attempts,
       max(e.ai_error)   AS last_error_example,
       max(e.extracted_at) AS last_attempt
FROM {{ ref('documents_extractions') }} e
WHERE e.prompt_version = '{{ var("prompt_version") }}'
GROUP BY e.doc_id
HAVING count_if(e.ai_error IS NULL AND e.ai_raw_json IS NOT NULL) = 0
