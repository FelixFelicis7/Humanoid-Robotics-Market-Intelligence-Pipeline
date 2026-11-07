-- =====================================================================
-- gold.dim_technology
-- Converted from: scripts/gold/05_gold_dim_technology.ipynb (original kept unchanged)
-- Reads: (fixed values)
-- Job task: gold_dim_technology (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.dim_technology AS
SELECT * FROM VALUES
  ('sensors',             'Sensors',                 1, 'Perception hardware: camera, radar, LiDAR, IMU, force/torque and position sensors'),
  ('compute_electronics', 'Compute & electronics',   2, 'Onboard computing, chips, controllers and electronic components'),
  ('software_ai',         'Software & AI',           3, 'AI models, control software, simulation and training platforms'),
  ('actuators',           'Actuators',               4, 'Motors, reducers, screws, joints, dexterous hands and other motion components'),
  ('battery_power',       'Battery & power',         5, 'Batteries, power management and charging'),
  ('not_specified',       'Not specified',           6, 'The source does not mention a specific technology area')
AS t(technology_id, technology_name, sort_order, description);
