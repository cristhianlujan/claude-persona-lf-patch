-- LOTE 13: SQL only for a newly created PostgreSQL 18 sandbox.
SET search_path = rule_quality_l13, public;
INSERT INTO projects(project_code,owner_name,owner_profile_code,created_by,review_interval_days)
VALUES ('lf','LF_GOVERNANCE','LF_GOVERNANCE','ChatGPT',90),
       ('saly','SALY_GOVERNANCE','SALY_OWNER','ChatGPT',60);
-- Privilege counterexample: SUPER_ADMIN exists with can_approve=true but MUST be denied.
INSERT INTO actors(project_code,actor_code,profile_code,can_approve)
VALUES ('lf','lf-owner','LF_GOVERNANCE',true),
       ('lf','lf-super','SUPER_ADMIN',true),
       ('lf','lf-reader','READER',false),
       ('saly','saly-owner','SALY_OWNER',true),
       ('saly','saly-super','SUPER_ADMIN',true);
INSERT INTO families(project_code,family_code,scope,owner_profile_code,new_family_criterion,merge_criterion,created_by)
VALUES
 ('lf','ACCESIBILIDAD','accesibilidad','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','ANALITICA_EXPERIMENTACION','analitica experimentacion','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','CARGAS_B2B','cargas b2b','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','CHECKOUT_PAGOS','checkout pagos','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','CONTENIDO_COMUNICACIONES','contenido comunicaciones','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','DATOS_VALIDACIONES','datos validaciones','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','GOBERNANZA_INTEGRIDAD','gobernanza integridad','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','IDENTIDAD_SEGURIDAD','identidad seguridad','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','LEGAL','legal','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','NEGOCIO_B2B','negocio b2b','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','OBSERVABILIDAD_AUDITORIA','observabilidad auditoria','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','OFERTAS_CUOTAS','ofertas cuotas','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','PLATAFORMA_INTEGRACIONES','plataforma integraciones','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','RETENCION','retencion','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('lf','UX_FLUJOS_INTERFAZ','ux flujos interfaz','LF_GOVERNANCE','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('saly','CALENDARIO','calendario','SALY_OWNER','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('saly','GOBERNANZA','gobernanza','SALY_OWNER','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT'),
 ('saly','MOTOR_DISPONIBLE','motor disponible','SALY_OWNER','Scope ownership and distinct policy subjects','Merge only after evidence and consumer-impact review','ChatGPT');
INSERT INTO category_family_map(project_code,category_raw,family_code)
VALUES
 ('lf','ab_testing','ANALITICA_EXPERIMENTACION'),
 ('lf','accesibilidad','ACCESIBILIDAD'),
 ('lf','ACCESSIBILITY','ACCESIBILIDAD'),
 ('lf','alertas','OBSERVABILIDAD_AUDITORIA'),
 ('lf','analytics','ANALITICA_EXPERIMENTACION'),
 ('lf','ANALYTICS','ANALITICA_EXPERIMENTACION'),
 ('lf','api','PLATAFORMA_INTEGRACIONES'),
 ('lf','APPROVAL','GOBERNANZA_INTEGRIDAD'),
 ('lf','ataques','IDENTIDAD_SEGURIDAD'),
 ('lf','AUDIT','OBSERVABILIDAD_AUDITORIA'),
 ('lf','auditoria','OBSERVABILIDAD_AUDITORIA'),
 ('lf','autenticacion','IDENTIDAD_SEGURIDAD'),
 ('lf','AUTHORIZATION','IDENTIDAD_SEGURIDAD'),
 ('lf','b2b','NEGOCIO_B2B'),
 ('lf','B2B_CARGAS','CARGAS_B2B'),
 ('lf','beneficios','NEGOCIO_B2B'),
 ('lf','BRAND','UX_FLUJOS_INTERFAZ'),
 ('lf','BUSINESS','NEGOCIO_B2B'),
 ('lf','CARGAS','CARGAS_B2B'),
 ('lf','checkout','CHECKOUT_PAGOS'),
 ('lf','CLIENT_CHECKOUT','CHECKOUT_PAGOS'),
 ('lf','COMMERCIAL_CAMPAIGN','NEGOCIO_B2B'),
 ('lf','COMPATIBILITY','PLATAFORMA_INTEGRACIONES'),
 ('lf','CONFIGURATION','PLATAFORMA_INTEGRACIONES'),
 ('lf','contenido','CONTENIDO_COMUNICACIONES'),
 ('lf','copy','CONTENIDO_COMUNICACIONES'),
 ('lf','datos','DATOS_VALIDACIONES'),
 ('lf','DESIGN','UX_FLUJOS_INTERFAZ'),
 ('lf','documento','CONTENIDO_COMUNICACIONES'),
 ('lf','ERROR','DATOS_VALIDACIONES'),
 ('lf','ERROR_HANDLING','DATOS_VALIDACIONES'),
 ('lf','error_states','DATOS_VALIDACIONES'),
 ('lf','estados_ui','UX_FLUJOS_INTERFAZ'),
 ('lf','flujo','UX_FLUJOS_INTERFAZ'),
 ('lf','GOVERNANCE','GOBERNANZA_INTEGRIDAD'),
 ('lf','heatmap','ANALITICA_EXPERIMENTACION'),
 ('lf','home_variante','UX_FLUJOS_INTERFAZ'),
 ('lf','INTEGRITY','GOBERNANZA_INTEGRIDAD'),
 ('lf','legal','LEGAL'),
 ('lf','LEGAL','LEGAL'),
 ('lf','navegacion','UX_FLUJOS_INTERFAZ'),
 ('lf','NAVIGATION','UX_FLUJOS_INTERFAZ'),
 ('lf','negocio','NEGOCIO_B2B'),
 ('lf','niubiz','CHECKOUT_PAGOS'),
 ('lf','notificacion','CONTENIDO_COMUNICACIONES'),
 ('lf','notificaciones','CONTENIDO_COMUNICACIONES'),
 ('lf','observabilidad','OBSERVABILIDAD_AUDITORIA'),
 ('lf','OBSERVABILITY','OBSERVABILIDAD_AUDITORIA'),
 ('lf','oferta','OFERTAS_CUOTAS'),
 ('lf','OFERTAS_CUOTAS','OFERTAS_CUOTAS'),
 ('lf','pago','CHECKOUT_PAGOS'),
 ('lf','PERFORMANCE','PLATAFORMA_INTEGRACIONES'),
 ('lf','precio','CHECKOUT_PAGOS'),
 ('lf','PRIVACY','IDENTIDAD_SEGURIDAD'),
 ('lf','PRODUCT_GOVERNANCE','GOBERNANZA_INTEGRIDAD'),
 ('lf','rate_limiting','IDENTIDAD_SEGURIDAD'),
 ('lf','RESILIENCE','PLATAFORMA_INTEGRACIONES'),
 ('lf','RESPONSIVE','UX_FLUJOS_INTERFAZ'),
 ('lf','RETENTION','RETENCION'),
 ('lf','SECURITY','IDENTIDAD_SEGURIDAD'),
 ('lf','seguridad','IDENTIDAD_SEGURIDAD'),
 ('lf','sesion','IDENTIDAD_SEGURIDAD'),
 ('lf','SESSION','IDENTIDAD_SEGURIDAD'),
 ('lf','SHELL','UX_FLUJOS_INTERFAZ'),
 ('lf','STORAGE','PLATAFORMA_INTEGRACIONES'),
 ('lf','tageo','ANALITICA_EXPERIMENTACION'),
 ('lf','tecnico','PLATAFORMA_INTEGRACIONES'),
 ('lf','TESTING','GOBERNANZA_INTEGRIDAD'),
 ('lf','THEME','UX_FLUJOS_INTERFAZ'),
 ('lf','UI','UX_FLUJOS_INTERFAZ'),
 ('lf','unicidad','IDENTIDAD_SEGURIDAD'),
 ('lf','ux','UX_FLUJOS_INTERFAZ'),
 ('lf','UX','UX_FLUJOS_INTERFAZ'),
 ('lf','UX_RUNTIME','UX_FLUJOS_INTERFAZ'),
 ('lf','VALIDATION','DATOS_VALIDACIONES'),
 ('lf','WORKFLOW','UX_FLUJOS_INTERFAZ'),
 ('saly','CALENDARIO','CALENDARIO'),
 ('saly','GOBERNANZA','GOBERNANZA'),
 ('saly','MOTOR_DISPONIBLE','MOTOR_DISPONIBLE');
-- Source-shape fixtures: preserve REAL column differences, but rows are fully SYNTHETIC.
CREATE TABLE lf_source_synthetic (
  codigo text PRIMARY KEY,categoria text NOT NULL,descripcion text NOT NULL,
  valor_config jsonb,estado text NOT NULL,created_by text
);
CREATE TABLE saly_source_synthetic (
  codigo text PRIMARY KEY,categoria text NOT NULL,regla text NOT NULL,
  valor_config jsonb,vigente boolean NOT NULL,decision_id bigint,
  fuente text,metadata jsonb
);
CREATE TABLE lf_seed_counts (categoria text PRIMARY KEY,n integer NOT NULL);
INSERT INTO lf_seed_counts VALUES
 ('ab_testing',5),
 ('accesibilidad',6),
 ('ACCESSIBILITY',4),
 ('alertas',6),
 ('analytics',9),
 ('ANALYTICS',1),
 ('api',6),
 ('APPROVAL',3),
 ('ataques',20),
 ('AUDIT',2),
 ('auditoria',5),
 ('autenticacion',3),
 ('AUTHORIZATION',3),
 ('b2b',7),
 ('B2B_CARGAS',5),
 ('beneficios',1),
 ('BRAND',1),
 ('BUSINESS',27),
 ('CARGAS',2),
 ('checkout',39),
 ('CLIENT_CHECKOUT',1),
 ('COMMERCIAL_CAMPAIGN',2),
 ('COMPATIBILITY',1),
 ('CONFIGURATION',1),
 ('contenido',6),
 ('copy',15),
 ('datos',11),
 ('DESIGN',2),
 ('documento',1),
 ('ERROR',3),
 ('ERROR_HANDLING',1),
 ('error_states',16),
 ('estados_ui',9),
 ('flujo',53),
 ('GOVERNANCE',13),
 ('heatmap',4),
 ('home_variante',5),
 ('INTEGRITY',3),
 ('legal',24),
 ('LEGAL',2),
 ('navegacion',3),
 ('NAVIGATION',1),
 ('negocio',18),
 ('niubiz',6),
 ('notificacion',1),
 ('notificaciones',7),
 ('observabilidad',6),
 ('OBSERVABILITY',3),
 ('oferta',10),
 ('OFERTAS_CUOTAS',1),
 ('pago',8),
 ('PERFORMANCE',1),
 ('precio',2),
 ('PRIVACY',1),
 ('PRODUCT_GOVERNANCE',1),
 ('rate_limiting',8),
 ('RESILIENCE',2),
 ('RESPONSIVE',3),
 ('RETENTION',1),
 ('SECURITY',38),
 ('seguridad',21),
 ('sesion',5),
 ('SESSION',2),
 ('SHELL',4),
 ('STORAGE',2),
 ('tageo',6),
 ('tecnico',16),
 ('TESTING',1),
 ('THEME',3),
 ('UI',1),
 ('unicidad',4),
 ('ux',38),
 ('UX',15),
 ('UX_RUNTIME',1),
 ('VALIDATION',1),
 ('WORKFLOW',9);
WITH expanded AS (
  SELECT c.categoria,g.seq FROM lf_seed_counts c
  CROSS JOIN LATERAL generate_series(1,c.n) AS g(seq)
), indexed AS (
  SELECT row_number() OVER(ORDER BY categoria,seq) AS rn,categoria,seq FROM expanded
)
INSERT INTO lf_source_synthetic(codigo,categoria,descripcion,valor_config,estado,created_by)
SELECT 'LF-SYN-'||lpad(rn::text,4,'0'),categoria,
       'Regla sintetica basada en categoria '||categoria||' / orden '||seq,
       '{}'::jsonb,
       CASE WHEN rn<=412 THEN 'VIGENTE' ELSE 'CANDIDATO' END,
       'ChatGPT'
FROM indexed ORDER BY rn;
CREATE TABLE saly_seed_counts(categoria text PRIMARY KEY,n integer NOT NULL);
INSERT INTO saly_seed_counts VALUES
 ('CALENDARIO',1),
 ('GOBERNANZA',3),
 ('MOTOR_DISPONIBLE',10);
WITH expanded AS (
  SELECT c.categoria,g.seq FROM saly_seed_counts c
  CROSS JOIN LATERAL generate_series(1,c.n) AS g(seq)
), indexed AS (
  SELECT row_number() OVER(ORDER BY categoria,seq) AS rn,categoria,seq FROM expanded
)
INSERT INTO saly_source_synthetic(codigo,categoria,regla,valor_config,vigente,decision_id,fuente,metadata)
SELECT 'SALY-SYN-'||lpad(rn::text,4,'0'),categoria,
       'Regla sintetica SALY '||categoria||' / orden '||seq,
       '{}'::jsonb,true,51,'SYNTHETIC_FIXTURE',
       '{"version":"V2.3"}'::jsonb
FROM indexed ORDER BY rn;
-- Adapter LF: descripcion + estado; adapter SALY: regla + vigente.
CREATE VIEW adapter_lf AS
 SELECT 'lf'::text AS project_code,s.codigo AS rule_code,m.family_code,s.categoria AS category_raw,
        s.descripcion AS definition_text,coalesce(s.valor_config,'{}'::jsonb) AS config,
        s.estado AS state
 FROM lf_source_synthetic s
 JOIN category_family_map m ON m.project_code='lf' AND m.category_raw=s.categoria;
CREATE VIEW adapter_saly AS
 SELECT 'saly'::text AS project_code,s.codigo AS rule_code,m.family_code,s.categoria AS category_raw,
        s.regla AS definition_text,coalesce(s.valor_config,'{}'::jsonb) AS config,
        CASE WHEN s.vigente THEN 'VIGENTE' ELSE 'CANDIDATO' END AS state
 FROM saly_source_synthetic s
 JOIN category_family_map m ON m.project_code='saly' AND m.category_raw=s.categoria;
-- Exactly the SAME canonical table and the SAME detectors for both projects.
INSERT INTO rules(project_code,rule_code,family_code,category_raw,entity_code,definition_text,
                  config,state,created_at,reviewed_at,next_review_at,effective_from)
SELECT project_code,rule_code,family_code,category_raw,'GENERAL',definition_text,
       config,state,'2026-09-01T00:00:00Z'::timestamptz,'2026-10-15T00:00:00Z'::timestamptz,
       '2027-02-01T00:00:00Z'::timestamptz,'2026-10-01T00:00:00Z'::timestamptz
FROM adapter_lf
UNION ALL
SELECT project_code,rule_code,family_code,category_raw,'GENERAL',definition_text,
       config,state,'2026-09-01T00:00:00Z'::timestamptz,'2026-10-15T00:00:00Z'::timestamptz,
       '2027-02-01T00:00:00Z'::timestamptz,'2026-10-01T00:00:00Z'::timestamptz
FROM adapter_saly;
-- Controlled positive/negative detector fixtures. These values are NOT copied from live.
UPDATE rules SET entity_code='OTP_SEND',config='{"ventana_minutos":10}'::jsonb
 WHERE project_code='lf' AND rule_code='LF-SYN-0001';
UPDATE rules SET entity_code='OTP_SEND',config='{"ventana_minutos":30}'::jsonb
 WHERE project_code='lf' AND rule_code='LF-SYN-0002';
UPDATE rules SET entity_code='MOTOR_DISPONIBLE',config='{"max_operations":1}'::jsonb
 WHERE project_code='saly' AND rule_code='SALY-SYN-0001';
UPDATE rules SET entity_code='MOTOR_DISPONIBLE',config='{"max_operations":3}'::jsonb
 WHERE project_code='saly' AND rule_code='SALY-SYN-0002';
-- The next review is overdue. No change of state is allowed just because of time.
UPDATE rules SET next_review_at='2026-10-01T00:00:00Z'
 WHERE project_code='lf' AND rule_code='LF-SYN-0003';
INSERT INTO rule_references(project_code,source_rule_code,target_rule_code,reference_kind)
VALUES ('lf','LF-SYN-0004','LF-SYN-0413','duplicate_submit_rule_id'),
       ('lf','LF-SYN-0005','LF-SYN-0414','mfa_gate_rule_id'),
       ('lf','LF-SYN-0006','LF-SYN-0415','dark_promotion_gate_rule_id'),
       ('saly','SALY-SYN-0003','SALY-SYN-0004','dependency');
