#!/usr/bin/env bash
# Pruebas locales (replica PG16) de la migracion que quita la exigencia de recibo independiente en lo pendiente.
# La replica tiene 59 especificaciones pendientes (produccion 62): el esperado se reescribe en una copia.
H=/home/pgtest; R=/home/claude/claude-persona-lf-patch
M=$R/supabase/migrations/20261028010000_lf_pe10a_drop_independent_receipt_requirement_v1.sql
N=20261028010000_lf_pe10a_drop_independent_receipt_requirement_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"; PL=programacion.engineering_plan_units
OLD=BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT
n=0;f=0
fresh(){ $P -d postgres -c "drop database if exists t_di" -c "create database t_di template t_dep" >/dev/null 2>&1; ready; }
MR=$R/supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql; NR=20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1
ready(){ $P -d t_di -c "insert into public.lf_operation_execution values ('EXEC-R','ACTUALIZACION_DB_LF','MIGRATION','$NR','IN_PROGRESS')" >/dev/null; $P -d t_di -v ON_ERROR_STOP=1 -f $MR >/dev/null 2>&1 || echo "FALLO preparando CT01 READY"; }
train(){ $P -d t_di -c "insert into public.lf_operation_execution values ('EXEC-D','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
SPECS=$($P -d t_dep -c "select count(*) from $PL u, jsonb_each(u.unit_metadata->'action_specs_v1') s where u.unit_code like 'PE10A%' and s.key<>'PE10A_CT01' and s.value->>'status'='$OLD'")
sed "s/c_expect_specs constant int := 62/c_expect_specs constant int := $SPECS/" $M > /tmp/di_test.sql
run(){ $P -d t_di -v ON_ERROR_STOP=1 -f /tmp/di_test.sql 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
chk(){ r=$($P -d t_di -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
experr(){ r=$(run); n=$((n+1)); case "$r" in $2*) echo "PASS  $1 -> $r";; *) f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$2*]";; esac; }
CNT_OLD="select count(*) from $PL u, jsonb_each(u.unit_metadata->'action_specs_v1') s where u.unit_code like 'PE10A%' and s.key<>'PE10A_CT01' and s.value->>'status'='$OLD'"
CNT_NEW="select count(*) from $PL u, jsonb_each(u.unit_metadata->'action_specs_v1') s where u.unit_code like 'PE10A%' and s.key<>'PE10A_CT01' and s.value->>'status'='BLOCK_PENDING_IMPLEMENTATION'"
echo "== D1 sin Train"; fresh; experr "D1" PE10A_DROP_INDEP_TRAIN_TRANSPORT_REQUIRED; chk "D1 nada cambio" "$CNT_OLD" $SPECS
echo "== D2 camino feliz"; fresh; train
CK0=$($P -d t_di -c "select md5(string_agg(checkpoint_code||status,',' order by checkpoint_code)) from programacion.engineering_work_checkpoints")
CT0=$($P -d t_di -c "select md5((unit_metadata->'action_specs_v1'->'PE10A_CT01')::text) from $PL where unit_code='PE10A_CONTRACTS'")
OT0=$($P -d t_di -c "select md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code)) from $PL where unit_code not like 'PE10A%'")
r=$(run); echo "migracion: ${r:-OK}"
chk "D2 ninguna spec con el estado viejo" "$CNT_OLD" 0
chk "D2 specs con estado nuevo" "$CNT_NEW" $SPECS
chk "D2 CT01 intacto" "select ('$CT0'=md5((unit_metadata->'action_specs_v1'->'PE10A_CT01')::text)) from $PL where unit_code='PE10A_CONTRACTS'" t
chk "D2 checkpoints intactos" "select ('$CK0'=md5(string_agg(checkpoint_code||status,',' order by checkpoint_code))) from programacion.engineering_work_checkpoints" t
chk "D2 unidades no PE10A intactas" "select ('$OT0'=md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code))) from $PL where unit_code not like 'PE10A%'" t
chk "D2 work items sin 'qualified independent receipt'" "select count(*) from programacion.engineering_work_items where expected_result like '%qualified independent receipt%'" 0
chk "D2 work items con el texto nuevo" "select count(*) from programacion.engineering_work_items where expected_result='Each atomic checkpoint has actual source/readback, positive and negative observation; never self-attest completion'" 8
chk "D2 pruebas de producto de jueces (JD04) intactas" "select (unit_metadata->'action_specs_v1'->'PE10A_JD04'->>'negative_test') like '%independiente%' from $PL where unit_code='PE10A_JUDGES'" t
echo "== D3 reaplicar"; experr "D3" PE10A_DROP_INDEP_PRESTATE_SPECS:0
echo "== D4 mutacion: una spec ya no tiene el estado viejo"; fresh; train
$P -d t_di -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10A_JD01,status}','\"OTRO\"') where unit_code='PE10A_JUDGES'" >/dev/null
experr "D4" PE10A_DROP_INDEP_PRESTATE_SPECS
echo "== D5 mutacion: un work item con texto distinto"; fresh; train
$P -d t_di -c "update programacion.engineering_work_items set expected_result='otro texto' where id=(select work_item_id from $PL where unit_code='PE10A_JUDGES')" >/dev/null
experr "D5" PE10A_DROP_INDEP_ITEMS_UPDATED
chk "D5 atomico: specs siguen con estado viejo" "$CNT_OLD" $SPECS
echo; echo "TOTAL $n pruebas, $f fallas"
