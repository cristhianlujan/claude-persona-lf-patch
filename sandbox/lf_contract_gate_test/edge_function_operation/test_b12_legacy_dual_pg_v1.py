#!/usr/bin/env python3
"""B12 isolated dual PG test of the ACTUAL one-migration UP and documented rollback.
No Supabase credentials, calls, or writes. Positive, deny, expected failure,
idempotent effect, and transaction rollback. Four S21_04 functions + 3 real
helper functions copied via pg_get_functiondef from live SELECT-only readback.
Explicitly NOT a real production end-to-end or DBA sign-off.
"""
import hashlib
import json
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FREEZE = ROOT / "audits/rule-quality-lote28/b12/01_preimagen_S21_04_live_20261113.json"
SOURCES = [
  {
    "name": "lf_asset_snapshot_sha_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text, p_code text)\n RETURNS text\n LANGUAGE plpgsql\n STABLE SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare v jsonb;\nbegin\n  if p_asset_type='REGLA' then\n    select to_jsonb(r)-'created_at'-'updated_at' into v from lf_ops.reglas r where r.codigo=p_code;\n  elsif p_asset_type='PANTALLA' then\n    select jsonb_agg(to_jsonb(r)-'created_at'-'updated_at' order by r.codigo) into v\n    from lf_ops.pantallas p join lf_ops.reglas_pantallas rp on rp.pantalla_id=p.id join lf_ops.reglas r on r.id=rp.regla_id where p.codigo=p_code;\n  else return null; end if;\n  if v is null then return null; end if;\n  return encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex');\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_apply_batch_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_batch_v1(p_ids text[])\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare x text; o jsonb; res jsonb := '[]'::jsonb; ok int := 0; bad int := 0;\nbegin\n foreach x in array coalesce(p_ids,array[]::text[]) loop\n  o := public.lf_rule_promotion_apply_v1(x);\n  if o->>'status'='APPLIED' then ok:=ok+1; else bad:=bad+1; end if;\n  res := res||jsonb_build_array(jsonb_build_object('id',x,'status',o->>'status','code',o->>'blocking_code'));\n end loop;\n return jsonb_build_object('applied',ok,'blocked',bad,'detail',res);\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_apply_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare p record;\nbegin\n select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;\n if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;\n if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;\n if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then\n  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;\n  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;\n update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';\n update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;\n return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_decide_batch_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_batch_v1(p_ids text[], p_decision text, p_decided_by text, p_note text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare x text; o jsonb; res jsonb := '[]'::jsonb; ok int := 0; bad int := 0;\nbegin\n foreach x in array coalesce(p_ids,array[]::text[]) loop\n  o := public.lf_rule_promotion_decide_v1(x,p_decision,p_decided_by,p_note);\n  if o->>'status' in ('APPROVED','REJECTED') then ok:=ok+1; else bad:=bad+1; end if;\n  res := res||jsonb_build_array(jsonb_build_object('id',x,'status',o->>'status','code',o->>'blocking_code'));\n end loop;\n return jsonb_build_object('ok',ok,'blocked',bad,'detail',res);\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_decide_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare p record;\nbegin\n if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;\n if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;\n select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;\n if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;\n if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;\n if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then\n  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;\n  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;\n update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;\n return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_guard_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_guard_v1()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\nbegin\n if NEW.estado='VIGENTE' and OLD.estado is distinct from 'VIGENTE' then\n  if not exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=OLD.codigo and p.status='APPROVED' and p.request_snapshot_sha256=public.lf_asset_snapshot_sha_v1('REGLA',OLD.codigo)) then\n   raise exception 'LF_RULE_PROMOTION_REQUIRED:%',OLD.codigo; end if;\n end if;\n return NEW;\nend $function$\n"
  },
  {
    "name": "lf_rule_promotion_report_v1",
    "sql": "CREATE OR REPLACE FUNCTION public.lf_rule_promotion_report_v1(p_page integer DEFAULT 1, p_size integer DEFAULT 8)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public', 'extensions'\nAS $function$\ndeclare tot int; pages int; v_page int := greatest(coalesce(p_page,1),1); v_size int := least(greatest(coalesce(p_size,8),1),15); txt text; it jsonb := '[]'::jsonb; i int := 0; r record; cat text; avisos text;\nbegin\n select count(*) into tot from public.lf_rule_promotion_v1 where status='PENDING';\n pages := greatest(ceil(tot::numeric/v_size)::int,1);\n txt := 'LOTE '||v_page||' DE '||pages||' — reglas pendientes de tu aprobación: '||tot||E'\\n'||'Qué estás decidiendo: pasar cada regla de CANDIDATO (borrador) a VIGENTE (regla oficial).'||E'\\n';\n for r in\n  select p.promotion_id, p.rule_code, p.reason, p.requested_by_profile, g.categoria, g.titulo, g.descripcion, g.razon,\n   (select case when count(*)>3 then 'Transversal: aplica a '||count(*)||' pantallas' else string_agg(pa.nombre||' ('||pa.codigo||')', ', ' order by pa.codigo) end from lf_ops.reglas_pantallas rp join lf_ops.pantallas pa on pa.id=rp.pantalla_id where rp.regla_id=g.id) pantallas,\n   exists(select 1 from lf_ops.reglas v where v.estado='VIGENTE' and lower(btrim(v.titulo))=lower(btrim(g.titulo))) dup,\n   (p.request_snapshot_sha256 is distinct from public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code)) cambio,\n   (select count(*) from lf_ops.reglas_pantallas rp2 where rp2.regla_id=g.id) npant\n  from public.lf_rule_promotion_v1 p join lf_ops.reglas g on g.codigo=p.rule_code\n  where p.status='PENDING' order by 12, 9, 5, 2 offset (v_page-1)*v_size limit v_size\n loop\n  i := i+1;\n  cat := case r.categoria when 'SECURITY' then 'Seguridad' when 'UX' then 'Experiencia de usuario' else initcap(lower(r.categoria)) end;\n  avisos := '';\n  if r.dup then avisos := avisos||E'\\n   ⚠ Ya existe una regla VIGENTE con el mismo título: revisa que no sea duplicada.'; end if;\n  if r.cambio then avisos := avisos||E'\\n   ⚠ La regla cambió después de pedirla: no se podrá aprobar; hay que pedirla de nuevo.'; end if;\n  txt := txt||E'\\n'||i||'. '||r.titulo||E'\\n   Qué dice: '||left(r.descripcion,320)||case when length(r.descripcion)>320 then '…' else '' end\n        ||E'\\n   Para qué sirve: '||left(coalesce(r.razon,'(sin razón registrada)'),200)\n        ||E'\\n   Pantalla: '||coalesce(r.pantallas,'(sin pantalla)')||' · Tipo: '||cat\n        ||E'\\n   Pedida por: '||r.requested_by_profile||' — '||coalesce(split_part(r.reason,' | ',1),'')||avisos\n        ||E'\\n   Código de aprobación: '||r.promotion_id;\n  it := it||jsonb_build_array(jsonb_build_object('n',i,'promotion_id',r.promotion_id,'rule_code',r.rule_code,'dup',r.dup,'cambio',r.cambio));\n end loop;\n txt := txt||E'\\n\\nPara decidir: \"aprueba el lote\", \"aprueba todas menos la 3\", o \"rechaza la 5 (motivo)\".';\n return jsonb_build_object('page',v_page,'pages',pages,'total_pending',tot,'items',it,'text',txt);\nend $function$\n"
  }
]

UP = ROOT / "supabase/migrations/20261113112500_lf_b12_legacy_guard_execute_acl_hardening_v1.sql"
ROLLBACK_SCRIPT = ROOT / "audits/rule-quality-lote28/b12/02_guard_acl_hardening_rollback_v1.sql"
SCHEMA = """
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA lf_ops;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE TABLE lf_ops.reglas (
  id bigint PRIMARY KEY, codigo text UNIQUE NOT NULL, estado text NOT NULL,
  categoria text NOT NULL, titulo text NOT NULL, descripcion text NOT NULL,
  razon text, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
);
CREATE TABLE lf_ops.pantallas (id bigint PRIMARY KEY, nombre text NOT NULL, codigo text NOT NULL);
CREATE TABLE lf_ops.reglas_pantallas (regla_id bigint NOT NULL, pantalla_id bigint NOT NULL);
CREATE TABLE public.lf_rule_promotion_v1 (
  promotion_id text PRIMARY KEY, rule_code text NOT NULL, status text NOT NULL,
  request_snapshot_sha256 text NOT NULL, reason text, requested_by_profile text,
  decided_by text, decided_at timestamptz, applied_at timestamptz
);
GRANT USAGE ON SCHEMA lf_ops TO anon, authenticated;
GRANT SELECT ON TABLE lf_ops.reglas TO anon, authenticated;
"""

SCENARIOS = """
BEGIN;
INSERT INTO lf_ops.reglas (id,codigo,estado,categoria,titulo,descripcion,razon)
VALUES
(1,'B12-R1','CANDIDATO','SECURITY','B12 Regla 1','Prueba positiva','Prueba'),
(2,'B12-R2','CANDIDATO','SECURITY','B12 Regla 2','Prueba rechazo','Prueba'),
(3,'B12-R3','CANDIDATO','UX','B12 Regla 3','Prueba reporte','Prueba');
INSERT INTO lf_ops.pantallas VALUES(10,'Inicio','B12-UI-1');
INSERT INTO lf_ops.reglas_pantallas VALUES(1,10);
INSERT INTO public.lf_rule_promotion_v1(
 promotion_id,rule_code,status,request_snapshot_sha256,reason,requested_by_profile)
SELECT 'PROM-'||codigo,codigo,'PENDING',
 public.lf_asset_snapshot_sha_v1('REGLA',codigo),'B12 regression','PERFIL-B12-ONLY'
FROM lf_ops.reglas;

DO $b12$
DECLARE v jsonb; v2 jsonb; v3 jsonb; before_reason text; err text;
BEGIN
 -- REPORT: real query over fixture; read-only result and repeatable output.
 v := public.lf_rule_promotion_report_v1(1,8);
 IF (v->>'total_pending')::integer <> 3 OR jsonb_array_length(v->'items') <> 3
 THEN RAISE EXCEPTION 'B12_REPORT_POSITIVE_FAILED:%',v; END IF;
 v2 := public.lf_rule_promotion_report_v1(1,8);
 IF v IS DISTINCT FROM v2 THEN RAISE EXCEPTION 'B12_REPORT_NOT_IDEMPOTENT'; END IF;
 RAISE NOTICE 'PASS_B12_REPORT_POSITIVE_AND_IDEMPOTENT';

 -- DECIDE: real delegate + human credential format gate and replay.
 v:=public.lf_rule_promotion_decide_batch_v1(ARRAY['PROM-B12-R2'],'APPROVE',
       'SUPER_ADMIN','bad');
 IF (v->>'blocked')::integer <> 1 OR v->'detail'->0->>'code'<>'APPROVER_MUST_BE_HUMAN'
 THEN RAISE EXCEPTION 'B12_DECIDE_HUMAN_DENY_FAILED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_batch_v1(ARRAY['PROM-B12-R2'],'GRANT_ALL',
       'HUMAN:qa','bad');
 IF (v->>'blocked')::integer <> 1 OR v->'detail'->0->>'code'<>'DECISION_INVALID'
 THEN RAISE EXCEPTION 'B12_DECIDE_INVALID_FAILED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_batch_v1(ARRAY['PROM-B12-R1'],'APPROVE',
       'HUMAN:qa-b12','approved');
 IF (v->>'ok')::integer<>1 OR v->'detail'->0->>'status'<>'APPROVED'
 THEN RAISE EXCEPTION 'B12_DECIDE_POSITIVE_FAILED:%',v; END IF;
 SELECT reason INTO before_reason FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-B12-R1';
 v2:=public.lf_rule_promotion_decide_batch_v1(ARRAY['PROM-B12-R1'],'APPROVE',
       'HUMAN:qa-b12','approved');
 IF (v2->>'blocked')::integer<>1 OR v2->'detail'->0->>'code'<>'PROMOTION_NOT_PENDING'
 OR (SELECT reason FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-B12-R1') IS DISTINCT FROM before_reason
 THEN RAISE EXCEPTION 'B12_DECIDE_REPLAY_SIDE_EFFECT:%',v2; END IF;
 RAISE NOTICE 'PASS_B12_DECIDE_POSITIVE_NEGATIVE_IDEMPOTENT';

 -- GUARD negative: direct candidate to VIGENTE without approval MUST throw.
 BEGIN
  UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-R2';
  RAISE EXCEPTION 'B12_GUARD_EXPECTED_ERROR_NOT_RAISED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err = MESSAGE_TEXT;
  IF err NOT LIKE 'LF_RULE_PROMOTION_REQUIRED:%'
  THEN RAISE EXCEPTION 'B12_GUARD_WRONG_ERROR:%',err; END IF;
 END;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo='B12-R2')<>'CANDIDATO'
 THEN RAISE EXCEPTION 'B12_GUARD_DID_NOT_ROLLBACK'; END IF;
 RAISE NOTICE 'PASS_B12_GUARD_EXPECTED_ERROR_FAIL_CLOSED';

 -- APPLY: exact legacy function; guard validates approved snapshot.
 v:=public.lf_rule_promotion_apply_batch_v1(ARRAY['PROM-B12-R1']);
 IF (v->>'applied')::integer<>1 OR (v->'detail'->0->>'status')<>'APPLIED'
 OR (SELECT estado FROM lf_ops.reglas WHERE codigo='B12-R1')<>'VIGENTE'
 THEN RAISE EXCEPTION 'B12_APPLY_POSITIVE_FAILED:%',v; END IF;
 v2:=public.lf_rule_promotion_apply_batch_v1(ARRAY['PROM-B12-R1']);
 IF (v2->>'blocked')::integer<>1 OR v2->'detail'->0->>'code'<>'PROMOTION_NOT_APPROVED'
 OR (SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE status='APPLIED')<>1
 THEN RAISE EXCEPTION 'B12_APPLY_REPLAY_SIDE_EFFECT:%',v2; END IF;
 v3:=public.lf_rule_promotion_apply_batch_v1(ARRAY['PROM-NOT-FOUND']);
 IF (v3->>'blocked')::integer<>1 OR v3->'detail'->0->>'code'<>'PROMOTION_NOT_FOUND'
 THEN RAISE EXCEPTION 'B12_APPLY_UNKNOWN_NOT_DENIED:%',v3; END IF;
 RAISE NOTICE 'PASS_B12_APPLY_POSITIVE_NEGATIVE_IDEMPOTENT';

 -- GUARD positive/idempotence: VIGENTE to VIGENTE is permitted.
 UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-R1';
 IF (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'B12_RULE_LOSS'; END IF;
 RAISE NOTICE 'PASS_B12_GUARD_POSITIVE_IDEMPOTENT_NO_RULE_LOSS';

 -- REPORT pages/inputs after first approval+apply, no write on repeated read.
 v:=public.lf_rule_promotion_report_v1(NULL,-99);
 IF (v->>'page')::integer<>1 OR (v->>'total_pending')::integer<>2
 THEN RAISE EXCEPTION 'B12_REPORT_NORMALIZATION:%',v; END IF;
 v2:=public.lf_rule_promotion_report_v1(NULL,-99);
 IF v IS DISTINCT FROM v2 THEN RAISE EXCEPTION 'B12_REPORT_READ_CHANGED'; END IF;
 RAISE NOTICE 'PASS_B12_REPORT_INPUT_NORMALIZATION';
END $b12$;
ROLLBACK;
SELECT 'B12_ROLLBACK_CLEAN|'||
 CASE WHEN (SELECT count(*) FROM lf_ops.reglas)=0
       AND (SELECT count(*) FROM public.lf_rule_promotion_v1)=0
       AND (SELECT count(*) FROM lf_ops.reglas_pantallas)=0
 THEN 'true' ELSE 'false' END;
"""

class B12DualPG(unittest.TestCase):
    def sql(self, container, sql, error=None, timeout=180):
        p = subprocess.run(
          ['docker','exec','-i',container,'psql','-X','-A','-t','-v','ON_ERROR_STOP=1',
           '-U','postgres','-d','postgres'],
          input=sql,text=True,capture_output=True,timeout=timeout
        )
        if error:
            self.assertNotEqual(p.returncode,0,
                'B12_EXPECTED_ERROR_ACCEPTED:'+error+' '+p.stdout[-800:])
            self.assertIn(error,p.stderr,
                'B12_WRONG_ERROR:'+p.stderr[-1400:])
            return p.stderr
        self.assertEqual(p.returncode,0,
            'B12_SQL_FAILED:'+p.stderr[-2600:]+' QUERY:'+sql[:400])
        return p.stdout.strip()

    def check_one(self, image, expected_num):
        name = 'lf-b12-'+uuid.uuid4().hex[:12]
        p = subprocess.run(
          ['docker','run','-d','--rm','--name',name,'-e','POSTGRES_PASSWORD=b12',
           '-e','POSTGRES_DB=postgres',image],
          text=True,capture_output=True,timeout=240
        )
        self.assertEqual(p.returncode,0,'B12_DOCKER_UNAVAILABLE:'+image+':'+p.stderr[-1000:])
        try:
            for _ in range(60):
                ready = subprocess.run(['docker','exec',name,'pg_isready','-U','postgres'],
                      capture_output=True,text=True,timeout=10)
                if ready.returncode==0: break
                time.sleep(1)
            else: self.fail('B12_POSTGRES_NOT_READY:'+image)
            # pg_isready can hit the temporary initdb server before final
            # PostgreSQL restarts; poll the final exact-version connection.
            number=None
            for attempt in range(15):
                try:
                    number=int(self.sql(name,'SHOW server_version_num;'))
                    break
                except AssertionError as exc:
                    if "connection to server on socket" not in str(exc):
                        raise
                    time.sleep(1)
            self.assertIsNotNone(number,"B12_POSTGRES_STARTUP_NOT_READY:"+image)
            self.assertEqual(number//10000,expected_num,'B12_WRONG_POSTGRES_VERSION')
            version=self.sql(name,'SHOW server_version;')
            self.assertTrue(version.startswith(str(expected_num)+'.'),
                  'B12_WRONG_POSTGRES_PATCH:'+version)
            self.assertEqual(version.split(' ')[0],image.split(':',1)[1],
                  'B12_REQUIRED_EXACT_PATCH:'+version)
            self.sql(name,SCHEMA)
            frozen=json.loads(FREEZE.read_text(encoding='utf-8'))
            frozen_sha={x['name']:x['sha256_pg_get_functiondef'] for x in frozen['functions']}
            for obj in SOURCES:
                if obj['name'] in frozen_sha:
                    actual=hashlib.sha256(obj['sql'].encode('utf-8')).hexdigest()
                    self.assertEqual(actual,frozen_sha[obj['name']],
                         'B12_LIVE_SOURCE_SHA256_DRIFT:'+obj['name'])
                self.sql(name,obj['sql'].rstrip().rstrip(';')+';\n')
            self.sql(name,"""CREATE TRIGGER b12_promotion_guard
              BEFORE UPDATE OF estado ON lf_ops.reglas FOR EACH ROW
              EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();
              REVOKE ALL ON FUNCTION
                public.lf_rule_promotion_apply_batch_v1(text[]),
                public.lf_rule_promotion_decide_batch_v1(text[],text,text,text),
                public.lf_rule_promotion_report_v1(integer,integer) FROM PUBLIC;
              GRANT EXECUTE ON FUNCTION
                public.lf_rule_promotion_apply_batch_v1(text[]),
                public.lf_rule_promotion_decide_batch_v1(text[],text,text,text),
                public.lf_rule_promotion_report_v1(integer,integer)
                TO service_role;
              GRANT EXECUTE ON FUNCTION
                public.lf_rule_promotion_apply_batch_v1(text[]),
                public.lf_rule_promotion_decide_batch_v1(text[],text,text,text),
                public.lf_rule_promotion_report_v1(integer,integer)
                TO postgres;
              GRANT EXECUTE ON FUNCTION
                public.lf_rule_promotion_guard_v1() TO anon, authenticated, service_role;""")
            for f in [
                "lf_rule_promotion_apply_batch_v1(ARRAY['PROM-X'])",
                "lf_rule_promotion_decide_batch_v1(ARRAY['PROM-X'],'APPROVE','HUMAN:qa','test')",
                "lf_rule_promotion_report_v1(1,8)",
            ]:
                self.sql(name,'SET ROLE anon; SELECT public.'+f+';',error='permission denied')
            self.sql(name,"SET ROLE anon; UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-R2';",
                     error='permission denied')
            print('PASS_B12_PERMISSIONS_DENY_ANON_'+image,flush=True)
            result=self.sql(name,SCENARIOS,timeout=180)
            self.assertIn('B12_ROLLBACK_CLEAN|true',result,
                'B12_ROLLBACK_NOT_CLEAN:'+result)
            self.check_guard_acl(name, image)
            # Confirm execution of all notices rather than assuming DO completes.
            print('PASS_B12_TRANSACTIONAL_BEHAVIOR_AND_ROLLBACK_'+image,flush=True)
            print('B12_EXACT_VERSION='+version+' B12_SOURCE_COUNT='+str(len(SOURCES)),flush=True)
        finally:
            subprocess.run(['docker','rm','-f',name],capture_output=True,text=True,timeout=30)

    def check_guard_acl(self, name, image):
        """Trigger EXECUTE exposure: direct, UPDATE, REVOKE, rollback, legitimate 4-function flow."""
        sig = "'public.lf_rule_promotion_guard_v1()'::regprocedure"
        roles = ("anon", "authenticated")
        for role in roles:
            is_allowed = self.sql(name,
                f"SELECT has_function_privilege('{role}',{sig},'EXECUTE');")
            self.assertEqual(is_allowed, "t", "B12_GUARD_INITIAL_EXECUTE_NOT_GRANTED:"+role)
            self.sql(name, f"BEGIN; SET LOCAL ROLE {role}; "
                     "SELECT public.lf_rule_promotion_guard_v1();",
                     error="trigger functions can only be called as triggers")
            self.sql(name, "BEGIN; "
                     "INSERT INTO lf_ops.reglas(id,codigo,estado,categoria,titulo,descripcion)"
                     "VALUES (999,'B12-ACL','CANDIDATO','SECURITY','ACL','ACL'); "
                     f"SET LOCAL ROLE {role}; "
                     "UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-ACL';",
                     error="permission denied for table reglas")
        print("PASS_B12_GUARD_DIRECT_UNCALLABLE_AND_UPDATE_DENIED_BY_TABLE_ACL_"+image,
              flush=True)

        # Proof that permission on the table is a separate boundary from
        # EXECUTE on a trigger function. These grants are DOCKER-ONLY.
        self.sql(name,"GRANT UPDATE(estado) ON lf_ops.reglas TO anon, authenticated;")
        for role in roles:
            before = self.sql(name, "SELECT count(*) FROM lf_ops.reglas;")
            self.assertEqual(before,"0","B12_GUARD_PRE_TEST_ROW_DRIFT")
            self.sql(name, "BEGIN; "
                "INSERT INTO lf_ops.reglas(id,codigo,estado,categoria,titulo,descripcion)"
                "VALUES (999,'B12-ACL','CANDIDATO','SECURITY','ACL','ACL'); "
                f"SET LOCAL ROLE {role}; "
                "UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-ACL';",
                error="LF_RULE_PROMOTION_REQUIRED:B12-ACL")
            self.assertEqual(self.sql(name,"SELECT count(*) FROM lf_ops.reglas;"),"0",
                "B12_GUARD_PRE_REVOKE_ERROR_ROLLBACK")
        print("PASS_B12_GUARD_UPDATE_PRIVILEGE_DOES_NOT_BYPASS_GUARD_"+image,flush=True)

        revoke = ("REVOKE EXECUTE ON FUNCTION public.lf_rule_promotion_guard_v1() "
                  "FROM PUBLIC, anon, authenticated;")
        # Transactional ACL rollback proof. After ROLLBACK, original grants survive.
        acl = self.sql(name, "BEGIN; "+revoke+
            f" SELECT has_function_privilege('anon',{sig},'EXECUTE')::text||'|'||"
            f"has_function_privilege('authenticated',{sig},'EXECUTE')::text;"
            " ROLLBACK;"
            f" SELECT has_function_privilege('anon',{sig},'EXECUTE')::text||'|'||"
            f"has_function_privilege('authenticated',{sig},'EXECUTE')::text;")
        self.assertEqual([line for line in acl.splitlines() if line in ("false|false","true|true")],
            ["false|false","true|true"],
            "B12_GUARD_ACL_REVOKE_ROLLBACK_FAILED:"+acl)
        print("PASS_B12_GUARD_REVOKE_TRANSACTION_ROLLBACK_"+image,flush=True)

        # Apply the proposed ACL to the disposable container only.
        # Execute the ACTUAL candidate migration, including four live-source
        # MD5/ACL preflight gates and postflight checks. Not hand-written REVOKE.
        self.sql(name, UP.read_text(encoding="utf-8"))
        actual_post=self.sql(name, "SELECT proacl::text FROM pg_proc WHERE "
             "oid='public.lf_rule_promotion_guard_v1()'::regprocedure;")
        self.assertEqual(actual_post,
             "{postgres=X/postgres,service_role=X/postgres}",
             "B12_UP_POSTFLIGHT_ACL_NOT_EXACT:"+actual_post)
        print("PASS_B12_EXACT_UP_MIGRATION_PREFLIGHT_POSTFLIGHT_"+image,flush=True)
        for role in roles:
            self.assertEqual(self.sql(name,
                f"SELECT has_function_privilege('{role}',{sig},'EXECUTE');"),"f",
                "B12_GUARD_REVOKE_NOT_ENFORCED:"+role)
            self.sql(name, f"BEGIN; SET LOCAL ROLE {role}; "
                     "SELECT public.lf_rule_promotion_guard_v1();",
                     error="permission denied for function lf_rule_promotion_guard_v1")
            self.sql(name, "BEGIN; "
                "INSERT INTO lf_ops.reglas(id,codigo,estado,categoria,titulo,descripcion)"
                "VALUES (999,'B12-ACL','CANDIDATO','SECURITY','ACL','ACL'); "
                f"SET LOCAL ROLE {role}; "
                "UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='B12-ACL';",
                error="LF_RULE_PROMOTION_REQUIRED:B12-ACL")
            self.assertEqual(self.sql(name,"SELECT count(*) FROM lf_ops.reglas;"),"0",
                "B12_GUARD_POST_REVOKE_ERROR_ROLLBACK")
        self.assertEqual(self.sql(name,
            f"SELECT has_function_privilege('service_role',{sig},'EXECUTE');"),"t",
            "B12_GUARD_SERVICE_ROLE_ACCESS_LOST")
        print("PASS_B12_GUARD_POST_REVOKE_DIRECT_DENY_TRIGGER_STILL_ENFORCED_"+image,
              flush=True)

        # End-to-end legal caller (service_role): report -> decide_batch ->
        # apply_batch -> trigger guard -> report; no persistent test rows.
        positive = self.sql(name, """
BEGIN;
INSERT INTO lf_ops.reglas(id,codigo,estado,categoria,titulo,descripcion,razon)
VALUES (997,'B12-LEGIT','CANDIDATO','SECURITY','B12 legitimate','only sandbox','sandbox');
INSERT INTO public.lf_rule_promotion_v1(
 promotion_id,rule_code,status,request_snapshot_sha256,reason,requested_by_profile)
SELECT 'PROM-B12-LEGIT',codigo,'PENDING',
 public.lf_asset_snapshot_sha_v1('REGLA',codigo),'sandbox','PERFIL-B12-ONLY'
FROM lf_ops.reglas WHERE codigo='B12-LEGIT';
SET LOCAL ROLE service_role;
DO $b12acl$
DECLARE v jsonb;
BEGIN
 v:=public.lf_rule_promotion_report_v1(1,8);
 IF (v->>'total_pending')::integer<>1 THEN
   RAISE EXCEPTION 'B12_LEGIT_REPORT_PRE_FAILED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_batch_v1(
   ARRAY['PROM-B12-LEGIT'],'APPROVE','HUMAN:b12-sandbox','no actual owner identity');
 IF (v->>'ok')::integer<>1 OR v->'detail'->0->>'status'<>'APPROVED' THEN
   RAISE EXCEPTION 'B12_LEGIT_DECIDE_FAILED:%',v; END IF;
 v:=public.lf_rule_promotion_apply_batch_v1(ARRAY['PROM-B12-LEGIT']);
 IF (v->>'applied')::integer<>1 OR v->'detail'->0->>'status'<>'APPLIED' THEN
   RAISE EXCEPTION 'B12_LEGIT_APPLY_GUARD_FAILED:%',v; END IF;
 v:=public.lf_rule_promotion_report_v1(1,8);
 IF (v->>'total_pending')::integer<>0 THEN
   RAISE EXCEPTION 'B12_LEGIT_REPORT_POST_FAILED:%',v; END IF;
END $b12acl$;
RESET ROLE;
SELECT 'B12_LEGIT_BEFORE_ROLLBACK|'||(
 SELECT CASE WHEN (SELECT estado FROM lf_ops.reglas WHERE codigo='B12-LEGIT')='VIGENTE'
 AND (SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='PROM-B12-LEGIT')='APPLIED'
 THEN 'true' ELSE 'false' END);
ROLLBACK;
SELECT 'B12_LEGIT_ROLLBACK_CLEAN|'||
  CASE WHEN (SELECT count(*) FROM lf_ops.reglas)=0
        AND (SELECT count(*) FROM public.lf_rule_promotion_v1)=0
  THEN 'true' ELSE 'false' END;
""",timeout=120)
        self.assertIn("B12_LEGIT_BEFORE_ROLLBACK|true",positive,
            "B12_LEGIT_WORKFLOW_DID_NOT_COMPLETE:"+positive)
        self.assertIn("B12_LEGIT_ROLLBACK_CLEAN|true",positive,
            "B12_LEGIT_ROLLBACK_FAILED:"+positive)
        print("PASS_B12_LEGITIMATE_FOUR_FUNCTION_FLOW_AFTER_REVOKE_"+image,
              flush=True)
        # Return Docker to original SQL-role permission state.
        # B12_DIAG_ONLY: inspect real ACL tuples AFTER rollback GRANT, inside
        # a disposable transaction. Prints expected vs actual in BOTH PG versions.
        acl_tuple_sql = "SELECT 'B12_ACLEXPLODE|'||COALESCE(jsonb_agg(\njsonb_build_object('grantee', CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,\n'privilegio',x.privilege_type,'grantor',pg_get_userbyid(x.grantor),'is_grantable',x.is_grantable)\nORDER BY CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,\nx.privilege_type,pg_get_userbyid(x.grantor),x.is_grantable),'[]'::jsonb)::text\nFROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) x\nWHERE p.oid='public.lf_rule_promotion_guard_v1()'::regprocedure;"
        # Expected is the ORIGINAL frozen ACL, not the post-UP ACL.
        frozen_acl=next(f["acl_raw"] for f in json.loads(FREEZE.read_text(encoding="utf-8"))["functions"]
                        if f["name"]=="lf_rule_promotion_guard_v1")
        baseline_sql=acl_tuple_sql.replace(
            "FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) x\\nWHERE p.oid='public.lf_rule_promotion_guard_v1()'::regprocedure;",
            "FROM aclexplode('"+frozen_acl+"'::aclitem[]) x;")
        if baseline_sql==acl_tuple_sql:
            self.fail("B12_EXPECTED_ACL_SOURCE_REPLACEMENT_MISSING")
        expected_acl = self.sql(name, baseline_sql)
        diagnostic = self.sql(name,
            "BEGIN; GRANT EXECUTE ON FUNCTION "
            "public.lf_rule_promotion_guard_v1() TO PUBLIC, anon, authenticated; "
            + acl_tuple_sql + " ROLLBACK;")
        actual_rows = [line for line in diagnostic.splitlines()
                       if line.startswith("B12_ACLEXPLODE|")]
        self.assertEqual(len(actual_rows),1,"B12_DIAG_ACLEXPLODE_MISSING:"+diagnostic)
        print("B12_ACLEXPLODE_EXPECTED_FROM_FREEZE_"+image+"="+expected_acl,flush=True)
        print("B12_ACLEXPLODE_REAL_AFTER_ROLLBACK_GRANT_"+image+"="+actual_rows[0],flush=True)
        self.assertEqual(expected_acl,actual_rows[0],
           "B12_ACLEXPLODE_FROZEN_SET_MISMATCH:"+actual_rows[0])
        print("PASS_B12_ACLEXPLODE_FROZEN_SET_MATCH_"+image,flush=True)
        self.sql(name,ROLLBACK_SCRIPT.read_text(encoding="utf-8"))
        self.sql(name, "REVOKE UPDATE(estado) ON lf_ops.reglas FROM anon, authenticated;")
        print("PASS_B12_EXACT_ROLLBACK_FILE_RESTORES_PREIMAGE_"+image,flush=True)
        for role in roles:
            self.assertEqual(self.sql(name,
                f"SELECT has_function_privilege('{role}',{sig},'EXECUTE');"),"t",
                "B12_GUARD_ORIGINAL_ACL_NOT_RESTORED")
        print("PASS_B12_GUARD_FIXTURE_ACL_RESTORED_"+image,flush=True)

    def test_pg17_6(self): self.check_one('postgres:17.6',17)
    def test_pg18_7(self): self.check_one('postgres:18.7',18)

if __name__=='__main__':
    unittest.main(verbosity=2)
