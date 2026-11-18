#!/usr/bin/env python3
"""Isolated PostgreSQL17 real BEGIN/ROLLBACK for Client global config prerequisite."""
import os,sys,re,json,hashlib,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/".lf_ci/chat9_client_config"
OUT.mkdir(parents=True,exist_ok=True)
def sql(query):
    return subprocess.run(
      ["psql","-X","-v","ON_ERROR_STOP=1","-t","-A",
       "-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres","-f","-"],
      input=query,text=True,capture_output=True,timeout=130,check=False,env=os.environ.copy())
def yes(q,what):
    r=sql(q)
    if r.returncode!=0:raise AssertionError(what+" "+r.stderr[-1500:])
    return r.stdout
def snapshot():
    q="""SELECT jsonb_build_object(
       'configs',(SELECT count(*) FROM public.lf_global_config),
       'rules',(SELECT count(*) FROM lf_ops.reglas),
       'vigente',(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE'),
       'candidato',(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO'),
       'config_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(c) ORDER BY scope,config_key)::text,'[]')) FROM public.lf_global_config c),
       'rule_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r))::text;"""
    return json.loads(yes(q,"SNAPSHOT").strip().splitlines()[-1])
def main():
    report={"status":"FAIL","db":"EPHEMERAL_POSTGRESQL17","remote_writes":False,"rules_updated":0}
    try:
        assert os.environ.get("GITHUB_EVENT_NAME")=="pull_request"
        assert os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch"
        head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
        assert head==os.environ.get("CLIENT_EXACT_HEAD")
        report["head"]=head
        paths=list((ROOT/"supabase/migrations").glob("*_lf_ig_chat9_client_antiabuse_config_v1.sql"))
        assert len(paths)==1
        source=paths[0].read_text()
        assert source.count("\nBEGIN;")==1 and source.count("\nCOMMIT;")==1
        assert not re.search(r"\b(?:UPDATE|INSERT INTO|DELETE FROM)\s+lf_ops\.reglas\b",source,re.I)
        report["source_sha256"]=hashlib.sha256(source.encode()).hexdigest()
        setup="""
CREATE SCHEMA lf_ops;
CREATE TABLE public.lf_global_config(
  scope text NOT NULL, config_key text NOT NULL, config_value text NOT NULL,
  value_type text NOT NULL CHECK(value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
  value_status text NOT NULL CHECK(value_status IN ('REAL','FICTICIO')),
  description text,valid_from timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(scope,config_key,valid_from));
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status)
 SELECT 'AUTH','BASELINE_'||i::text,'1','INTEGER','REAL' FROM generate_series(1,40) i;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY,estado text NOT NULL,valor_config jsonb);
INSERT INTO lf_ops.reglas
 SELECT 'EXISTING_'||i::text,CASE WHEN i<=436 THEN 'VIGENTE' ELSE 'CANDIDATO' END,'{}'::jsonb
 FROM generate_series(1,577) i;
INSERT INTO lf_ops.reglas VALUES
 ('REG_SES_003','VIGENTE','{"max_sesiones":1,"ventana_minutos":5}'::jsonb),
 ('REG_ATQ_016','VIGENTE','{"accion":"bloqueo_ip_1h_y_alerta","patron_1":{"ventana_minutos":10,"dni_distintos_por_ip":20},"patron_2":{"ips_por_dni":5,"ventana_minutos":10}}'::jsonb);
CREATE TABLE lf_ops.politicas_sesion(policy_code text,status text,max_concurrent_sessions integer);
INSERT INTO lf_ops.politicas_sesion VALUES('SESSION-CLIENT-DEFAULT','VIGENTE',3);
"""
        yes(setup,"FIXTURE_SCHEMA")
        before=snapshot()
        assert [before["configs"],before["rules"],before["vigente"],before["candidato"]]==[40,579,438,141]
        body=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        positive="BEGIN;\n"+body+"""
SELECT CASE WHEN
 (SELECT COUNT(*) FROM public.lf_global_config)=46
 AND (SELECT COUNT(*) FROM public.lf_global_config WHERE scope='CLIENT')=6
 AND (SELECT COUNT(*) FROM public.lf_global_config WHERE scope='CLIENT'
      AND value_type='INTEGER' AND value_status='REAL')=6
 AND (SELECT COUNT(*) FROM lf_ops.reglas)=579
 THEN 'SIX_GLOBAL_CONFIG_PASS' ELSE 'CONFIG_FAIL' END;
UPDATE public.lf_global_config SET config_value='4'
 WHERE scope='CLIENT' AND config_key='ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS';
SELECT CASE WHEN (SELECT config_value::integer FROM public.lf_global_config
 WHERE scope='CLIENT' AND config_key='ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS'
 ORDER BY valid_from DESC LIMIT 1)=4 THEN 'DYNAMIC_CONFIG_PASS' ELSE 'DYNAMIC_FAIL' END;
ROLLBACK;
"""
        out=yes(positive,"POSITIVE_SQL")
        assert "SIX_GLOBAL_CONFIG_PASS" in out and "DYNAMIC_CONFIG_PASS" in out
        assert snapshot()==before
        checks={"positive_begin_rollback":True,"dynamic_config_update":True,"separate_select_restore":True}
        negatives={
         "session_policy_drift":("UPDATE lf_ops.politicas_sesion SET max_concurrent_sessions=2;",
                                "IG_CHAT9_L2_CLIENT_BASELINE_DRIFT"),
         "rule_session_drift":("UPDATE lf_ops.reglas SET valor_config='{}'::jsonb WHERE codigo='REG_SES_003';",
                               "IG_CHAT9_L2_CLIENT_BASELINE_DRIFT"),
         "rule_atq_drift":("UPDATE lf_ops.reglas SET valor_config='{}'::jsonb WHERE codigo='REG_ATQ_016';",
                          "IG_CHAT9_L2_CLIENT_BASELINE_DRIFT"),
         "config_collision":("DELETE FROM public.lf_global_config WHERE scope='AUTH' AND config_key='BASELINE_40'; INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES('CLIENT','ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS','9','INTEGER','REAL');",
                              "IG_CHAT9_L2_KEY_EXISTS")
        }
        for name,(tamper,error) in negatives.items():
            r=sql("BEGIN;\n"+tamper+"\n"+body+"\nROLLBACK;\n")
            assert r.returncode!=0 and error in r.stderr,(name,r.stderr[-1100:])
            assert snapshot()==before,name
            checks[name]=True
        report.update(status="PASS",checks=checks,preimage=before,readback=snapshot(),
          expected={"configs_after_apply":46,"client_keys":6,"rules":579,"effects":"CONFIG_ONLY"})
    except Exception as e:
        report["error"]=str(e)[:1200]
    (OUT/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,sort_keys=True))
    return 0 if report["status"]=="PASS" else 1
if __name__=="__main__":sys.exit(main())
