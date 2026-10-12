-- EKB append-only verified M10.1 preflight remediation, sandbox only.
DO $m101_ekb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M101-FIXED-COUNTS-NAME-PREFIX-SANDBOX-CONTRACT-001')
 THEN RAISE EXCEPTION 'M101_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,created_at,updated_at,source_context,source_ref)
 VALUES
 (gen_random_uuid(),
 'IG-M101-FIXED-COUNTS-NAME-PREFIX-SANDBOX-CONTRACT-001',
 'IG_CONTRACT_GOVERNANCE_VALIDATOR',
 'M10.1 candidate hardcoded 4/2/2 consumer counts and guessed Profiles from asset-code prefixes',
 'The unmerged M10.1 candidate source used count=4, Adapter=2, Profiles=2, and profile LIKE name patterns as acceptance authority. The CP3 generic assertion only required Git merged and readback, allowing inventory-complete to be confused with router facade migration or release acceptance.',
 'The checkpoint contract lacked a data-governed dynamic eligibility rule and semantically strong acceptance. This recreates the M9.9/M9.10 errors of stale acceptance, fixed operational prerequisites and incomplete source-pack/governance alignment.',
 'A snapshot count or asset-code prefix must never become a permanent contract, and sandbox consumer inventory is not proof of runtime facade use, release qualification or live operational admission.',
 'Before the first attempt, compare EKB M9.9/M9.10 against CP3 contract, source_pack, governance, and downstream CP4-CP6; derive eligibility from current public.lf_activos typed metadata and observed relations. Deduplicate by codigo_activo, calculate expected delta versus baseline, reject unbound Adapters and unrelated capabilities, keep an explicit sandbox-only stage. Contract+governance+validator/readback must change together; test positive/negative in transaction and ROLLBACK before Git-first exact source merge. Independently validate ROUTER_MIGRATED, NEG_INTERNAL_CALL and FACADE_READBACK later; do not infer zero external callers from CP3 DONE and do not require live release receipts for sandbox qualification.',
 'PR #2297 merged squash 5fac5a879e59c04fe26ff29ed3a41f4aa937007c. Migrations 20261012133000 contract-governance source blob 2a74a4e81e230d64022440f1537ddd223784f232, 20261012133100 inventory source blob f3aef4730a8793b35f1b7fb95e7bd623a7204394. Source-first Git=ledger=DB; BEGIN-like nested subtransaction test: contract + inventory readback READY, negative excludes noneligible, 0 residual after rollback. Real readback eligible=4 (2 Profiles,2 Adapters) dynamic, covered=4, unauthorized=0, duplicates=0, runtime_authorized=false, production_authorized=false. Negative assertion rejected; positive receipt sha256=75dc8aa13d034ea5a99eca7e4bf3b3855e7055b4139cf658a5637e80722e618b; CP3 transition applied, ledger M10.1 50% 3/6. CP4-CP6 NOT certified.',
 'HIGH',1,now(),now(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.1','#2297','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2297;supabase://supabase_migrations.schema_migrations/20261012133000;supabase://supabase_migrations.schema_migrations/20261012133100;supabase://programacion.engineering_work_checkpoints/M10.1/PROFILES_ADAPTERS_CONSUMERS',
 now(),now(),
 'ENGINEERING_SANDBOX_INVENTORY;NO_RUNTIME_ACTIVATION;downstream CP4 CP5 CP6 remain pending',
 'programacion.engineering_plan_units/M10.1;github://cristhianlujan/claude-persona-lf-patch/pull/2297');
END $m101_ekb$;