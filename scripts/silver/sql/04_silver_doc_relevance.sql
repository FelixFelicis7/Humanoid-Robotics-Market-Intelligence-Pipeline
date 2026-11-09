-- =====================================================================
-- silver.documents_relevance (append-only, ai_classify)
-- Converted from: scripts/silver/04_silver_doc_relevance.dbquery.ipynb (original kept in sync)
-- Reads: silver.documents_clean
-- Job task: silver_04_doc_relevance (SQL file)
-- Incremental: only documents not yet classified are sent to ai_classify.
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
  WHERE NOT EXISTS (SELECT 1 FROM humanoid_robotics.silver.documents_relevance r
                    WHERE r.doc_id = d.doc_id)   
) t;
