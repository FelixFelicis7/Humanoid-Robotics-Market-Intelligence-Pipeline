-- =====================================================================
-- gold constraints: declare primary keys and foreign keys
-- Run AFTER all 8 gold tables are (re)built.
-- Constraints are informational (not enforced), but are shown in
-- Catalog Explorer and used by Genie to understand relationships.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Drop existing constraints (makes this file safe to re-run)
--    Order: foreign keys first, then primary keys
-- ---------------------------------------------------------------------

-- foreign keys
ALTER TABLE humanoid_robotics.gold.fct_events             DROP CONSTRAINT IF EXISTS fk_fact_events_date;
ALTER TABLE humanoid_robotics.gold.fct_events             DROP CONSTRAINT IF EXISTS fk_fact_events_primary_source;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    DROP CONSTRAINT IF EXISTS fk_bec_event;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    DROP CONSTRAINT IF EXISTS fk_bec_company;
ALTER TABLE humanoid_robotics.gold.bridge_event_technology DROP CONSTRAINT IF EXISTS fk_bet_event;
ALTER TABLE humanoid_robotics.gold.bridge_event_technology DROP CONSTRAINT IF EXISTS fk_bet_technology;
ALTER TABLE humanoid_robotics.gold.bridge_event_source     DROP CONSTRAINT IF EXISTS fk_bes_event;
ALTER TABLE humanoid_robotics.gold.bridge_event_source     DROP CONSTRAINT IF EXISTS fk_bes_source;

-- primary keys
ALTER TABLE humanoid_robotics.gold.dim_date                DROP CONSTRAINT IF EXISTS pk_dim_date;
ALTER TABLE humanoid_robotics.gold.dim_source              DROP CONSTRAINT IF EXISTS pk_dim_source;
ALTER TABLE humanoid_robotics.gold.dim_company             DROP CONSTRAINT IF EXISTS pk_dim_company;
ALTER TABLE humanoid_robotics.gold.dim_technology          DROP CONSTRAINT IF EXISTS pk_dim_technology;
ALTER TABLE humanoid_robotics.gold.fct_events             DROP CONSTRAINT IF EXISTS pk_fct_events;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    DROP CONSTRAINT IF EXISTS pk_bridge_event_company;
ALTER TABLE humanoid_robotics.gold.bridge_event_technology DROP CONSTRAINT IF EXISTS pk_bridge_event_technology;
ALTER TABLE humanoid_robotics.gold.bridge_event_source     DROP CONSTRAINT IF EXISTS pk_bridge_event_source;

-- ---------------------------------------------------------------------
-- 1. Primary keys (PK columns must be NOT NULL first)
-- ---------------------------------------------------------------------

-- dimensions
ALTER TABLE humanoid_robotics.gold.dim_date       ALTER COLUMN date          SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.dim_date       ADD CONSTRAINT pk_dim_date       PRIMARY KEY (date);

ALTER TABLE humanoid_robotics.gold.dim_source     ALTER COLUMN doc_id        SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.dim_source     ADD CONSTRAINT pk_dim_source     PRIMARY KEY (doc_id);

ALTER TABLE humanoid_robotics.gold.dim_company    ALTER COLUMN company_id    SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.dim_company    ADD CONSTRAINT pk_dim_company    PRIMARY KEY (company_id);

ALTER TABLE humanoid_robotics.gold.dim_technology ALTER COLUMN technology_id SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.dim_technology ADD CONSTRAINT pk_dim_technology PRIMARY KEY (technology_id);

-- fact
ALTER TABLE humanoid_robotics.gold.fct_events    ALTER COLUMN event_id      SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.fct_events    ADD CONSTRAINT pk_fct_events    PRIMARY KEY (event_id);

-- bridges (composite keys)
ALTER TABLE humanoid_robotics.gold.bridge_event_company    ALTER COLUMN event_id      SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    ALTER COLUMN company_id    SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    ALTER COLUMN role          SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_company    ADD CONSTRAINT pk_bridge_event_company    PRIMARY KEY (event_id, company_id, role);

ALTER TABLE humanoid_robotics.gold.bridge_event_technology ALTER COLUMN event_id      SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_technology ALTER COLUMN technology_id SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_technology ADD CONSTRAINT pk_bridge_event_technology PRIMARY KEY (event_id, technology_id);

ALTER TABLE humanoid_robotics.gold.bridge_event_source     ALTER COLUMN event_id      SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_source     ALTER COLUMN doc_id        SET NOT NULL;
ALTER TABLE humanoid_robotics.gold.bridge_event_source     ADD CONSTRAINT pk_bridge_event_source     PRIMARY KEY (event_id, doc_id);

-- ---------------------------------------------------------------------
-- 2. Foreign keys: fact -> dimensions (direct)
-- ---------------------------------------------------------------------

ALTER TABLE humanoid_robotics.gold.fct_events
  ADD CONSTRAINT fk_fct_events_date
  FOREIGN KEY (event_date) REFERENCES humanoid_robotics.gold.dim_date (date);

ALTER TABLE humanoid_robotics.gold.fct_events
  ADD CONSTRAINT fk_fct_events_primary_source
  FOREIGN KEY (primary_source_doc_id) REFERENCES humanoid_robotics.gold.dim_source (doc_id);

-- ---------------------------------------------------------------------
-- 3. Foreign keys: bridges -> fact and dimensions
-- ---------------------------------------------------------------------

ALTER TABLE humanoid_robotics.gold.bridge_event_company
  ADD CONSTRAINT fk_bec_event   FOREIGN KEY (event_id)   REFERENCES humanoid_robotics.gold.fct_events (event_id);
ALTER TABLE humanoid_robotics.gold.bridge_event_company
  ADD CONSTRAINT fk_bec_company FOREIGN KEY (company_id) REFERENCES humanoid_robotics.gold.dim_company (company_id);

ALTER TABLE humanoid_robotics.gold.bridge_event_technology
  ADD CONSTRAINT fk_bet_event      FOREIGN KEY (event_id)      REFERENCES humanoid_robotics.gold.fct_events (event_id);
ALTER TABLE humanoid_robotics.gold.bridge_event_technology
  ADD CONSTRAINT fk_bet_technology FOREIGN KEY (technology_id) REFERENCES humanoid_robotics.gold.dim_technology (technology_id);

ALTER TABLE humanoid_robotics.gold.bridge_event_source
  ADD CONSTRAINT fk_bes_event  FOREIGN KEY (event_id) REFERENCES humanoid_robotics.gold.fct_events (event_id);
ALTER TABLE humanoid_robotics.gold.bridge_event_source
  ADD CONSTRAINT fk_bes_source FOREIGN KEY (doc_id)   REFERENCES humanoid_robotics.gold.dim_source (doc_id);
