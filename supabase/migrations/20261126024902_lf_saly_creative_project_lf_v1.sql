BEGIN;
-- Alta del negocio LF autorizada por el dueño. La identidad permanece en lf_design.
INSERT INTO saly.proyecto(id,codigo,nombre,fase,estado,objetivo)
SELECT 3,'LF','Libertad Financiera','IDEACION','ACTIVO','Plataforma peruana de negociación de deuda castigada.'
WHERE NOT EXISTS (SELECT 1 FROM saly.proyecto WHERE codigo='LF')
AND EXISTS (SELECT 1 FROM lf_design.design_systems WHERE project_code='LF');
DO $check$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.proyecto WHERE codigo='LF' AND nombre='Libertad Financiera') THEN RAISE EXCEPTION 'LF_PROJECT_INTAKE_NOT_REGISTERED'; END IF;
END $check$;
COMMIT;
