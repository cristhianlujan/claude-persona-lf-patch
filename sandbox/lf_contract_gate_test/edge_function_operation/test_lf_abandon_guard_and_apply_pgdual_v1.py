"""Owner 22:08: PG17/18 exact guard exception, bulk stale abandonment under rollback."""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261116030000_lf_abandon_guard_and_apply_v1.sql"
PRIOR=ROOT/"supabase/migrations/20261116020000_lf_generic_rule_engine_and_abandon_v1.sql"
TABLES=r"""
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text NOT NULL,
 status text NOT NULL DEFAULT 'IN_PROGRESS',
 updated_at timestamptz NOT NULL DEFAULT now(),
 started_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 manifest jsonb NOT NULL DEFAULT '{}'::jsonb);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text NOT NULL,step_order int NOT NULL,
 observed_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.lf_policy_versions (
 policy_code text,policy_version text,policy_sha text,
 effective_at timestamptz,superseded_at timestamptz);
"""
FIXTURES=r"""
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,status,updated_at,started_at,manifest) VALUES
 ('LEG','EJECUCION_PERFIL_LF','IN_PROGRESS',now()-interval '48 hours',now()-interval '50 hours','{}'),
 ('SNAP','EJECUCION_PERFIL_LF','IN_PROGRESS',now()-interval '48 hours',now()-interval '50 hours',
 '{"operation_policy_snapshots":{"owner":{"policy_code":"EXISTING","policy_version":"v1","policy_sha":"abc"}}}'),
 ('REC','EJECUCION_PERFIL_LF','IN_PROGRESS',now()-interval '1 hour',now()-interval '2 hours','{}'),
 ('OLDSTEP','EJECUCION_PERFIL_LF','IN_PROGRESS',now()-interval '48 hours',now()-interval '50 hours','{}');
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,observed_at)
 VALUES('OLDSTEP',40,now()-interval '1 hour');
"""
READBACK=r"""
SELECT 'STATUS='||execution_id||':'||status
 FROM public.lf_operation_execution ORDER BY execution_id;
SELECT 'MARKER='||execution_id||':'||(manifest->>'abandoned_reason')
 FROM public.lf_operation_execution
 WHERE status='ABANDONED' ORDER BY execution_id;
SELECT 'COUNT_ABANDONED='||count(*) FROM public.lf_operation_execution WHERE status='ABANDONED';
SELECT 'COUNT_IN_PROGRESS='||count(*) FROM public.lf_operation_execution WHERE status='IN_PROGRESS';
DO $negative$
BEGIN
 BEGIN
  UPDATE public.lf_operation_execution
   SET manifest=jsonb_set(manifest,'{operation_policy_snapshots,owner,policy_sha}','"illegal"',true)
   WHERE execution_id='SNAP';
  RAISE EXCEPTION 'MISSING_IMMUTABILITY_GUARD';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM LIKE 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE%' THEN
   RAISE NOTICE 'NEGATIVE_IMMUTABLE_PASS';
  ELSE
   RAISE;
  END IF;
 END;
END $negative$;
SELECT 'STILL_SNAPSHOT='||(manifest#>>'{operation_policy_snapshots,owner,policy_sha}')
 FROM public.lf_operation_execution WHERE execution_id='SNAP';
"""
class AbandonGuardPGDual(unittest.TestCase):
 def test_legacy_snapshot_recent_immutability_and_rollback(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=MIG.read_text(encoding="utf-8")
  prior=PRIOR.read_text(encoding="utf-8")
  exception=" AND NOT (NEW.status='ABANDONED' AND OLD.status='IN_PROGRESS' AND NEW.manifest ? 'abandoned_reason')"
  self.assertEqual(migration.count(exception),1)
  self.assertTrue(migration.startswith("BEGIN;\n"))
  self.assertTrue(migration.rstrip().endswith("COMMIT;"))
  old_guard=migration.split("CREATE OR REPLACE FUNCTION public.lf_operation_policy_snapshot_guard_v1()",1)[1].split("\nDO $ab$",1)[0].replace(exception,"")
  old_guard="CREATE OR REPLACE FUNCTION public.lf_operation_policy_snapshot_guard_v1()"+old_guard
  self.assertNotIn(" AND NOT (NEW.status='ABANDONED'",old_guard)
  old_abandon="CREATE OR REPLACE FUNCTION public.lf_execution_mark_abandoned_v1"+prior.split(
   "CREATE OR REPLACE FUNCTION public.lf_execution_mark_abandoned_v1",1)[1].split(
   "\nINSERT INTO lf_ops.regla_behavior_tests",1)[0].strip()
  body=migration.split("BEGIN;\n",1)[1].rsplit("COMMIT;",1)[0]
  sql_tx=("BEGIN;\n"+TABLES+"\n"+old_abandon+"\n"+old_guard+"\n"+
    "CREATE TRIGGER trg_01_lf_operation_policy_snapshot_guard_v1 "+
    "BEFORE UPDATE OF status,manifest ON public.lf_operation_execution "+
    "FOR EACH ROW EXECUTE FUNCTION public.lf_operation_policy_snapshot_guard_v1();\n"+
    FIXTURES+"\n"+body+"\n"+READBACK+"\nROLLBACK;\n"+
    "SELECT 'POST_ROLLBACK_TABLE_ABSENT='||"+
    "(to_regclass('public.lf_operation_execution') IS NULL)::text;\n")
  for pg in ("17.6","18.7"):
   with self.subTest(engine=pg):
    name="lf-abandon-v1-"+uuid.uuid4().hex[:10]
    started=subprocess.run(["docker","run","-d","--rm","--name",name,
     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
     capture_output=True,text=True,timeout=180)
    self.assertEqual(started.returncode,0,started.stderr[-2000:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     proc=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=sql_tx,capture_output=True,text=True,timeout=180)
     self.assertEqual(proc.returncode,0,proc.stderr[-5000:]+"\n"+proc.stdout[-3000:])
     for marker in (
       "STATUS=LEG:ABANDONED","STATUS=SNAP:ABANDONED",
       "STATUS=REC:IN_PROGRESS","STATUS=OLDSTEP:IN_PROGRESS",
       "COUNT_ABANDONED=2","COUNT_IN_PROGRESS=2",
       "MARKER=LEG:SIN_AVANCE_24H_OWNER_20261115",
       "MARKER=SNAP:SIN_AVANCE_24H_OWNER_20261115",
       "STILL_SNAPSHOT=abc",
       "POST_ROLLBACK_TABLE_ABSENT=true"
     ):
      self.assertIn(marker,proc.stdout,marker+"\n"+proc.stdout[-2500:])
     self.assertIn("NEGATIVE_IMMUTABLE_PASS",proc.stderr)
     print("PASS_ABANDON_GUARD_PG"+pg+"_LEG_SNAP_REC_IMMUTABLE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

if __name__=="__main__":
 unittest.main()
