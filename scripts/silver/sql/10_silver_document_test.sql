-- =====================================================================
-- Check on silver.documents_clean
-- Converted from: scripts/silver/10_silver_document_test.dbquery.ipynb (original kept unchanged)
-- Reads: silver.documents_clean
-- Not in the Job: manual check. Table name made fully qualified (catalog added).
-- =====================================================================

SELECT count_if(is_truncated)
FROM humanoid_robotics.silver.documents_clean;
