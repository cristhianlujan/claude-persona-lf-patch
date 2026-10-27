#!/usr/bin/env python3
"""PE10A_CT02 (parte 1): paridad de NOMBRES de argumentos entre llamadores y firmas SQL congeladas.
Lee frozen_inventory_v1.json (firmas) y extrae de los llamadores del repo los literales rpc("fn", {p_...}).
Salida: JSON con veredicto por llamada. --mutate-param cambia un nombre en memoria (negativo)."""
import json,re,sys,pathlib
root=pathlib.Path(__file__).resolve().parents[3]
inv=json.load(open(root/'docs/profile_updater/pe10a_ct01_falsifier/frozen_inventory_v1.json'))
sig={s['fn']:[a.split()[0] for a in s['args'].split(', ')] for s in inv['surfaces']}
mut='--mutate-param' in sys.argv
callers=[p for p in ['supabase/functions/run-creacion-perfil-lf/index.ts','supabase/functions/lf-profile-creator-governance-caller-v1/index.ts','supabase/functions/lf-profiles-governance-caller-v1/index.ts']]
pat=re.compile(r'rpc\(\s*"([a-z0-9_]+)"\s*,\s*\{(.*?)\}\s*\)',re.S)
res=[]
for c in callers:
    f=root/c
    if not f.exists(): continue
    t=f.read_text()
    for m in pat.finditer(t):
        fn=m.group(1)
        if fn not in sig: continue
        keys=re.findall(r'\b(p_[a-z0-9_]+)\s*:',m.group(2))
        if mut and fn=='lf_profile_update_begin_v1': keys=[k.replace('p_target_code','p_target_cod') for k in keys]
        exp=sig[fn]
        res.append({'caller':c,'fn':fn,'line':t[:m.start()].count('\n')+1,
          'missing':[k for k in exp if k not in keys],'unknown':[k for k in keys if k not in exp],
          'verdict':'PASS' if sorted(keys)==sorted(exp) else 'FAIL_ARG_NAMES'})
print(json.dumps({'checked':len(res),'results':res},indent=1))
sys.exit(0 if res and all(r['verdict']=='PASS' for r in res) else 1)
