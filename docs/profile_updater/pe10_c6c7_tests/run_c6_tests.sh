#!/usr/bin/env bash
# Pruebas locales (replica PG16) de la migracion que cierra PE10_C6.
H=/home/pgtest; R=/home/claude/claude-persona-lf-patch; T=$R/docs/profile_updater/pe10_c6c7_tests
M=$R/supabase/migrations/20261028030000_lf_pe10_c6_close_v1.sql; N=20261028030000_lf_pe10_c6_close_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"; PL=programacion.engineering_plan_units; PLAN=PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1
n=0;f=0
fresh(){ $P -d postgres -c "drop database if exists t_c6" -c "create database t_c6 template t_dep" >/dev/null 2>&1; python3 $T/build_fixture.py >/dev/null; $P -d t_c6 -v ON_ERROR_STOP=1 -f $T/replica_pe10_c6_c7_fixture.sql >/dev/null 2>&1 || echo "FALLO fixture"; }
train(){ $P -d t_c6 -c "insert into public.lf_operation_execution values ('EXEC-C6','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
run(){ $P -d t_c6 -v ON_ERROR_STOP=1 -f $M 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
chk(){ r=$($P -d t_c6 -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
experr(){ r=$(run); n=$((n+1)); case "$r" in $2*) echo "PASS  $1 -> $r";; *) f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$2*]";; esac; }
CPS="select string_agg(c.checkpoint_code||':'||c.status,',' order by c.checkpoint_code) from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10'"
echo "== 1 sin Train"; fresh; experr 1 PE10_C6_CLOSE_TRAIN_TRANSPORT_REQUIRED; chk "1 C6 sigue PENDING" "select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" PENDING
echo "== 2 camino feliz"; fresh; train
CK0=$($P -d t_c6 -c "$CPS"); REV0=$($P -d t_c6 -c "select public.lf_operation_revision_sha256_v1('ACTUALIZACION_PERFIL_LF')")
r=$(run); echo "migracion: ${r:-OK}"
chk "2 C6 DONE" "select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" DONE
chk "2 C7 sigue PENDING" "select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C7'" PENDING
chk "2 recibo de asercion guardado" "select assertion_receipt_sha256 is not null from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" t
chk "2 el detalle observado queda legible (positivo+negativo+rollback)" "select (detail like '%\"positive_gate_tested\": true%' and detail like '%\"negative_gate_tested\": true%' and detail like '%\"transaction_rolled_back\": true%' and detail like '%candidate_sql_sha256%') from programacion.engineering_work_updates w join $PL u on u.work_item_id=w.work_item_id where u.unit_code='PE10' and w.summary='Checkpoint PE10_C6 -> DONE'" t
chk "2 sin contrato v0.2 persistido" "select count(*) from public.lf_operation_contracts where contract_code<>'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1'" 0
chk "2 registro sigue v0.1" "select version from public.lf_operation_registry where operation_code='ACTUALIZACION_PERFIL_LF'" v0.1
chk "2 revision de la operacion sin cambio" "select (public.lf_operation_revision_sha256_v1('ACTUALIZACION_PERFIL_LF')='$REV0')" t
chk "2 otros checkpoints intactos" "select (select string_agg(c.checkpoint_code||':'||c.status,',' order by c.checkpoint_code) from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code<>'PE10_C6')=replace('$CK0',',PE10_C6:PENDING','')" t
echo "== 3 reaplicar"; experr 3 PE10_C6_CLOSE_NOT_PENDING:DONE
echo "== 4 mutacion: ya existe un contrato v0.2"; fresh; train
$P -d t_c6 -c "insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,status) values ('ACTUALIZACION_PERFIL_LF','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2','x','CANDIDATO_READ_ONLY')" >/dev/null
experr 4 PE10_C6_CLOSE_PRESTATE_INVALID; chk "4 C6 sigue PENDING (atomico)" "select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" PENDING
echo "== 5 mutacion: el candidato DEJA de ser invisible (el SQL candidato lo inserta como ACTIVE_ENFORCEMENT)"; fresh; train
sed "s/'CANDIDATO_READ_ONLY','EXEC-PE10-C7-CANDIDATE/'ACTIVE_ENFORCEMENT','EXEC-PE10-C7-CANDIDATE/" $M > /tmp/c6_mut5.sql
r=$($P -d t_c6 -v ON_ERROR_STOP=1 -f /tmp/c6_mut5.sql 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1); n=$((n+1)); case "$r" in PE10_C6_CLOSE_DRYRUN_FAILED:positive=f*) echo "PASS  5 -> $r";; *) f=$((f+1)); echo "FAIL  5 obtenido=[$r]";; esac
chk "5 C6 sigue PENDING (atomico)" "select status from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10' and c.checkpoint_code='PE10_C6'" PENDING
echo "== 6 mutacion: registro ya en v0.2"; fresh; train
$P -d t_c6 -c "update public.lf_operation_registry set version='v0.2' where operation_code='ACTUALIZACION_PERFIL_LF'" >/dev/null
experr 6 PE10_C6_CLOSE_PRESTATE_INVALID
echo "== 7 mutacion: C5 no esta DONE"; fresh; train
$P -d t_c6 -c "update programacion.engineering_work_checkpoints c set status='PENDING' from $PL u where u.work_item_id=c.work_item_id and u.unit_code='PE10' and c.checkpoint_code='PE10_C5'" >/dev/null
experr 7 PE10_C6_CLOSE_GATES_STATE_INVALID
echo "== 8 mutacion: hay una ejecucion abierta de la operacion"; fresh; train
$P -d t_c6 -c "insert into public.lf_operation_execution values ('EXEC-OPEN','ACTUALIZACION_PERFIL_LF','PERFIL','x','IN_PROGRESS')" >/dev/null
experr 8 PE10_C6_CLOSE_PRESTATE_INVALID
echo; echo "TOTAL $n pruebas, $f fallas"
