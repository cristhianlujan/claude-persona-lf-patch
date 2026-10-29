H=/home/pgtest; M=/home/claude/claude-persona-lf-patch/supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql
N=20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1; PL=programacion.engineering_plan_units
PLAN=PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"
fresh(){ $P -d postgres -c "drop database if exists t_ct" -c "create database t_ct template t_dep" >/dev/null 2>&1; }
train(){ $P -d t_ct -c "insert into public.lf_operation_execution values ('EXEC-C1','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
n=0;f=0
chk(){ r=$($P -d t_ct -c "$2" 2>&1); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 ($r)" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
run(){ $P -d t_ct -v ON_ERROR_STOP=1 -f $1 2>&1 | grep ERROR | sed 's/.*ERROR:  //' | head -1; }
experr(){ r=$(run $2); n=$((n+1)); [ "$r" = "$3" ] && echo "PASS  $1 -> $r" || { f=$((f+1)); echo "FAIL  $1 obtenido=[$r] esperado=[$3]"; }; }
SPECS="select string_agg(k||':'||md5((unit_metadata->'action_specs_v1'->k)::text),',' order by k) from $PL, jsonb_object_keys(unit_metadata->'action_specs_v1') k where unit_code='PE10A_CONTRACTS' and k<>'PE10A_CT01'"
CPS="select string_agg(checkpoint_code||':'||status,',' order by checkpoint_code) from programacion.engineering_work_checkpoints c join $PL u on u.work_item_id=c.work_item_id where u.unit_code='PE10A_CONTRACTS'"
AC="select (programacion.fn_engineering_action_spec_assertion_contract_v1(plan_code,unit_code,'PE10A_CT01',unit_metadata->'action_specs_v1'->'PE10A_CT01'))->>'status' from $PL where unit_code='PE10A_CONTRACTS'"
echo "== T1 sin Train"; fresh; experr "T1 sin ejecucion del Train" $M PE10A_CT01_ASSERTION_TRAIN_TRANSPORT_REQUIRED
chk "T1 nada cambio" "$AC" BLOCK_ACTION_SPEC_NOT_READY
echo "== T2 con Train"; fresh; train
S0=$($P -d t_ct -c "$SPECS"); C0=$($P -d t_ct -c "$CPS"); O0=$($P -d t_ct -c "select md5((unit_metadata - 'action_specs_v1')::text) from $PL where unit_code='PE10A_CONTRACTS'")
r=$(run $M); echo "migracion: ${r:-OK}"
chk "T2 contrato de asercion READY" "$AC" READY
chk "T2 modo EXPLICIT_PASS_WHEN_SUBSET" "select unit_metadata->'action_specs_v1'->'PE10A_CT01'->'assertion_contract'->>'mode' from $PL where unit_code='PE10A_CONTRACTS'" EXPLICIT_PASS_WHEN_SUBSET
chk "T2 pass_when con 6 condiciones" "select count(*) from $PL, jsonb_object_keys(unit_metadata->'action_specs_v1'->'PE10A_CT01'->'assertion_contract'->'pass_when') where unit_code='PE10A_CONTRACTS'" 6
chk "T2 independent_receipt_bound exigido" "select unit_metadata->'action_specs_v1'->'PE10A_CT01'->'assertion_contract'->'pass_when'->>'independent_receipt_bound' from $PL where unit_code='PE10A_CONTRACTS'" true
chk "T2 otras especificaciones (CT02..) idénticas" "select ('$S0'=($SPECS))" t
chk "T2 estados de checkpoints idénticos (CT01 sigue PENDING)" "select ('$C0'=($CPS))" t
chk "T2 resto del metadata (fuera de action_specs) idéntico" "select ('$O0'=md5((unit_metadata - 'action_specs_v1')::text)) from $PL where unit_code='PE10A_CONTRACTS'" t
chk "T2 CT01 spec: resto de claves conservadas (forbidden, negative_test)" "select (unit_metadata->'action_specs_v1'->'PE10A_CT01') ? 'forbidden' and (unit_metadata->'action_specs_v1'->'PE10A_CT01') ? 'negative_test' from $PL where unit_code='PE10A_CONTRACTS'" t
echo "== T3 reaplicar"; experr "T3 segunda aplicacion" $M PE10A_CT01_ASSERTION_PRESTATE_DRIFT_OR_ALREADY_APPLIED
echo "== T4 deriva de spec"; fresh; train
$P -d t_ct -c "update $PL set unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,PE10A_CT01,purpose}','\"x\"') where unit_code='PE10A_CONTRACTS'" >/dev/null
experr "T4 spec modificada antes" $M PE10A_CT01_ASSERTION_PRESTATE_DRIFT_OR_ALREADY_APPLIED
echo "== T5 checkpoint no PENDING"; fresh; train
$P -d t_ct -c "update programacion.engineering_work_checkpoints set status='DONE' where checkpoint_code='PE10A_CT01'" >/dev/null 2>&1
experr "T5 CT01 ya DONE" $M PE10A_CT01_ASSERTION_CHECKPOINT_NOT_PENDING
echo "== T6 mutacion: pass_when ausente debe fallar con el error exacto y revertir"; fresh; train
sed "s/'pass_when', jsonb_build_object(/'pass_when_x', jsonb_build_object(/" $M > /tmp/mut_ct.sql
cmp -s $M /tmp/mut_ct.sql && echo "FAIL T6 la mutacion no cambio el archivo"
experr "T6 mutacion rechazada" /tmp/mut_ct.sql PE10A_CT01_ASSERTION_POSTSTATE_CONTRACT_NOT_READY
chk "T6 spec de CT01 sin cambios tras fallo (atomico)" "select unit_metadata->'action_specs_v1'->'PE10A_CT01'->>'status' from $PL where unit_code='PE10A_CONTRACTS'" BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT
echo "== T7 alcance: solo CT01 cambia entre unidades"; fresh; train
U0=$($P -d t_ct -c "select string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code) from $PL where unit_code<>'PE10A_CONTRACTS'"); run $M >/dev/null
chk "T7 otras unidades intactas" "select ('$U0'=(select string_agg(unit_code||md5(unit_metadata::text),',' order by unit_code) from $PL where unit_code<>'PE10A_CONTRACTS'))" t
echo; echo "TOTAL $n pruebas, $f fallas"
