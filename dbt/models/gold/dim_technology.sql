-- gold.dim_technology: fixed lookup of the 6 technology areas.
-- Migrated from scripts/gold/sql/05_gold_dim_technology.sql (logic unchanged).
-- Could later become a dbt seed (CSV), since it is not derived from data.

SELECT * FROM VALUES
  ('sensors',             'Sensors',                 1, 'Perception hardware: camera, radar, LiDAR, IMU, force/torque and position sensors'),
  ('compute_electronics', 'Compute & electronics',   2, 'Onboard computing, chips, controllers and electronic components'),
  ('software_ai',         'Software & AI',           3, 'AI models, control software, simulation and training platforms'),
  ('actuators',           'Actuators',               4, 'Motors, reducers, screws, joints, dexterous hands and other motion components'),
  ('battery_power',       'Battery & power',         5, 'Batteries, power management and charging'),
  ('not_specified',       'Not specified',           6, 'The source does not mention a specific technology area')
AS t(technology_id, technology_name, sort_order, description)
