-- =====================================================================
-- silver.documents_relevance (append-only, ai_classify)
-- Converted from: scripts/silver/04_silver_doc_relevance.dbquery.ipynb (original kept in sync)
-- Reads: silver.documents_clean
-- Job task: silver_04_doc_relevance (SQL file)
-- Incremental: only documents without a usable label are sent to ai_classify.
-- A NULL label is retried; downstream steps only use rows where is_relevant is true.
-- =====================================================================

CREATE TABLE IF NOT EXISTS humanoid_robotics.silver.documents_relevance (
  doc_id          STRING,
  relevance_label STRING,
  is_relevant     BOOLEAN,
  classified_at   TIMESTAMP
);

INSERT INTO humanoid_robotics.silver.documents_relevance
SELECT doc_id,
       label,
       label = 'about_humanoid_robots',
       current_timestamp()
FROM (
  SELECT d.doc_id,
         ai_classify(left(d.clean_text, 4000),   
                     ARRAY('about_humanoid_robots', 'not_about_humanoid_robots')) AS label
  FROM humanoid_robotics.silver.documents_clean d
  -- Skip only documents that already have a usable label. A NULL label (failed
  -- call or empty input) is kept as a record and retried on the next run.
  WHERE NOT EXISTS (SELECT 1 FROM humanoid_robotics.silver.documents_relevance r
                    WHERE r.doc_id = d.doc_id
                      AND r.relevance_label IS NOT NULL)
) t;
