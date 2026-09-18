-- AUD-0 QUALITY BASELINE V1
-- Read-only. Bound to freeze:
-- main=dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- schema_fp=56c2af889d3f6a4781b1ac74ba7da5bb
--
-- Purpose: map user objectives to existing LF canon, measurable controls and thresholds.
-- v1 correction: prevention-rule keys are schema-first (regla_codigo/regla/justificacion).
with criteria(code,objective,match_regex,control_method,threshold) as (
  values
  ('Q01','Operar sin errores','(error|failure|fail|defect|incidenc)','COUNT reproducible OPEN High/Critical findings on critical path','0 un-dispositioned reproducible High/Critical findings'),
  ('Q02','Sin dependencias frágiles','(dependenc|predecess|currentness|binding|lineage)','Graph edges missing owner/contract/currentness','0 fragile material dependencies on operational paths'),
  ('Q03','Sin bloqueos genéricos','(blocker|blocking|first.bad.hop|causal)','Blockers without causal code + owner + next action','0 generic blockers'),
  ('Q04','Sin datos en duro','(hardcod|literal|configur|registry)','Static/config scanner for material governed literals','0 unauthorized material hardcodes'),
  ('Q05','Componentes transversales','(transversal|shared|reuse|duplic|capabilit)','Duplicate responsibility / local reimplementation scan','0 active duplicate engines for same governed responsibility'),
  ('Q06','Un proceso estándar','(lifecycle|operation contract|standard|metamodel|policy)','Operation lifecycle/contract/evidence/readback conformance','100% operational paths covered or explicit governed exception'),
  ('Q07','Pruebas robustas','(claim|assurance|precondition|adversarial|negative.test|coverage)','Claim -> obligation -> predecessor/subprocess -> positive/negative/adversarial -> evidence','100% Critical/High applicable claims covered'),
  ('Q08','SHA estables y currentness causal','(sha|currentness|exact.head|version|digest)','Count invalidations not caused by declared material dependency','0 non-causal invalidations'),
  ('Q09','Arquitectura correcta','(architecture|owner|authority|layer|bypass)','Architecture conformance scanner + authority graph','0 Critical/High architecture violations'),
  ('Q10','Determinístico separado de semántico','(determin|semantic|judge|resolver)','Machine-checkable rules delegated to LLM / semantic logic embedded in deterministic layer','0 avoidable cross-layer violations'),
  ('Q11','Sin acumulación de contexto','(context|token|budget|jit|payload)','Context budget and JIT retrieval controls','soft <=1500 and hard <=3000 estimated tokens unless explicit governed exception'),
  ('Q12','Transporte liviano','(transport|payload|compact|rehydrat|cache)','Payload bytes/token overhead and repeated transport','No full-pack transport where compact/JIT contract exists'),
  ('Q13','Consultas eficientes e índices correctos','(query|sql|index|performance|broad.query|schema.first)','Query-shaping + index/selectivity + scan/latency analysis','0 unjustified broad queries on critical path; index need decided from measured selectivity/cardinality')
),
canon as (
  select 'BEST_PRACTICE' source_type,
         coalesce(categoria,'') source_category,
         titulo source_key,
         coalesce(practica,'')||' '||coalesce(evidencia,'') source_text
  from public.lf_best_practices
  union all
  select 'PREVENTION_RULE',
         coalesce(categoria,''),
         regla_codigo,
         coalesce(regla,'')||' '||coalesce(justificacion,'')
  from public.lf_prevention_rules
  where activa
  union all
  select 'DECISION',coalesce(estado,''),coalesce(titulo,adr),coalesce(decision,'')||' '||coalesce(razon,'')||' '||coalesce(impacto,'')
  from public.lf_decision_log
  where lower(coalesce(estado,'')) not in ('superseded','archived')
  union all
  select 'POLICY',coalesce(status,''),policy_code,coalesce(policy_payload::text,'')
  from public.lf_policy_versions
  where status='ACTIVE'
),
matched as (
  select c.code,
         count(*) filter (where lower(canon.source_key||' '||canon.source_text) ~ c.match_regex) as canon_matches,
         jsonb_agg(
           jsonb_build_object('source_type',canon.source_type,'source_category',canon.source_category,'source_key',canon.source_key)
           order by canon.source_type,canon.source_key
         ) filter (where lower(canon.source_key||' '||canon.source_text) ~ c.match_regex) as refs
  from criteria c
  cross join canon
  group by c.code
)
select c.code,c.objective,c.control_method,c.threshold,
       coalesce(m.canon_matches,0) as canon_match_count,
       case when coalesce(m.canon_matches,0)=0 then 'CANON_GAP'
            when coalesce(m.canon_matches,0)<3 then 'PARTIAL_CANON'
            else 'CANON_PRESENT_REQUIRES_CONFORMANCE_AUDIT' end as baseline_gap_state,
       coalesce(m.refs,'[]'::jsonb) as evidence_refs
from criteria c
left join matched m using(code)
order by c.code;
