#!/usr/bin/env bash
# Pruebas locales (replica PG16) de la migracion que corrige y cierra PE10_C7 (requiere aplicar antes la de C6).
H=/home/pgtest; R=/home/claude/claude-persona-lf-patch; T=$R/docs/profile_updater/pe10_c6c7_tests
M6=$R/supabase/migrations/20261028030000_lf_pe10_c6_close_v1.sql; N6=20261028030000_lf_pe10_c6_close_v1
M=$R/supabase/migrations/20261028031000_lf_pe10_c7_candidate_contract_close_v1.sql; N=20261028031000_lf_pe10_c7_candidate_contract_close_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"; PL=programacion.engineering_plan_units
n=0;f=0
fresh(){ $P -d postgres -c "drop database if exists t_c7" -c "create database t_c7 template t_dep" >/dev/null 2>&1; python3 -B $T/build_fixture.py >/dev/null; $P -d t_c7 -v ON_ERROR_STOP=1 -f $T/replica_pe10_c6_c7_fixture.sql >/dev/null 2>&1 || echo "FALLO fixture"
  $P -d t_c7 -c "insert into public.lf_operation_execution values ('EXEC-C6','ACTUALIZACION_DB_LF','MIGRATION','$N6','IN_PROGRESS')" >/dev/null
  $P -d t_c7 -v ON_ERROR_STOP=1 -f $M6 2>&1 | grep -q ERROR && echo "FALLO migracion C6"
  $P -d t_c7 -c "update public.lf_operation_execution set status='COMPLETED' where execution_id='EXEC-C6'" >/dev/null; }
train(){ $P -d t_c7 -c "insert into public.lf_operation_execution values ('EXEC-C7','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
run(){ $P -d t_c7 -v ON_ERROR_STOP=1 -f $M 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
chk(){ r=$($P -d t_c7 -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
experr(){ r=$(run); n=$((n+1)); case "$r" in $2*) echo "PASS  $1 -> $r";; *) f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$2*]";; esac; }
CPS="select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code="
SPECHASH="select md5(unit_metadata::text) from $PL where unit_code='PE10'"
NOCHANGE="PASS_SPEC_UNCHANGED"
echo "== 1 sin Train"; fresh; S0=$($P -d t_c7 -c "$SPECHASH"); experr 1 PE10_C7_CLOSE_TRAIN_TRANSPORT_REQUIRED; chk "1 C7 sigue PENDING" "${CPS}'PE10_C7'" PENDING
echo "== 2 camino feliz"; fresh; train
REV0=$($P -d t_c7 -c "select public.lf_operation_revision_sha256_v1('ACTUALIZACION_PERFIL_LF')"); OTH0=$($P -d t_c7 -c "select md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code)) from $PL where unit_code<>'PE10'")
r=$(run); echo "migracion: ${r:-OK}"
chk "2 C7 DONE" "${CPS}'PE10_C7'" DONE
chk "2 C6 sigue DONE" "${CPS}'PE10_C6'" DONE
chk "2 contrato v0.2 en CANDIDATO_READ_ONLY" "select status from public.lf_operation_contracts where contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2'" CANDIDATO_READ_ONLY
chk "2 contrato v0.2 copia las obligaciones del v0.1" "select (a.required_before_write=b.required_before_write and a.blocked=b.blocked and a.required_after_write=b.required_after_write and a.allowed-'v02_candidate'-'activation_authorized'=b.allowed and (a.allowed->>'activation_authorized')='false') from public.lf_operation_contracts a, public.lf_operation_contracts b where a.contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2' and b.contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1'" t
chk "2 solo 1 contrato ACTIVE_ENFORCEMENT (begin_v1 intacto)" "select count(*) from public.lf_operation_contracts where operation_code='ACTUALIZACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT'" 1
chk "2 revision de la operacion sin cambio" "select (public.lf_operation_revision_sha256_v1('ACTUALIZACION_PERFIL_LF')='$REV0')" t
chk "2 registro sigue v0.1" "select version from public.lf_operation_registry where operation_code='ACTUALIZACION_PERFIL_LF'" v0.1
chk "2 pass_when registry_v02 = 0" "select unit_metadata#>>'{action_specs_v1,PE10_C7,assertion_contract,pass_when,registry_v02}' from $PL where unit_code='PE10'" 0
chk "2 validador catalogo expected = 0" "select unit_metadata#>>'{action_specs_v1,PE10_C7,validator_contract,validation_input,assertions,0,expected}' from $PL where unit_code='PE10'" 0
chk "2 ya no quedan consultas con target_operation_version" "select unit_metadata::text like '%target_operation_version%' from $PL where unit_code='PE10'" f
chk "2 consultas de C7 identicas en las 3 copias" "select count(distinct q) from (select unit_metadata#>>'{action_specs_v1,PE10_C7,verification_queries,0}' q from $PL where unit_code='PE10' union all select unit_metadata#>>'{checkpoint_contracts,PE10_C7,validation_input,queries,0}' from $PL where unit_code='PE10' union all select unit_metadata#>>'{source_pack_v2,checkpoint_inputs,PE10_C7,inputs,queries,0}' from $PL where unit_code='PE10') z" 1
chk "2 la consulta persistida da 0/1/1/1" "select to_jsonb(t)::text from (select (select count(*)::int from public.lf_operation_registry where operation_code='ACTUALIZACION_PERFIL_LF' and version='v0.2') registry_v02,(select count(*)::int from public.lf_operation_contracts where operation_code='ACTUALIZACION_PERFIL_LF' and contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2' and status='CANDIDATO_READ_ONLY') contract_v02) t" '{"contract_v02": 1, "registry_v02": 0}'
chk "2 criterio de aceptacion actualizado" "select acceptance_criteria::text like '%PE10_C7: v0.2 contract as CANDIDATO_READ_ONLY%' from programacion.engineering_work_items w join $PL u on u.work_item_id=w.id where u.unit_code='PE10'" t
chk "2 otras unidades intactas" "select ('$OTH0'=md5(string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code))) from $PL where unit_code<>'PE10'" t
chk "2 politica candidata v1.4 no modificada" "select policy_sha from public.lf_policy_versions where policy_version='v1.4-evolved-routing-candidate'" 5ae6804ded17dea94a7ec2d8c4ebe588b1017222ab8d92b912bc8607996892b5
chk "2 fila EKB creada" "select count(*) from public.lf_error_knowledge where codigo='LF-PE10-C7-REGISTRY-V02-NEEDS-ACTIVATION-20261028-001'" 1
echo "== 3 reaplicar"; experr 3 PE10_C7_CLOSE_GATES_STATE_INVALID
echo "== 4 mutacion: C6 cerrado con OTRO sql candidato"; fresh; train
$P -d t_c7 -c "update programacion.engineering_work_updates set detail=replace(detail,'candidate_sql_sha256','candidate_sql_shaX') where summary='Checkpoint PE10_C6 -> DONE'" >/dev/null
S0=$($P -d t_c7 -c "$SPECHASH"); experr 4 PE10_C7_CLOSE_CANDIDATE_SQL_NOT_THE_ONE_TESTED_BY_C6; chk "4 atomico: especificacion intacta" "select ('$S0'=md5(unit_metadata::text)) from $PL where unit_code='PE10'" t
echo "== 5 mutacion: la politica candidata no coincide con el evento de C5"; fresh; train
$P -d t_c7 -c "update public.lf_policy_versions set policy_sha='deadbeef' where policy_version='v1.4-evolved-routing-candidate'" >/dev/null
S0=$($P -d t_c7 -c "$SPECHASH"); experr 5 PE10_C7_CLOSE_READBACK_FAILED
chk "5 atomico: especificacion intacta" "select ('$S0'=md5(unit_metadata::text)) from $PL where unit_code='PE10'" t
chk "5 atomico: sin contrato v0.2" "select count(*) from public.lf_operation_contracts where contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2'" 0
chk "5 atomico: C7 sigue PENDING" "${CPS}'PE10_C7'" PENDING
echo "== 6 mutacion: la especificacion ya cambio (una consulta distinta)"; fresh; train
$P -d t_c7 -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{checkpoint_contracts,PE10_C7,validation_input,queries,0}','\"select 1\"') where unit_code='PE10'" >/dev/null
experr 6 PE10_C7_CLOSE_SPEC_PRESTATE_DRIFT
echo "== 7 mutacion: registro ya en v0.2"; fresh; train
$P -d t_c7 -c "update public.lf_operation_registry set version='v0.2' where operation_code='ACTUALIZACION_PERFIL_LF'" >/dev/null
experr 7 PE10_C7_CLOSE_PRESTATE_INVALID
echo "== 8 mutacion: ya hay un segundo contrato activo"; fresh; train
$P -d t_c7 -c "insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,status) values ('ACTUALIZACION_PERFIL_LF','OTRO','x','ACTIVE_ENFORCEMENT')" >/dev/null
experr 8 PE10_C7_CLOSE_PRESTATE_INVALID
echo "== 8b ejecucion abierta heredada: se tolera y no se toca"; fresh; train
$P -d t_c7 -c "insert into public.lf_operation_execution values ('EXEC-OPEN','ACTUALIZACION_PERFIL_LF','PERFIL','x','IN_PROGRESS')" >/dev/null
r=$(run); n=$((n+1)); [ -z "$r" ] && echo "PASS  8b migracion OK con ejecucion abierta" || { f=$((f+1)); echo "FAIL  8b obtenido=[$r]"; }
chk "8b la ejecucion abierta sigue IN_PROGRESS" "select status from public.lf_operation_execution where execution_id='EXEC-OPEN'" IN_PROGRESS
chk "8b C7 DONE" "${CPS}'PE10_C7'" DONE
echo "== 9 mutacion: criterio de aceptacion ya distinto"; fresh; train
$P -d t_c7 -c "update programacion.engineering_work_items w set acceptance_criteria='[\"otro\"]'::jsonb from $PL u where u.work_item_id=w.id and u.unit_code='PE10'" >/dev/null
experr 9 PE10_C7_CLOSE_ACCEPTANCE_DRIFT
echo "== 10 mutacion: C6 todavia PENDING"; fresh; train
$P -d t_c7 -c "update programacion.engineering_work_checkpoints c set status='PENDING' from $PL u where u.work_item_id=c.work_item_id and u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" >/dev/null
experr 10 PE10_C7_CLOSE_GATES_STATE_INVALID
echo; echo "TOTAL $n pruebas, $f fallas"
