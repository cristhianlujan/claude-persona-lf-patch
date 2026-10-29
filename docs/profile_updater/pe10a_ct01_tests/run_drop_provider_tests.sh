#!/usr/bin/env bash
# Pruebas locales (replica PG16) de la migracion que quita la exigencia de recibo del proveedor en lo pendiente.
H=/home/pgtest; R=/home/claude/claude-persona-lf-patch
M=$R/supabase/migrations/20261028020000_lf_pe10a_drop_provider_bound_requirement_v1.sql
N=20261028020000_lf_pe10a_drop_provider_bound_requirement_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"; PL=programacion.engineering_plan_units
n=0;f=0
fresh(){ $P -d postgres -c "drop database if exists t_dp" -c "create database t_dp template t_dep" >/dev/null 2>&1; }
train(){ $P -d t_dp -c "insert into public.lf_operation_execution values ('EXEC-P','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
run(){ $P -d t_dp -v ON_ERROR_STOP=1 -f $M 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
chk(){ r=$($P -d t_dp -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
experr(){ r=$(run); n=$((n+1)); case "$r" in $2*) echo "PASS  $1 -> $r";; *) f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$2*]";; esac; }
FLAGS="select count(*) from $PL u, jsonb_each(u.unit_metadata->'checkpoint_inputs') e where e.value->>'provider_receipt_required'='true'"
PB="select count(*) from $PL where unit_metadata::text ~* 'provider-bound'"
echo "== P1 sin Train"; fresh; experr P1 PE10A_DROP_PROVIDER_TRAIN_TRANSPORT_REQUIRED; chk "P1 nada cambio" "$FLAGS" 12
echo "== P2 camino feliz"; fresh; train
CK0=$($P -d t_dp -c "select md5(string_agg(checkpoint_code||status,',' order by checkpoint_code)) from programacion.engineering_work_checkpoints")
CT0=$($P -d t_dp -c "select md5(unit_metadata::text) from $PL where unit_code='PE10A_CONTRACTS'")
OT0=$($P -d t_dp -c "select md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code)) from $PL where unit_code not in ('PE10A_STRUCTURE','PE10A_READY')")
r=$(run); echo "migracion: ${r:-OK}"
chk "P2 flags en true" "$FLAGS" 0
chk "P2 flags ahora false (12)" "select count(*) from $PL u, jsonb_each(u.unit_metadata->'checkpoint_inputs') e where e.value->>'provider_receipt_required'='false'" 12
chk "P2 sin 'provider-bound' en PE10A_STRUCTURE/READY" "$PB" 0
chk "P2 texto nuevo ST10" "select unit_metadata#>>'{checkpoint_inputs,PE10A_ST10,pass_when}' like '%ChatGPT o Claude (chat)%' from $PL where unit_code='PE10A_STRUCTURE'" t
chk "P2 texto nuevo OP04" "select unit_metadata#>>'{action_specs_v1,PE10A_OP04,positive_test}' like 'E2E ejecutado en ChatGPT o Claude (chat) para tarea%' from $PL where unit_code='PE10A_READY'" t
chk "P2 checkpoints intactos" "select ('$CK0'=md5(string_agg(checkpoint_code||status,',' order by checkpoint_code))) from programacion.engineering_work_checkpoints" t
chk "P2 CONTRACTS (CT01) intacto" "select ('$CT0'=md5(unit_metadata::text)) from $PL where unit_code='PE10A_CONTRACTS'" t
chk "P2 otras unidades intactas" "select ('$OT0'=md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code))) from $PL where unit_code not in ('PE10A_STRUCTURE','PE10A_READY')" t
chk "P2 evidence_mode no se toco" "select count(*) from $PL u, jsonb_each(u.unit_metadata->'checkpoint_inputs') e where e.value->>'evidence_mode'='REAL_PROVIDER_BOUND_READBACK' and u.unit_code in ('PE10A_STRUCTURE','PE10A_READY')" "$($P -d t_dep -c "select count(*) from $PL u, jsonb_each(u.unit_metadata->'checkpoint_inputs') e where e.value->>'evidence_mode'='REAL_PROVIDER_BOUND_READBACK' and u.unit_code in ('PE10A_STRUCTURE','PE10A_READY')")"
echo "== P3 reaplicar"; experr P3 PE10A_DROP_PROVIDER_PRESTATE_TEXT_DRIFT
echo "== P4 mutacion: texto ST10 distinto"; fresh; train
$P -d t_dp -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10A_ST10,positive_test}','\"otro\"') where unit_code='PE10A_STRUCTURE'" >/dev/null
experr P4 PE10A_DROP_PROVIDER_PRESTATE_TEXT_DRIFT; chk "P4 atomico: flags siguen" "$FLAGS" 12
echo "== P5 mutacion: una flag ya false"; fresh; train
$P -d t_dp -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{checkpoint_inputs,PE10A_ST03,provider_receipt_required}','false') where unit_code='PE10A_STRUCTURE'" >/dev/null
experr P5 PE10A_DROP_PROVIDER_PRESTATE_FLAGS
echo; echo "TOTAL $n pruebas, $f fallas"
