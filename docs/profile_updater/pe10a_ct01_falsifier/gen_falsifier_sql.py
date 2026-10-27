#!/usr/bin/env python3
"""Genera SQL de solo lectura que compara frozen_inventory_v1.json con pg_proc.
Uso: gen_falsifier_sql.py [--negatives]   (sale 0; el veredicto lo da la consulta)"""
import json,sys,os
d=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'frozen_inventory_v1.json')))
q=lambda s:"'"+s.replace("'","''")+"'"
vals=",\n".join(f"({q(s['fn'])},{q(s['args'])},{q(s['md5'])},{str(s['secdef']).lower()})" for s in d['surfaces'])
neg=""
if '--negatives' in sys.argv:
    neg=("\n union all select 'NEG_MD5_OBSOLETE',fn,args,'f'||substr(md5,2),secdef from frozen where fn='lf_profile_update_result_class_v1'"
         "\n union all select 'NEG_ARGS_OBSOLETE',fn,args||', p_extra text',md5,secdef from frozen where fn='lf_profile_update_effective_route_v1'"
         "\n union all select 'NEG_OWNERLESS_NEW','lf_profile_update_ghost_v1','p_x text',md5,false from frozen where fn='lf_profile_update_result_class_v1'")
print(f"""with frozen(fn,args,md5,secdef) as (values
{vals}),
muts as (select 'POSITIVE' case_id,fn,args,md5,secdef from frozen{neg}),
live as (select p.proname fn,pg_get_function_identity_arguments(p.oid) args,md5(p.prosrc) md5,p.prosecdef secdef,p.prosrc
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')
select m.case_id,m.fn,
 case when l.fn is null then 'FAIL_MISSING_OR_OWNERLESS' when l.args<>m.args then 'FAIL_SIGNATURE_DRIFT'
      when l.md5<>m.md5 then 'FAIL_BODY_DRIFT' when l.secdef<>m.secdef then 'FAIL_SECDEF_DRIFT' else 'PASS' end verdict,
 (select string_agg(distinct c.fn,',') from live c where c.prosrc like '%'||m.fn||'%' and c.fn<>m.fn) mention_in
from muts m left join live l on l.fn=m.fn order by (m.case_id<>'POSITIVE'),m.fn;""")
