#!/usr/bin/env bash
# Pruebas locales (replica PG16) de la migracion de cierre de CT01. La replica usa funciones STUB para las 12
# superficies, por eso el md5 congelado se reescribe al md5 de los stubs en una copia de la migracion.
H=/home/pgtest; R=/home/claude/claude-persona-lf-patch
MR=$R/supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql
MC=$R/supabase/migrations/20261027230000_lf_pe10a_ct01_close_v1.sql
NR=20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1; NC=20261027230000_lf_pe10a_ct01_close_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"; PL=programacion.engineering_plan_units; CK=programacion.engineering_work_checkpoints
n=0;f=0
fresh(){ $P -d postgres -c "drop database if exists t_cl" -c "create database t_cl template t_dep" >/dev/null 2>&1
  $P -d t_cl -c "insert into public.lf_operation_execution values ('EXEC-R','ACTUALIZACION_DB_LF','MIGRATION','$NR','IN_PROGRESS')" >/dev/null
  $P -d t_cl -v ON_ERROR_STOP=1 -f $MR >/dev/null 2>&1 || echo "FALLO preparando READY"; }
train(){ $P -d t_cl -c "insert into public.lf_operation_execution values ('EXEC-C','ACTUALIZACION_DB_LF','MIGRATION','$NC','IN_PROGRESS')" >/dev/null; }
mkcopy(){ cp $MC /tmp/close_test.sql; $P -d t_cl -At -F'|' -c "select p.proname,md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%select ''stub:%'" | while IFS='|' read fn m; do
   python3 - "$fn" "$m" <<'PY'
import re,sys
fn,m=sys.argv[1:]
s=open('/tmp/close_test.sql').read()
s=re.sub(r"\('%s','([^']*)','[0-9a-f]{32}'"%fn, lambda x:"('%s','%s','%s'"%(fn,x.group(1),m), s)
open('/tmp/close_test.sql','w').write(s)
PY
 done; }
run(){ $P -d t_cl -v ON_ERROR_STOP=1 -f $1 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
chk(){ r=$($P -d t_cl -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
experr(){ r=$(run $2); n=$((n+1)); case "$r" in $3*) echo "PASS  $1 -> $r";; *) f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3*]";; esac; }
OTH="select string_agg(checkpoint_code||':'||status,',' order by checkpoint_code) from $CK c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10A_CONTRACTS' and checkpoint_code<>'PE10A_CT01'"

echo "== C1 sin ejecucion del Train"; fresh; mkcopy
experr "C1 sin Train" /tmp/close_test.sql PE10A_CT01_CLOSE_TRAIN_TRANSPORT_REQUIRED
chk "C1 CT01 sigue PENDING" "select status from $CK where checkpoint_code='PE10A_CT01'" PENDING

echo "== C2 camino feliz"; fresh; train; mkcopy; O0=$($P -d t_cl -c "$OTH")
r=$(run /tmp/close_test.sql); echo "migracion: ${r:-OK}"
chk "C2 CT01 DONE" "select status from $CK where checkpoint_code='PE10A_CT01'" DONE
chk "C2 recibo de asercion guardado con hash" "select (assertion_receipt_sha256 is not null and assertion_receipt->>'passed'='true') from $CK where checkpoint_code='PE10A_CT01'" t
chk "C2 evidence_ref apunta al recibo" "select evidence_ref like '%PE10A_CT01_RECIBO_INDEPENDIENTE_ACEPTADO_V1%' from $CK where checkpoint_code='PE10A_CT01'" t
chk "C2 solo CT01 cambio (CT02..CT07 PENDING)" "select ('$O0'=($OTH))" t
chk "C2 fila EKB creada" "select count(*) from public.lf_error_knowledge where codigo like 'LF-PE10A-ASSERTION-CONTRACT-PASSWHEN-NULL%'" 1

echo "== C3 reaplicar"; fresh; train; mkcopy; run /tmp/close_test.sql >/dev/null
experr "C3 segunda aplicacion" /tmp/close_test.sql PE10A_CT01_CLOSE_NOT_PENDING

echo "== C4 mutacion: cuerpo de una funcion UPDATER cambia"; fresh; train; mkcopy
$P -d t_cl -c "create or replace function public.lf_profile_update_result_class_v1(p_value jsonb) returns text language sql as \$f\$ select 'cambiado' \$f\$" >/dev/null
experr "C4 deriva de cuerpo" /tmp/close_test.sql PE10A_CT01_CLOSE_INVENTORY_DRIFT
chk "C4 CT01 sigue PENDING (atomico)" "select status from $CK where checkpoint_code='PE10A_CT01'" PENDING

echo "== C5 mutacion: falta una funcion UPDATER"; fresh; train; mkcopy
$P -d t_cl -c "drop function public.lf_profile_update_substantive_block_v1(text,text,jsonb,jsonb)" >/dev/null
experr "C5 funcion ausente" /tmp/close_test.sql PE10A_CT01_CLOSE_INVENTORY_DRIFT

echo "== C6 mutacion: aparece funcion fantasma (negativo ghost no detectable)"; fresh; train; mkcopy
$P -d t_cl -c "create function public.lf_profile_update_ghost_v1() returns int language sql as 'select 1'" >/dev/null
experr "C6 ghost existe" /tmp/close_test.sql PE10A_CT01_CLOSE_NEGATIVES_NOT_DETECTED

echo "== C7 otro checkpoint ya no PENDING"; fresh; train; mkcopy
$P -d t_cl -c "update $CK set status='DONE' where checkpoint_code='PE10A_CT02'" >/dev/null
experr "C7 CT02 DONE" /tmp/close_test.sql PE10A_CT01_CLOSE_OTHER_CHECKPOINTS_NOT_PENDING

echo "== C8 contrato sin pass_when"; fresh; train; mkcopy
$P -d t_cl -c "update $PL set unit_metadata=unit_metadata #- '{action_specs_v1,PE10A_CT01,assertion_contract,pass_when}' where unit_code='PE10A_CONTRACTS'" >/dev/null
experr "C8 pass_when ausente" /tmp/close_test.sql PE10A_CT01_CLOSE_CONTRACT_NOT_READY

echo "== C9 condicion del contrato no cubierta por observed"; fresh; train; mkcopy
$P -d t_cl -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10A_CT01,assertion_contract,pass_when,extra_condition}','true') where unit_code='PE10A_CONTRACTS'" >/dev/null
experr "C9 condicion extra" /tmp/close_test.sql ENGINEERING_ASSERTION_RESULT_FAILED
chk "C9 CT01 sigue PENDING y sin recibo" "select status||':'||(assertion_receipt is null) from $CK where checkpoint_code='PE10A_CT01'" "PENDING:true"
echo; echo "TOTAL $n pruebas, $f fallas"
