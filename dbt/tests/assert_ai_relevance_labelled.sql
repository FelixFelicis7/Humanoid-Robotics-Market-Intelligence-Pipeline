-- Documents whose relevance label is still NULL after every attempt.
-- 04 retries them on the next run; a document listed here after a rerun keeps failing.
-- Was: 12_silver_quality_check check 7b.
{{ config(severity='warn') }}
SELECT doc_id, count(*) AS n_attempts, max(classified_at) AS last_attempt
FROM {{ ref('documents_relevance') }}
GROUP BY doc_id
HAVING count(relevance_label) = 0
