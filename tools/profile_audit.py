#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SKILL=ROOT/'skills'/'creating-integral-user-stories'
CONFIG={
'A24':{'path':'perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md','agent':'agents/cross-cutting-enricher.md','judges':['J05_OBSERVATIONS_ERRORS','J06_SECURITY_PRIVACY','J07_AUDIT_TRACEABILITY','J08_TOKENS_MESSAGES','J09_ANALYTICS_OBSERVABILITY'],'writes':['observations','errors','security_privacy','states','audit','tokens_messages','analytics','observability','responsive_accessibility','dependencies_risks','evidence'],'quality':['analytics_events_with_pii','audit_events_without_source_reference','cross_tenant_access','hardcoded_color_count','critical_failures_without_alert_decision']},
'A25':{'path':'perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md','agent':'agents/field-contract-author.md','judges':['J04_FIELD_CONTRACTS'],'writes':['fields','validations','field_coverage','pending_decisions','evidence'],'quality':['fields_without_contract','unexpected_field_contracts','pii_fields_with_analytics_allowed','editable_fields_without_audit_strategy','fields_without_validation_mapping']},
'A26':{'path':'perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md','agent':'agents/screen-decomposer.md','judges':['J01_SOURCE_INTEGRITY','J02_SCREEN_DECOMPOSITION'],'writes':['screen_decomposition','coverage_matrix','pending_decisions','evidence'],'quality':['unmapped_count','unjustified_count','duplicate_functional_units','confirmed_rules_have_source']},
}
HEAD=re.compile(r'^##\s+(\d+)\.\s+(.+?)\s*$',re.M)
CODE=re.compile(r'(?<!`)`([^`\n]+)`(?!`)')

def sections(text):
    rows=list(HEAD.finditer(text)); out={}
    for i,m in enumerate(rows):
        out[int(m.group(1))]=text[m.end():rows[i+1].start() if i+1<len(rows) else len(text)]
    return out

def tokens(block): return set(CODE.findall(block))

def evaluate(code,text):
    c=CONFIG[code]; s=sections(text); findings=[]
    def need(name,ok):
        if not ok: findings.append(name)
    need('sections_1_14',set(range(1,15))<=set(s))
    need('candidate_read_only','CANDIDATO_READ_ONLY' in s.get(1,''))
    need('runtime_disabled','Runtime: deshabilitado' in s.get(1,''))
    need('production_not_authorized','Producción: no autorizada' in s.get(1,''))
    need('merge_not_authorized','Merge: no autorizado' in s.get(1,''))
    need('agent_ref',c['agent'] in s.get(1,'') and (SKILL/c['agent']).is_file())
    need('inputs_nonempty',len(tokens(s.get(3,'')))>=4)
    need('tools_nonempty',len(tokens(s.get(4,'')))>=3)
    need('read_scope',all(x in s.get(5,'').lower() for x in ('task packet','fuente','evidencia')))
    need('write_scope_exact',set(c['writes'])==tokens(s.get(6,'')))
    prohibited=s.get(7,'')
    need('prohibitions',all(x in prohibited for x in ('aprobar','VALIDATED','APPROVED','PRODUCTION_READY','PRODUCTION_AUTHORIZED')))
    need('protocol_nine_steps',len(re.findall(r'^\d+\.',s.get(8,''),re.M))>=9)
    result_block=s.get(9,'')
    need('allowed_results_exact',all(x in result_block for x in ('READY_FOR_JUDGE','RETURN_TO_WORKER','BLOCKED','no puede producir `PASS_WITH_EVIDENCE`')))
    judge_tokens={x for x in tokens(s.get(10,'')) if x.startswith('J')}
    need('judges_exact',set(c['judges'])==judge_tokens)
    need('independence',all(x in s.get(10,'') for x in ('worker_identity != judge_identity','worker_must_not_modify_judge_contract = true','worker_must_not_select_own_pass_result = true')))
    need('quality_ids_exact',all(f'`{x} = 0`' in s.get(11,'') for x in c['quality']))
    need('retry_limit_two','retry_limit = 2' in s.get(12,''))
    block=s.get(12,'').lower()
    need('blocking_conditions',all(x in block for x in ('fuente','scope','contradicción','output previo','reparación')))
    handoff=s.get(13,'')
    need('handoff_fields',all(x in handoff for x in ('worker_profile','agent_ref','target_ref','source_snapshot_sha256','written_sections','assertion_results','pending_decisions','evidence_refs','retry_count','next_judge')))
    need('benchmark_repositories',all(x in s.get(14,'') for x in ('Significant-Gravitas/AutoGPT','microsoft/vscode','freeCodeCamp/freeCodeCamp')))
    need('no_temporal_star_counts',not re.search(r'~?\d{3,}[,.]?\d*\s+estrellas',s.get(14,''),re.I))
    need('no_self_pass','El perfil no puede producir `PASS_WITH_EVIDENCE`' in s.get(9,''))
    return sorted(set(findings))

def mutate(code,text,case):
    c=CONFIG[code]
    if case=='remove_approve_prohibition':
        return text.replace('- `aprobar resultados`','',1).replace('- `aprobar el resultado`','',1)
    if case=='allow_self_pass':
        return text.replace('READY_FOR_JUDGE\nRETURN_TO_WORKER\nBLOCKED','READY_FOR_JUDGE\nRETURN_TO_WORKER\nBLOCKED\nPASS_WITH_EVIDENCE',1).replace('El perfil no puede producir `PASS_WITH_EVIDENCE`; ese estado pertenece al juez.','',1)
    if case=='wrong_judge':
        return text.replace(c['judges'][0],'J99_WRONG_JUDGE',1)
    if case=='write_out_of_scope':
        return text.replace('## 7. Acciones prohibidas','- `main`\n\n## 7. Acciones prohibidas',1)
    raise ValueError(case)

def run(code,mode,report_dir):
    c=CONFIG[code]; path=SKILL/c['path']; raw=path.read_bytes(); text=raw.decode(); base=evaluate(code,text)
    if mode=='static':
        checks={'profile_contract':not base,'sha256_present':len(hashlib.sha256(raw).hexdigest())==64,'agent_exists':(SKILL/c['agent']).is_file(),'judges_declared':all(j in text for j in c['judges'])}
        score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2)
        out={'artifact_code':code,'relative_path':c['path'],'sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'contract_findings':base,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':base+[k for k,v in checks.items() if not v]}
        report_dir.mkdir(parents=True,exist_ok=True)
        (report_dir/f'{code}.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(out,ensure_ascii=False,sort_keys=True))
        return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
    cases=[{'case':'positive','expected':'PASS_WITH_EVIDENCE','findings':base}]
    for name in ('remove_approve_prohibition','allow_self_pass','wrong_judge','write_out_of_scope'):
        fs=evaluate(code,mutate(code,text,name)); cases.append({'case':name,'expected':'RETURN_TO_WORKER','findings':fs})
    for row in cases:
        row['actual']='PASS_WITH_EVIDENCE' if not row['findings'] else 'RETURN_TO_WORKER'; row['passed']=row['actual']==row['expected']
    out={'artifact':code,'passed':all(x['passed'] for x in cases),'cases':cases,'sha256':hashlib.sha256(raw).hexdigest()}
    print(json.dumps(out,ensure_ascii=False,sort_keys=True))
    return 0 if out['passed'] else 1

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--artifact',choices=CONFIG,required=True); parser.add_argument('--mode',choices=('static','runtime'),required=True); parser.add_argument('--report-dir',type=Path,default=ROOT/'audit-results'); args=parser.parse_args()
    return run(args.artifact,args.mode,args.report_dir)
if __name__=='__main__': raise SystemExit(main())
