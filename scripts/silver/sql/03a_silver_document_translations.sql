-- =====================================================================
-- silver.document_translations (append-only, ai_translate)
-- Reads: bronze.manifest, bronze.documents
-- Job task: silver_03a_document_translations (SQL file)
-- Runs BEFORE 03_silver_documents, which joins this table instead of
-- calling ai_translate itself.
--
-- NEVER replace this table: it holds paid AI results.
-- Incremental: a Chinese document is translated only when no successful
-- translation exists for the same doc_id + source_hash. source_hash covers
-- title, publisher and raw text, so a changed source text is retranslated.
-- Failed calls (text_en IS NULL) are retried on the next run.
-- The hash expression must stay identical to the one in 03_silver_documents.
-- =====================================================================

CREATE TABLE IF NOT EXISTS humanoid_robotics.silver.document_translations (
  doc_id        STRING,
  source_hash   STRING,
  title_en      STRING,
  publisher_en  STRING,
  text_en       STRING,
  translated_at TIMESTAMP
);

INSERT INTO humanoid_robotics.silver.document_translations
SELECT s.doc_id,
       s.source_hash,
       ai_translate(s.title, 'en')     AS title_en,
       ai_translate(s.publisher, 'en') AS publisher_en,
       ai_translate(s.raw_text, 'en')  AS text_en,
       current_timestamp()             AS translated_at
FROM (
  SELECT m.doc_id,
         m.title,
         m.publisher,
         d.raw_text,
         sha2(concat_ws('||', coalesce(m.title, ''), coalesce(m.publisher, ''), d.raw_text), 256) AS source_hash
  FROM humanoid_robotics.bronze.manifest m
  JOIN humanoid_robotics.bronze.documents d
    ON d.file_name = m.file_name
  WHERE m.language = 'zh'
    AND d.raw_text IS NOT NULL
) s
WHERE NOT EXISTS (
  SELECT 1
  FROM humanoid_robotics.silver.document_translations t
  WHERE t.doc_id = s.doc_id
    AND t.source_hash = s.source_hash
    AND t.text_en IS NOT NULL
);
