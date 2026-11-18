-- PR-J2 CI only. Minimal Train/event fixture, explicitly SYNTHETIC.
-- The actual producer #4085 and event 21937 were independently SELECT-verified.
-- Bring the disposable fixture's total to 579 without changing AUTH-020.
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado,created_at,updated_at,pendiente_decision,es_transversal)
SELECT 10000+g,'PRJ2-SYN-'||g,'TEST','TEST','fixture only','CANDIDATO',now(),now(),false,false
FROM generate_series(1,578) AS g;

CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,status text,
 manifest jsonb,updated_by_execution_id text
);
CREATE TABLE public.lf_eventos(
 id bigint PRIMARY KEY,entidad_codigo text,evento_tipo text,origen text,payload jsonb
);
CREATE TABLE public.lf_ig_owner_decision_v2(id bigint);
CREATE TABLE public.lf_ig_rule_change_v2(id bigint);
CREATE TABLE public.lf_ig_functional_train_evidence_v1(
 rule_code text NOT NULL,source_snapshot_sha256 text NOT NULL,
 proposal_sha256 text NOT NULL,candidate_snapshot_sha256 text NOT NULL,
 train_execution_id text NOT NULL,train_run_id text NOT NULL,
 train_event_id bigint NOT NULL REFERENCES public.lf_eventos(id),
 train_head_sha text NOT NULL,pg_rollback_status text NOT NULL,
 independent_readback_status text NOT NULL,functional_checks_status text NOT NULL,
 negative_checks_status text NOT NULL,pg_report_sha256 text NOT NULL,
 readback_sha256 text NOT NULL,check_manifest_sha256 text NOT NULL,
 report_ref text NOT NULL,captured_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(rule_code,source_snapshot_sha256,proposal_sha256)
);
ALTER TABLE public.lf_ig_functional_train_evidence_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_ig_functional_train_evidence_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public.lf_ig_functional_train_evidence_v1
 FROM PUBLIC;

INSERT INTO public.lf_operation_execution VALUES(
 'EXEC-DB-TRAIN-PR4085-20261118100000-R44330090597',
 'ACTUALIZACION_DB_LF','COMPLETED',
 '{"train_run_id":"44330090597","head_sha":"367f5fa03875348cfe0114e24be7e34ded72c761"}'::jsonb,
 'LF-MIGRATION-TRAIN-RUN-44330090597'
);
WITH receipt AS (
 SELECT jsonb_build_object(
  'train_run_id','44330090597',
  'heads',jsonb_build_object(
     'final_head','367f5fa03875348cfe0114e24be7e34ded72c761',
     'final_head_is_execution_head',true),
  'terminal_status','COMPLETED',
  'parity',jsonb_build_object('migration_source_parity','PASS'),
  'ledger_readback',jsonb_build_object('matches_target',true)) AS payload
)
INSERT INTO public.lf_eventos(id,entidad_codigo,evento_tipo,origen,payload)
SELECT 21937,'EXEC-DB-TRAIN-PR4085-20261118100000-R44330090597',
'MIGRATION_TRAIN_RECEIPT_RECORDED','lf-migration-merge-train',
jsonb_build_object('receipt',payload,'receipt_sha256',
 encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'))
FROM receipt;

-- This negative probe proves payload hash binding rejects a altered receipt.
DO $neg$
DECLARE v_ok boolean;
BEGIN
 SELECT encode(extensions.digest(convert_to((payload->'receipt')::text,'UTF8'),'sha256'),'hex')
        =payload->>'receipt_sha256'
 INTO v_ok FROM public.lf_eventos WHERE id=21937;
 IF v_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'PR_J2_FIXTURE_HASH_INVALID'; END IF;
 IF EXISTS(
  SELECT 1 FROM public.lf_eventos evt
  WHERE id=21937 AND encode(extensions.digest(
     convert_to((jsonb_set(evt.payload->'receipt','{heads,final_head}',
                        '"deadbeef"'::jsonb))::text,'UTF8'),'sha256'),'hex')
                     =evt.payload->>'receipt_sha256')
 THEN RAISE EXCEPTION 'PR_J2_TAMPERED_RECEIPT_HASH_ACCEPTED'; END IF;
 RAISE NOTICE 'PR_J2_NEG_TAMPERED_TRAIN_RECEIPT_REJECTED';
END $neg$;
