-- Synthetic 14-row SALY shape copied from 2026-11-13 live metadata.
-- Codes, status and decision IDs are observed; text bodies are NOT copied.
-- This is NOT a full database dump and no actual decision records are included.
CREATE SCHEMA IF NOT EXISTS saly;
CREATE TABLE saly.reglas (
 id bigint PRIMARY KEY,
 codigo text NOT NULL UNIQUE,
 categoria text NOT NULL,
 titulo text NOT NULL,
 regla text NOT NULL,
 razon text,
 alcance text NOT NULL DEFAULT 'PRODUCTO',
 producto_codigo text,
 valor_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 parametrizable boolean NOT NULL DEFAULT true,
 es_transversal boolean NOT NULL DEFAULT false,
 estado text NOT NULL DEFAULT 'BORRADOR',
 vigente boolean NOT NULL DEFAULT true,
 decision_id bigint,
 fuente text,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE saly.reglas ENABLE ROW LEVEL SECURITY;
INSERT INTO saly.reglas(id,codigo,categoria,titulo,regla,estado,vigente,decision_id)
VALUES
 (1,'SALY-RGL-001','MOTOR_DISPONIBLE','Curvas core del motor','CI_ONLY','VALIDADO',true,51),
 (2,'SALY-RGL-002','MOTOR_DISPONIBLE','Assignment cap','CI_ONLY','VALIDADO',true,53),
 (3,'SALY-RGL-003','MOTOR_DISPONIBLE','Accrual cap','CI_ONLY','VALIDADO',true,53),
 (4,'SALY-RGL-004','MOTOR_DISPONIBLE','Withdrawal limits','CI_ONLY','VALIDADO',true,53),
 (5,'SALY-RGL-005','CALENDARIO','Ciclo materializado','CI_ONLY','VALIDADO',true,54),
 (6,'SALY-RGL-006','MOTOR_DISPONIBLE','Gate de disposición','CI_ONLY','VALIDADO',true,55),
 (7,'SALY-RGL-007','MOTOR_DISPONIBLE','Excepción temporal de bloqueo','CI_ONLY','VALIDADO',true,55),
 (8,'SALY-RGL-008','MOTOR_DISPONIBLE','Saldo adicional temporal','CI_ONLY','VALIDADO',true,56),
 (9,'SALY-RGL-009','MOTOR_DISPONIBLE','Fuente VARIABLE_UPLOAD','CI_ONLY','VALIDADO',true,57),
 (10,'SALY-RGL-010','MOTOR_DISPONIBLE','Corrección de carga variable','CI_ONLY','VALIDADO',true,57),
 (11,'SALY-RGL-011','GOBERNANZA','Redondeo monetario','CI_ONLY','VALIDADO',true,58),
 (12,'SALY-RGL-012','GOBERNANZA','Traza de cálculo','CI_ONLY','VALIDADO',true,58),
 (13,'SALY-RGL-013','GOBERNANZA','Autorización de excepciones y saldos extraordinarios','CI_ONLY','VALIDADO',true,56),
 (14,'SALY-RGL-014','MOTOR_DISPONIBLE','Saly Plus — adelanto temporal de disponibilidad','CI_ONLY','VALIDADO',true,60);
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado)
VALUES
 (-70701,'LF-B07-CI-CANDIDATO','B07_TEST','CI ONLY CANDIDATO','CI ONLY','CANDIDATO'),
 (-70702,'LF-B07-CI-VIGENTE','B07_TEST','CI ONLY VIGENTE','CI ONLY','VIGENTE');
