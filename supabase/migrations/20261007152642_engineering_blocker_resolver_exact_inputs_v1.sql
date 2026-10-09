update programacion.engineering_plan_units
         set unit_metadata=jsonb_set(
           unit_metadata,
           '{runtime_repair_inputs_v1,CONTEXT_OBJECT,target_resolution}',
           jsonb_build_object(
             'exact_db_objects',jsonb_build_array(
               'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'
             ),
             'authority','LIVE_EDGE_RECEIVER_PLUS_PG_PROC'
           ),true
         )
         where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
           and unit_code='M5.3'
           and disposition='ASSIGNED';

         update programacion.engineering_plan_units
         set unit_metadata=jsonb_set(
           unit_metadata,
           '{runtime_repair_inputs_v1,OBSERVATION_COUNT,evaluator}',
           jsonb_build_object(
             'regprocedure','programacion.fn_engineering_soak_observation_history_v2(text,text,text,boolean)',
             'authority','SOAK_OBSERVATION_HISTORY_V2'
           ),true
         )
         where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
           and unit_code='M9.11'
           and disposition='ASSIGNED';