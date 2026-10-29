H=/home/pgtest; S=/tmp/claude-0/-home-claude/6f209a87-4203-56a2-995c-a9783177ba4a/scratchpad
M=/home/claude/claude-persona-lf-patch/supabase/migrations/20261027203000_lf_pe10_readiness_work_item_dependency_gate_v1.sql
N=20261027203000_lf_pe10_readiness_work_item_dependency_gate_v1
PL=programacion.engineering_plan_units; PLAN=PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1
FN=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1
P="psql -h $H/sock -p 54330 -U pgtest -q -At"
fresh(){ $P -d postgres -c "drop database if exists t_run" -c "create database t_run template t_dep" >/dev/null 2>&1; }
train(){ $P -d t_run -c "insert into public.lf_operation_execution values ('EXEC-D1','ACTUALIZACION_DB_LF','MIGRATION','$N','IN_PROGRESS')" >/dev/null; }
snap(){ $P -d t_run -c "drop table if exists $1" >/dev/null 2>&1; $P -d t_run -c "create table $1 as select u.unit_code, c.checkpoint_code, c.status cp_status, $FN(u.plan_code,u.unit_code,c.checkpoint_code,'{}','{}') rd from $PL u join programacion.engineering_work_checkpoints c on c.work_item_id=u.work_item_id where u.disposition='ASSIGNED'" >/dev/null; }
n=0; f=0
chk(){ r=$($P -d t_run -c "$2" 2>&1); n=$((n+1)); if [ "$r" = "$3" ]; then echo "PASS  $1  ($r)"; else f=$((f+1)); echo "FAIL  $1  obtenido=[$r] esperado=[$3]"; fi; }
run(){ $P -d t_run -v ON_ERROR_STOP=1 -f $1 2>&1 | grep -E "ERROR" | sed 's/.*ERROR:  //' | head -1; }
expect_err(){ r=$(run $2); n=$((n+1)); if [ "$r" = "$3" ]; then echo "PASS  $1  -> $r"; else f=$((f+1)); echo "FAIL  $1  obtenido=[$r] esperado=[$3]"; fi; }
fresh; train
$P -d t_run -c "insert into programacion.engineering_work_checkpoints(work_item_id,checkpoint_code,title,sequence_no,weight,required,status) select work_item_id,'ZZ_JUD_NR','x',99,1,true,'PENDING' from $PL where unit_code='PE10A_JUDGES'; insert into programacion.engineering_work_checkpoints(work_item_id,checkpoint_code,title,sequence_no,weight,required,status) select work_item_id,'ZZ_CON_NR','x',99,1,true,'PENDING' from $PL where unit_code='PE10A_CONTRACTS';" >/dev/null
snap zz_before; r=$(run $M); echo "migración con Train: ${r:-OK sin errores}"; snap zz_after
chk "T1 función cambiada (marcador en prosrc)" "select position('WORK_ITEM_DEPENDENCY_UNMET' in prosrc)>0 from pg_proc where proname='fn_engineering_checkpoint_execution_readiness_from_payload_v1'" "t"
chk "T1 ACL conservada (lf_app_r sigue con EXECUTE)" "select has_function_privilege('lf_app_r','$FN(text,text,text,jsonb,jsonb)','EXECUTE')" "t"
chk "T1 public sigue sin EXECUTE" "select has_function_privilege('public','$FN(text,text,text,jsonb,jsonb)','EXECUTE')" "f"
EXP="select count(*) from zz_after a join $PL u on u.unit_code=a.unit_code join programacion.engineering_work_checkpoints c on c.work_item_id=u.work_item_id and c.checkpoint_code=a.checkpoint_code where c.status in ('PENDING','IN_PROGRESS') and exists (select 1 from programacion.engineering_work_dependencies d join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id where d.work_item_id=u.work_item_id and d.relation_type='REQUIRES' and dw.status not in ('DONE','CANCELLED'))"
EXPN=$($P -d t_run -c "$EXP")
chk "T2 filas cambiadas == abiertos con dependencia sin cumplir (calculado aparte: $EXPN)" "select count(*) from zz_before b join zz_after a using(unit_code,checkpoint_code) where b.rd is distinct from a.rd" "$EXPN"
chk "T2 filas cambiadas son todas NOT_READY con razón tipada" "select count(*) from zz_before b join zz_after a using(unit_code,checkpoint_code) where b.rd is distinct from a.rd and not (a.cp_status in ('PENDING','IN_PROGRESS') and a.rd->>'status'='NOT_READY' and a.rd->'reasons' ? 'WORK_ITEM_DEPENDENCY_UNMET')" "0"
chk "T2 checkpoints DONE de PE10 idénticos" "select count(*) from zz_before b join zz_after a using(unit_code,checkpoint_code) where a.unit_code='PE10' and a.cp_status='DONE' and b.rd is distinct from a.rd" "0"
chk "T3 PE10_C6 antes READY" "select rd->>'status' from zz_before where checkpoint_code='PE10_C6'" "READY"
chk "T3 PE10_C6 después NOT_READY" "select rd->>'status' from zz_after where checkpoint_code='PE10_C6'" "NOT_READY"
chk "T3 PE10_C7 después NOT_READY" "select rd->>'status' from zz_after where checkpoint_code='PE10_C7'" "NOT_READY"
chk "T3 C6 razón tipada + dependencia nombrada + conteo" "select (rd->'reasons')::text || '|' || (rd#>>'{dependencies,unmet,0,work_code}') || '|' || (rd#>>'{dependencies,unmet_count}') from zz_after where checkpoint_code='PE10_C6'" '["WORK_ITEM_DEPENDENCY_UNMET"]|PEVO-PE10A_READY|1'
chk "T3 C6 DEPENDENCIES_SATISFIED=false y execution_ready=false" "select (rd#>>'{gates,DEPENDENCIES_SATISFIED}')||'|'||(rd->>'execution_ready') from zz_after where checkpoint_code='PE10_C6'" "false|false"
chk "T3 C6 gates previos conservados" "select (b.rd->'gates') = ((a.rd->'gates') - 'DEPENDENCIES_SATISFIED') from zz_before b join zz_after a using(unit_code,checkpoint_code) where checkpoint_code='PE10_C6'" "t"
chk "T4 NR con deps: razones fusionadas en orden" "select (rd->'reasons')::text from zz_after where checkpoint_code='ZZ_JUD_NR'" '["COMPILE_NOT_READY", "WORK_ITEM_DEPENDENCY_UNMET"]'
chk "T4 NR con deps: COMPILE_READY sigue false (reparadores no cambian)" "select rd#>>'{gates,COMPILE_READY}' from zz_after where checkpoint_code='ZZ_JUD_NR'" "false"
chk "T4 NR sin deps (CONTRACTS) idéntico" "select b.rd = a.rd from zz_before b join zz_after a using(unit_code,checkpoint_code) where checkpoint_code='ZZ_CON_NR'" "t"
chk "T5 unidad inexistente -> UNIT_NOT_FOUND como antes" "select ($FN('NO_PLAN','NO_UNIT','X','{}','{}')->'reasons')::text" '["UNIT_NOT_FOUND"]'
chk "T5 READY nunca lleva claves nuevas" "select count(*) from zz_after where rd ? 'dependencies' and rd->>'status'='READY'" "0"
RD="select $FN('$PLAN','PE10','PE10_C6','{}','{}')"
$P -d t_run -c "update programacion.engineering_work_items set status='DONE' where work_code='PEVO-PE10A_READY'" >/dev/null
chk "T6a dependencia DONE -> salida idéntica a la de antes" "select ($RD) = (select rd from zz_before where checkpoint_code='PE10_C6')" "t"
$P -d t_run -c "update programacion.engineering_work_items set status='CANCELLED' where work_code='PEVO-PE10A_READY'" >/dev/null
chk "T6b dependencia CANCELLED -> no bloquea" "select ($RD)->>'status'" "READY"
$P -d t_run -c "update programacion.engineering_work_items set status='IN_PROGRESS' where work_code='PEVO-PE10A_READY'" >/dev/null
chk "T6c dependencia IN_PROGRESS -> bloquea" "select ($RD)->>'status'" "NOT_READY"
$P -d t_run -c "update programacion.engineering_work_items set status='BACKLOG' where work_code='PEVO-PE10A_READY'; update $PL set disposition='FUSED', fused_into_plan_unit_id=(select id from $PL where unit_code='PE10A_CONTRACTS') where unit_code='PE10A_READY'" >/dev/null
chk "T6d FUSED a destino BACKLOG -> bloquea (FUSED_TO_TARGET)" "select (($RD)->>'status')||'|'||(($RD)#>>'{dependencies,unmet,0,resolution}')" "NOT_READY|FUSED_TO_TARGET"
$P -d t_run -c "update programacion.engineering_work_items set status='DONE' where work_code='PEVO-PE10A_CONTRACTS'" >/dev/null
chk "T6e FUSED a destino DONE -> READY" "select ($RD)->>'status'" "READY"
$P -d t_run -c "update programacion.engineering_work_items set status='BACKLOG' where work_code='PEVO-PE10A_CONTRACTS'; update programacion.engineering_work_checkpoints set status='DONE' where checkpoint_code='PE10_C6'" >/dev/null
chk "T6f C6 ya DONE con dependencia sin cumplir -> sin cambio" "select ($RD)->>'status'" "READY"
echo "##### negativos de la migración"
fresh; expect_err "N1 sin ejecución del Train" $M PE10_READINESS_DEP_GATE_TRAIN_TRANSPORT_REQUIRED
fresh; train; $P -d t_run -c "create or replace function $FN(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb) returns jsonb language plpgsql stable as \$f\$ begin return '{}'::jsonb; end \$f\$" >/dev/null
H0=$($P -d t_run -c "select md5(prosrc) from pg_proc where proname='fn_engineering_checkpoint_execution_readiness_from_payload_v1'")
expect_err "N2 función con deriva" $M PE10_READINESS_DEP_GATE_PRESTATE_DRIFT_OR_ALREADY_APPLIED
chk "N2 función de la deriva quedó intacta" "select md5(prosrc) from pg_proc where proname='fn_engineering_checkpoint_execution_readiness_from_payload_v1'" "$H0"
fresh; train; run $M >/dev/null; expect_err "N3 reaplicar" $M PE10_READINESS_DEP_GATE_PRESTATE_DRIFT_OR_ALREADY_APPLIED
fresh; train; $P -d t_run -c "create or replace function programacion.fn_engineering_effective_dependencies_v1(p_work_item_id bigint) returns table(dependency_id bigint, relation_type text, raw_depends_on_work_item_id bigint, raw_work_code text, raw_status text, effective_work_item_id bigint, effective_work_code text, effective_status text, resolution text, is_unmet boolean) language sql stable as \$f\$ select null::bigint,null::text,null::bigint,null::text,null::text,null::bigint,null::text,null::text,null::text,false where false \$f\$" >/dev/null
expect_err "N4 función de dependencias con deriva" $M PE10_READINESS_DEP_GATE_DEPENDENCY_FN_DRIFT
fresh; train; $P -d t_run -c "drop function programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(text,jsonb,jsonb,jsonb)" >/dev/null 2>&1
expect_err "N5 falta from_context" $M PE10_READINESS_DEP_GATE_CONTEXT_FN_MISSING
echo "##### control de mutación: la suite debe DETECTAR una implementación defectuosa"
sed "s/if v_cp_status is null or v_cp_status in ('DONE','NOT_APPLICABLE') then/if v_cp_status is null then/" $M > $S/dep/mut.sql
fresh; train; snap zz_before; run $S/dep/mut.sql >/dev/null; snap zz_after
chk "MUT1 sin exención de DONE: se detectan los 6 DONE de PE10 alterados" "select count(*) from zz_before b join zz_after a using(unit_code,checkpoint_code) where a.unit_code='PE10' and a.cp_status='DONE' and b.rd is distinct from a.rd" "6"
sed "s/if v_unmet_count=0 then/if false then/" $M > $S/dep/mut2.sql
fresh; train; snap zz_before; run $S/dep/mut2.sql >/dev/null; snap zz_after
chk "MUT2 sin salida temprana: se detecta alteración de checkpoints sin dependencias" "select count(*) > 0 from zz_before b join zz_after a using(unit_code,checkpoint_code) where a.unit_code='PE10A_CONTRACTS' and b.rd is distinct from a.rd" "t"
echo "=== TOTAL: $n pruebas, $f fallos ==="
