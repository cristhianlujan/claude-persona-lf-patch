-- EKB / IG M9.13 signed independent readback closeout. Append-only documentation.
-- No checkpoint mutation, no production or release operation.
DO $m913_ekb$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M913-INDEPENDENT-REAL-RUNNER-VERIFIED-001')
 THEN RAISE EXCEPTION 'M913_EKB_ALREADY_RECORDED'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,created_at,updated_at,source_context,source_ref)
 VALUES(
 gen_random_uuid(),
 'IG-M913-INDEPENDENT-REAL-RUNNER-VERIFIED-001',
 'IG_INDEPENDENT_EVIDENCE',
 'M9.13 certified by distinct real executor with ledger and HANDOFF manifest parity',
 'A completed local test and an INDEPENDENT_READBACK event emitted by the HANDOFF producer were insufficient. For terminal acceptance the independently executed, source-bound verifier must read the canonical 13-unit ledger snapshot and HANDOFF evidence and return an auditable receipt.',
 'Evidence transport, actor separation and assertion were incomplete even after the bounded-test packet compiler was repaired. The risk of self-assertion was covered by prior IG-M913-INDEPENDENT-EVENT-SELF-CLAIM-001.',
 'Machine-positive readback is not terminal until a second actor executes the exact Git-merged test with real 13-unit Supabase evidence, adversarial negative, persisted assertion and checkpoint transition readback.',
 'At checkpoint preflight: compare EKB against contract, governance and validator; run exact merged Python artifact on authenticated distinct SentinelX host, bind canonical source blob, canonical snapshot SHA and HANDOFF producer identity. Require 13/13, identical ledger/HANDOFF manifest SHA, no missing evidence or discrepancies and a negative tamper rejected. Record actor-specific evidence via assertion_record_v1, then checkpoint_transition_v1 and rebootstrap. No synthetic PASS or self-reported independent_identity, no POST_PASE or production activation.',
 'Positive: host_3d5ff6fb467d4e9e script_job_6cb6bf8a18cf4eeeabf6b487c455ac15 exit=0 PASS 13/13, discrepancy=0, sha256=19923001b6a493b2f34a35234d7be72953c777a88257a29d18468145f7b9057f. Adversarial: script_job_ece4eea3a9e942aabc160cbd28794d8b exit=1 FAIL mismatched M9.0 and manifest. Source blob=a0712ed52ba8120c9adfdf79c1b87eb88285d94d; DB snapshot sha256=bd6a4816a366138a412a60db427a531592fefa4e66308d9ca14183962d4a798a. Assertion receipt sha256=2c79eaa56a27ed32145c59f50527f805b7ef25a5fc8a63184e2c4128c23bad30. Canonical readback M9.13 DONE 5/5 100 percent, open_blockers=0 STOP_TERMINAL_DONE. Generic self-claim risk in older units remains separately tracked.',
 'HIGH',1,now(),now(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.13',NULL,'VERIFICADO',
 'sentinelx://host_3d5ff6fb467d4e9e/script_job_6cb6bf8a18cf4eeeabf6b487c455ac15;negative=script_job_ece4eea3a9e942aabc160cbd28794d8b;supabase://programacion.engineering_work_checkpoints/M9.13',
 now(),now(),
 'M9_INDEPENDENT_READBACK: technical sandbox closure, no production cutover',
 'supabase://programacion.fn_engineering_unit_bootstrap_v3/IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.13');
END $m913_ekb$;
