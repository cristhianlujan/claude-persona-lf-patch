#!/usr/bin/env python3
"""One trusted-main invocation: SUNAT batches 2..479 sequentially into existing SALY.
Reuses the approved snapshot reader, deployed native atomic writer and existing operation.
No new tables, alternate database, direct hallazgos INSERT, upload or parallel workers.
Each batch commits and verifies before the next. On failure stops; rerun resumes prefix.
"""
import json
import re
import sys

from sunat_first_governed_batch_v22 import (
    EXEC, OWNER, SOURCE, expected, request_for, psql, sql_literal,
)
from sunat_verified_delivery_v1 import verified_candidate_payloads
from sunat_batch_plan_v1 import sha, canonical


def database_prefix(exact):
    # Read-only preflight from the existing SALY plan, not a new runtime state store.
    qexec, qsrc = sql_literal(EXEC), sql_literal(SOURCE)
    sql=f"""WITH plan AS (
 SELECT (b.filtros->>'ordinal')::int ord, b.estado,
        (b.filtros->>'rows')::int rows
 FROM saly.ventas_discovery_plan_batches b
 JOIN saly.ventas_discovery_runs r ON b.run_id=r.id
 WHERE r.run_ref={qexec} AND b.source_id={qsrc}
), stat AS (
 SELECT count(*)::int total, count(*) FILTER (WHERE estado='FOUND')::int found,
        coalesce(sum(rows) FILTER (WHERE estado='FOUND'),0)::int expected_done,
        count(*) FILTER (WHERE estado NOT IN ('FOUND','NOT_RUN'))::int unusual FROM plan
)
SELECT jsonb_build_object(
 'total',s.total,'found',s.found,'expected_done',s.expected_done,
 'prefix_ok',NOT EXISTS(SELECT 1 FROM plan p
   WHERE (p.ord<=s.found AND p.estado<>'FOUND') OR
         (p.ord>s.found AND p.estado<>'NOT_RUN')),
 'unusual',s.unusual,
 'enabled',(SELECT config_value::jsonb->'enabled'='true'::jsonb
   FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
   AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
 'pilot_scope',(SELECT config_value::jsonb->>'pilot_scope'
   FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
   AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
 'policy_manifest',(SELECT config_value::jsonb->>'manifest_digest_sha256'
   FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
   AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
 'policy_snapshots',(SELECT config_value::jsonb->'snapshot_sha256'
   FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
   AND config_key='SUNAT_POLICY_V1' ORDER BY valid_from DESC LIMIT 1),
 'source_enabled',(SELECT habilitada AND persist_business_data
   FROM saly.ventas_discovery_catalogo WHERE source_id={qsrc}),
 'run_manifest',(SELECT plan_hash FROM saly.ventas_discovery_runs
   WHERE run_ref={qexec}),
 'operation_state',(SELECT status FROM public.lf_operation_execution
   WHERE execution_id={qexec}),
 'ingestas',(SELECT count(*) FROM saly.ventas_discovery_ingestas
   WHERE source_id={qsrc}),
 'reported',(SELECT coalesce(sum(filas_reportadas),0)
   FROM saly.ventas_discovery_ingestas WHERE source_id={qsrc}),
 'companies',(SELECT count(*) FROM saly.ventas_hallazgos h
   JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
   WHERE i.source_id={qsrc})
)::text FROM stat s;"""
    data=psql(sql,timeout=60)
    checks={
        'plan':data.get('total')==exact['batches']==479,
        'prefix':data.get('prefix_ok') is True and data.get('unusual')==0,
        'count':type(data.get('found')) is int and 1<=data['found']<=479,
        'policy':data.get('enabled') is True and data.get('pilot_scope')=='SEQUENTIAL_ALL_REMAINING_479',
        'binding':data.get('policy_manifest')==data.get('run_manifest')==exact['manifest_digest_sha256']
                 and data.get('policy_snapshots')==exact['source_sha256'],
        'source':data.get('source_enabled') is True,
        'operation':data.get('operation_state')=='IN_PROGRESS',
        'rows':data.get('expected_done')==data.get('reported')==data.get('companies'),
        'ingestas':data.get('ingestas')==data.get('found'),
    }
    if not all(checks.values()):
        raise ValueError('SEQUENTIAL_PREFLIGHT_REJECTED')
    return data['found'], data['expected_done']


def build_one_batch_sql(entry,payload,ordinal,total_rows):
    if entry.get('ordinal')!=ordinal or type(ordinal) is not int or ordinal<2 or ordinal>479:
        raise ValueError('SEQUENTIAL_ORDINAL')
    if type(payload) is not bytes or sha(payload)!=entry['capture_sha256'] or len(payload)!=entry['bytes']:
        raise ValueError('SEQUENTIAL_PAYLOAD_HASH')
    if not (type(total_rows) is int and 1000<total_rows<=478657):
        raise ValueError('SEQUENTIAL_TOTAL')
    txt=payload.decode('utf-8',errors='strict')
    if '$saly_sequential_v25$' in txt:
        raise ValueError('SEQUENTIAL_DELIMITER')
    qexec,qowner,qsource,qbatch,qhash=map(sql_literal,(EXEC,OWNER,SOURCE,entry['batch_key'],entry['capture_sha256']))
    qpayload=sql_literal(txt)
    expected_rows=entry['rows']
    return f"""BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='240s';
DO $saly_sequential_v25$
DECLARE v_lease jsonb; v_receipt jsonb; v_found int; v_count int; v_sum bigint;
BEGIN
 -- One global sequence per existing SUNAT run; NEVER dispatch a parallel lot.
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 SELECT count(*) INTO v_found FROM saly.ventas_discovery_plan_batches b
 JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
 WHERE r.run_ref={qexec} AND b.source_id={qsource} AND b.estado='FOUND';
 IF v_found<>{ordinal-1} OR EXISTS(
   SELECT 1 FROM saly.ventas_discovery_plan_batches b
   JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
   WHERE r.run_ref={qexec} AND b.source_id={qsource}
   AND ((b.filtros->>'ordinal')::int<{ordinal} AND b.estado<>'FOUND'
     OR (b.filtros->>'ordinal')::int={ordinal} AND b.estado<>'NOT_RUN')
 ) THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_OUT_OF_ORDER'; END IF;
 v_lease:=public.fn_lf_operation_acquire_lease_v1({qexec},{qowner},3600,{qexec});
 IF v_lease->>'result' IS DISTINCT FROM 'LEASE_ACQUIRED'
 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_LEASE'; END IF;
 v_receipt:=saly.ventas_sunat_batch_execute_v1(
     {qexec},{qowner},(v_lease->>'lease_fence')::bigint,{qbatch},{qpayload});
 IF v_receipt->>'batch_key' IS DISTINCT FROM {qbatch}
 OR v_receipt->>'capture_sha256' IS DISTINCT FROM {qhash}
 OR (v_receipt->>'rows')::int<>{expected_rows}
 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_RECEIPT'; END IF;
 SELECT count(*),coalesce(sum(i.filas_reportadas),0)
 INTO v_count,v_sum FROM saly.ventas_discovery_ingestas i
 WHERE i.source_id={qsource};
 IF v_count<>{ordinal} OR v_sum<>{total_rows}
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
    JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
    WHERE r.run_ref={qexec} AND b.source_id={qsource} AND b.estado='FOUND')<>{ordinal}
 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_READBACK'; END IF;
END $saly_sequential_v25$;
SELECT jsonb_build_object('ordinal',{ordinal},'ingestas',
 (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id={qsource}),
 'rows',(SELECT coalesce(sum(filas_reportadas),0) FROM saly.ventas_discovery_ingestas
  WHERE source_id={qsource}))::text;
COMMIT;"""


def run():
    exact, prior = expected()
    completed, total=database_prefix(exact)
    print('SUNAT_SEQUENCE_START '+json.dumps(dict(done=completed,total_batches=exact['batches'],
             reported_rows=total,remaining=exact['batches']-completed),sort_keys=True),flush=True)
    if completed==exact['batches']:
        if total!=exact['rows']:
            raise ValueError('SEQUENTIAL_TERMINAL_MISMATCH')
        print('SUNAT_SEQUENCE_COMPLETE '+json.dumps(dict(batches=completed,companies=total,
             db_write_confirmed=True),sort_keys=True),flush=True)
        return
    # Single pinned read of both official archives, full QA and staging only once.
    with verified_candidate_payloads(request_for(prior),expected_manifest=exact) as (qa,stream):
        entries=qa['batch_plan']['plan']
        if len(entries)!=479 or sha(canonical(entries))!=exact['manifest_digest_sha256']:
            raise ValueError('SEQUENTIAL_PLAN_DRIFT')
        # Prefix already committed in SALY. Skip without writing or duplicating it.
        for item,payload in stream:
            ordinal=item['ordinal']
            if ordinal<=completed:
                continue
            if ordinal!=completed+1:
                raise ValueError('SEQUENTIAL_SKIP_OR_REORDER')
            planned=total+item['rows']
            receipt=psql(build_one_batch_sql(item,payload,ordinal,planned),timeout=300)
            if (receipt.get('ordinal'),receipt.get('ingestas'),receipt.get('rows')) != (ordinal,ordinal,planned):
                raise ValueError('SEQUENTIAL_READBACK_MISMATCH')
            completed,total=ordinal,planned
            print('SUNAT_SEQUENCE_PROGRESS '+json.dumps(dict(batch=ordinal,total_batches=479,
                  rows_registered=total),sort_keys=True),flush=True)
    if completed!=479 or total!=exact['rows']:
        raise ValueError('SEQUENTIAL_INCOMPLETE')
    final_done,final_rows=database_prefix(exact)
    if (final_done,final_rows)!=(479,478657):
        raise ValueError('SEQUENTIAL_FINAL_DB_MISMATCH')
    print('SUNAT_SEQUENCE_COMPLETE '+json.dumps(dict(batches=final_done,companies=final_rows,
         db_write_confirmed=True),sort_keys=True),flush=True)


if __name__=='__main__':
    try:
        run()
    except Exception as exc:
        reason=str(exc) if type(exc) is ValueError and re.fullmatch('[A-Z_]+',str(exc)) else type(exc).__name__
        print('SUNAT_SEQUENCE_BLOCKED '+reason,flush=True)
        raise SystemExit(1)
