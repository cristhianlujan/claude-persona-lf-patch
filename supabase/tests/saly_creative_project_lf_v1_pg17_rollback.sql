\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA saly;
CREATE SCHEMA lf_design;
CREATE TABLE saly.proyecto(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text UNIQUE NOT NULL,nombre text NOT NULL,fase text NOT NULL,estado text NOT NULL,objetivo text);
CREATE TABLE lf_design.design_systems(project_code text);
INSERT INTO saly.proyecto OVERRIDING SYSTEM VALUE VALUES(2,'SALY-001','Saly','IDEACION','ACTIVO','fixture');
ALTER TABLE saly.proyecto ALTER COLUMN id RESTART WITH 3;
INSERT INTO lf_design.design_systems VALUES('LF');
\i /tmp/saly_project_lf_body.sql
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.proyecto WHERE id=3 AND codigo='LF' AND nombre='Libertad Financiera') OR (SELECT count(*) FROM saly.proyecto)<>2 THEN RAISE EXCEPTION 'LF_INTAKE_FAILED'; END IF;
END $$;
ROLLBACK;
