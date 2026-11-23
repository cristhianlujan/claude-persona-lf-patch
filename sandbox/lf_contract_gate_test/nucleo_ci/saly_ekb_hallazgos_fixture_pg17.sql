-- Solo PG17 desechable. Proyección estructural EKB consultada por information_schema 2026-11-23.
-- No es migración; nunca transportar a Supabase real.
CREATE SCHEMA transversal;
CREATE TABLE transversal.error_knowledge (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 codigo text UNIQUE,
 categoria text NOT NULL,
 titulo text NOT NULL,
 descripcion text,
 causa_raiz text,
 patron text,
 prevencion text,
 validacion text,
 severidad text,
 frecuencia integer NOT NULL DEFAULT 1,
 primera_vez timestamptz NOT NULL DEFAULT now(),
 ultima_vez timestamptz NOT NULL DEFAULT now(),
 lote_origen text,
 pr text,
 estado text NOT NULL DEFAULT 'activo',
 evidencia text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 lifecycle_phase text NOT NULL DEFAULT 'construction',
 consumer_role text[] NOT NULL DEFAULT ARRAY['Architect'],
 root_cause_family text,
 detectability text,
 source_context text,
 source_ref text,
 CHECK (root_cause_family IS NULL OR root_cause_family IN (
  'R1_NO_SABE','R2_NO_VE','R3_NO_PRIORIZA','R4_NO_CUESTIONA',
  'R5_EROSION_PROCESO','UNCLASSIFIED_WITH_REASON'
 )),
 CHECK (detectability IS NULL OR detectability IN (
  'LOUD_EARLY','LOUD_LATE','SILENT','PROCESS_DEPENDENT'
 ))
);
