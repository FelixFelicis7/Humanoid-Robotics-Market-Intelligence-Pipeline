-- Extraction stored with neither a result nor an error (e.g. a NULL prompt).
-- v_extractions_parsed ignores these rows and the document is retried next run.
-- Was: 12_silver_quality_check check 7a.
{{ config(severity='warn') }}
SELECT doc_id, prompt_version, extracted_at
FROM {{ ref('documents_extractions') }}
WHERE ai_error IS NULL AND ai_raw_json IS NULL
