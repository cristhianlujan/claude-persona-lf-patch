BEGIN;

CREATE TABLE IF NOT EXISTS public.lf_profile_selection_registry_v1 (
  profile_code text PRIMARY KEY,
  canonical_profile_key text NOT NULL,
  profile_slug text NOT NULL,
  descriptor jsonb NOT NULL,
  source_kind text NOT NULL CHECK (source_kind IN ('GITHUB_SKILL','LF_ACTIVOS_RAW_PAYLOAD')),
  source_ref text NOT NULL,
  source_revision text NOT NULL,
  descriptor_status text NOT NULL DEFAULT 'CURRENT'
    CHECK (descriptor_status IN ('CURRENT','STALE_SOURCE_CHANGED')),
  stale_reason text,
  synced_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  synced_by_execution_id text
);

COMMENT ON TABLE public.lf_profile_selection_registry_v1 IS
'Canonical deterministic profile descriptors for semantic profile selection. This registry discovers and describes profiles; it does not choose a profile semantically.';

REVOKE ALL ON TABLE public.lf_profile_selection_registry_v1 FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT SELECT ON TABLE public.lf_profile_selection_registry_v1 TO service_role;

DO $guard$
DECLARE
  v_canonical_count integer;
BEGIN
  SELECT count(*) INTO v_canonical_count
  FROM public.lf_activos
  WHERE tipo_activo='PERFIL'
    AND archived_at IS NULL
    AND nullif(metadata->>'canonical_profile_key','') IS NOT NULL;

  IF v_canonical_count <> 10 THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_CANONICAL_PROFILE_SET_DRIFT expected=10 actual=%',
      v_canonical_count;
  END IF;
END
$guard$;

WITH seed(profile_code,descriptor,source_kind,source_ref,source_revision) AS (
  VALUES
('ACT-0051', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Convert approved product and UI specifications into implementation advice or static, reviewable frontend prototypes for LF sandbox use. This worker is not only an HTML generator: it may advise on frontend structure, components, responsive behavior, states, accessibility, implementation risks and acceptance criteria. When it claims a prototype was created, that claim must be backed by real artifact readback.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Convert approved product and UI specifications into implementation advice or static, reviewable frontend prototypes for LF sandbox use. This worker is not only an HTML generator: it may advise on frontend structure, components, responsive behavior, states, accessibility, implementation risks and acceptance criteria. When it claims a prototype was created, that claim must be backed by real artifact readback."},{"kind":"ACTIVATION","source_section":"Activation triggers","value":"Activate this worker when the request involves: frontend implementation advice, translating UI decisions into components/states, static HTML preview, HTML/CSS sandbox, frontend prototype, clickable static section, visual implementation preview, designer/developer handoff prototype, or converting an approved UI spec into a local browser artifact."},{"kind":"EXCLUSION","source_section":"Do not activate when","value":"- Product scope is not defined by Product Director and cannot be recovered from governed context.\n- UI structure is not defined by UI Architect and cannot be recovered from governed context.\n- The request requires backend, API, authentication, database, deployment, tracking, payment, production app, runtime or real user data.\n- The task is only product strategy, UI direction, copywriting, legal review, QA review or image prompt generation.\n\nFor these cases, do not silently terminate or improvise ownership: return a typed routing/block state so the orchestrator can resolve the next governed capability."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/frontend_prototype_architect_lf/SKILL.md', 'cc1ac8c6d0455c1b9d9e225e5e1382a084be6cd4'),
('PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Produce an implementation-ready customer financial decision specification for LF journeys such as settlement offers, installment options, due dates, discounts, payment timing, debt-resolution paths and financial next-step choices.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Produce an implementation-ready customer financial decision specification for LF journeys such as settlement offers, installment options, due dates, discounts, payment timing, debt-resolution paths and financial next-step choices."},{"kind":"OWNERSHIP","source_section":"Workflow / route","value":"Separate decision meaning from presentation. This profile owns financial decision semantics; UI Architect owns visual layout/components."},{"kind":"BOUNDARY","source_section":"Authority limits / boundaries","value":"This profile may decide customer financial decision semantics only from supplied governed authority. It must not design UI layout, execute payments, issue legal conclusions, decide privacy consent, create gamification mechanics, invent authority, bypass Router/Orchestrator, enable runtime, mark VALIDATED/VIGENTE, or authorize production. Deterministic validators and fixtures prove contract consistency only; behavioral PASS requires RAW output plus an execution receipt bound to exact source/input/output and applicable semantic review."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/customer_financial_ux_decisioning/SKILL.md', '8729433b02b0905da0ea29f94073144273ee5b88'),
('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Review operational claims that depend on GitHub, Supabase, CI, EKB, or governing LF assets. Determine whether the claim is supported by direct, current, revision-bound evidence.","selection_evidence":[{"kind":"ROLE","source_section":"Role","value":"Review operational claims that depend on GitHub, Supabase, CI, EKB, or governing LF assets. Determine whether the claim is supported by direct, current, revision-bound evidence."},{"kind":"BOUNDARY","source_section":"Non-negotiable rules","value":"- Direct current readback outranks handoff prose.\n- `read=true`, `current=true`, `artifact_verified=true`, matching declared hashes, or a declared receipt-valid flag are not evidence by themselves.\n- A translated or rephrased structural identifier is not canonical until reconciled against governing authority.\n- Evidence from another commit/run cannot prove an exact-revision claim.\n- Missing or conflicting authority blocks a definitive PASS.\n- A semantic assertion can use only an `authority_ref` that belongs to the resolver-backed material authority universe.\n- This profile cannot merge, mutate Supabase, enable runtime, promote candidates, or authorize production."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/evidence_lineage_reviewer_lf/SKILL.md', '2acf40bb9130a76a1b8cf3dc5a71dae1f0da0b3c'),
('PERFIL-GAMIFICATION-SYSTEM-ARCHITECT', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Convert an authorized product/UX objective into an ethical, measurable and testable gamification system. The worker produces executable mechanics, not decorative ideas, and cannot invent eligibility, debt, payment, urgency or success claims.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Convert an authorized product/UX objective into an ethical, measurable and testable gamification system. The worker produces executable mechanics, not decorative ideas, and cannot invent eligibility, debt, payment, urgency or success claims."},{"kind":"BOUNDARY","source_section":"Automatic block / missing input","value":"Block or route unresolved material input when:\n- the objective or healthy target behavior remains materially unresolved after context resolution;\n- a material financial claim lacks current authority;\n- the mechanic requires pressure, punitive loss or harmful financial incentive;\n- activation/deactivation is unsafe or unreachable;\n- a required guardrail is absent or would be lost downstream;\n- the metric has no decision use;\n- the worker re-asks a resolved objective/guardrail/authority;\n- a noncanonical proposal is represented as current product/financial authority."},{"kind":"BOUNDARY","source_section":"Runtime and impact","value":"Runtime remains disabled. Automatic promotion remains disabled. No Router, UI/Frontend, Quality/Evidence or cross-runtime changes are authorized by this pack."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/gamification_system_architect/SKILL.md', '09deca7a98efaa1efb836a53b087eecaa4d805ce'),
('PERFIL-PRODUCT-DIRECTOR-LF', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Define product direction, scope, priority, functional trade-offs, acceptance criteria and handoff for LF deliverables. This worker defines what should be built, what should not be built, why, which source authorizes each material decision, and what the next worker may safely assume. It does not replace UX/UI, Copy, Legal, Tech, Data, QA or human approval.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Define product direction, scope, priority, functional trade-offs, acceptance criteria and handoff for LF deliverables. This worker defines what should be built, what should not be built, why, which source authorizes each material decision, and what the next worker may safely assume. It does not replace UX/UI, Copy, Legal, Tech, Data, QA or human approval."},{"kind":"ACTIVATION","source_section":"Activation triggers","value":"Use for product scope/priority decisions, MVP vs future scope, product conflicts, acceptance criteria, or translation of business intent into an operational brief."},{"kind":"EXCLUSION","source_section":"Do not activate when","value":"- The task is only visual design, copywriting, legal approval, technical architecture, data modeling, financial advice or document audit.\n- A product decision is already closed and verified.\n- The request needs a specialist first and the product question is not defined."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/product_director_lf/SKILL.md', '479ccb9261980100999935c8e84e32dac3adc160'),
('PERFIL-QUALITY-PACK', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable."},{"kind":"ACTIVATION","source_section":"Activation triggers","value":"Activate this worker when an upstream profile returns a deliverable, score, PASS/PASS_WITH_RESTRICTIONS, handoff, prompt draft, UI spec, render spec, image prompt, document patch, or any artifact that may proceed to Composer, Final Judge or generation."},{"kind":"EXCLUSION","source_section":"Do not activate when","value":"- There is no upstream artifact to review.\n- The task is simple prose with no operational impact.\n- The orchestrator has not provided the worker output, contract, expected schema or acceptance criteria."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/quality_pack/SKILL.md', 'de455eaba3fa7e4bbca01a368a506c8764ebc75d'),
('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient, implementable repair specification that eliminates the failure class rather than the first plausible local fix.\n\nThe profile designs and specifies the repair. It does not implement it, activate it, promote it, or claim post-implementation verification that has not occurred.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient, implementable repair specification that eliminates the failure class rather than the first plausible local fix.\n\nThe profile designs and specifies the repair. It does not implement it, activate it, promote it, or claim post-implementation verification that has not occurred."},{"kind":"ACTIVATION","source_section":"Activation","value":"Use for recurrent failures, repeated local repairs, cross-run regressions, bypasses, replay/duplicate failures, partial-failure recovery defects, stale-state defects, authority/source contradictions, or incidents whose immediate cause is not sufficient to explain recurrence.\n\nAlso use for architecture/lifecycle audits of a governed process when the request is to find material gaps and design the repair (`case_mode=ARCHITECTURE_AUDIT`).\n\nDo not use for simple deterministic defects whose cause and repair are already classified and covered by an existing EKB rule."},{"kind":"BOUNDARY","source_section":"Claim ceiling","value":"CANDIDATO / READ_ONLY. This profile can diagnose, compare and specify a repair; it cannot authorize or execute that repair. A repair specification is quality-accepted only through the canonical deterministic and semantic gates. Implementation and post-implementation verification remain separate governed operations."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/systemic_root_cause_repair_lf/SKILL.md', 'b0864fbdd96a6874bcf7c7f048a2280abb94df69'),
('PERFIL-UI-ARCHITECT', '{"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1","description":"Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth.","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth."},{"kind":"OWNERSHIP","source_section":"New-screen invariants","value":"Keep domain truth from upstream profiles intact; UI owns presentation, hierarchy, components, states, tokens and responsive behavior, not financial/legal/privacy truth."},{"kind":"BOUNDARY","source_section":"Traceability and lifecycle","value":"Candidate remediation evidence lives under `profiles/ui_architect/evals/<remediation_lot>/`.\nFuture profile writes require `ACTUALIZACION_PERFIL_LF` bound to `PERFIL-UI-ARCHITECT` before the first GitHub write.\nRuntime enablement, `VALIDATED`, production promotion, and automatic promotion remain blocked unless separately governed and authorized."}]}'::jsonb, 'GITHUB_SKILL', 'github://cristhianlujan/claude-persona-lf-patch@33684cc36e6ca0a7d74e3d547fce50898a16f0a5/profiles/ui_architect/SKILL.md', '2e9e59ebefe2b241b5e7493c942dc07dde7fd181')
)
INSERT INTO public.lf_profile_selection_registry_v1(
  profile_code,canonical_profile_key,profile_slug,descriptor,
  source_kind,source_ref,source_revision,descriptor_status,
  stale_reason,synced_at,synced_by_execution_id
)
SELECT
  a.codigo_activo,
  a.metadata->>'canonical_profile_key',
  a.metadata->>'profile_slug',
  s.descriptor,
  s.source_kind,
  s.source_ref,
  s.source_revision,
  'CURRENT',
  NULL,
  clock_timestamp(),
  'MIG-20261024224500-PROFILE-SELECTOR-DESCRIPTORS'
FROM seed s
JOIN public.lf_activos a ON a.codigo_activo=s.profile_code
WHERE a.tipo_activo='PERFIL'
  AND a.archived_at IS NULL
  AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  AND nullif(a.metadata->>'profile_slug','') IS NOT NULL
ON CONFLICT(profile_code) DO UPDATE SET
  canonical_profile_key=excluded.canonical_profile_key,
  profile_slug=excluded.profile_slug,
  descriptor=excluded.descriptor,
  source_kind=excluded.source_kind,
  source_ref=excluded.source_ref,
  source_revision=excluded.source_revision,
  descriptor_status='CURRENT',
  stale_reason=NULL,
  synced_at=clock_timestamp(),
  synced_by_execution_id=excluded.synced_by_execution_id;

WITH raw_profiles AS (
  SELECT *
  FROM public.lf_activos
  WHERE codigo_activo IN (
    'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
    'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
  )
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL
),
normalized AS (
  SELECT
    a.codigo_activo AS profile_code,
    a.metadata->>'canonical_profile_key' AS canonical_profile_key,
    a.metadata->>'profile_slug' AS profile_slug,
    jsonb_build_object(
      'schema_version','LF_PROFILE_SELECTION_DESCRIPTOR_V1',
      'description',a.raw_payload->>'purpose',
      'selection_evidence',jsonb_build_array(
        jsonb_build_object(
          'kind','PURPOSE',
          'source_section','raw_payload.purpose',
          'value',to_jsonb(a.raw_payload->>'purpose')
        ),
        jsonb_build_object(
          'kind','RESPONSIBILITIES',
          'source_section','raw_payload.responsibilities',
          'value',coalesce(a.raw_payload->'responsibilities','[]'::jsonb)
        ),
        jsonb_build_object(
          'kind','APPLIES_TO',
          'source_section','raw_payload.applies_to',
          'value',coalesce(a.raw_payload->'applies_to','[]'::jsonb)
        ),
        jsonb_build_object(
          'kind','BOUNDARY',
          'source_section','raw_payload.boundaries',
          'value',coalesce(a.raw_payload->'boundaries','[]'::jsonb)
        )
      )
    ) AS descriptor,
    'LF_ACTIVOS_RAW_PAYLOAD'::text AS source_kind,
    'supabase://public/lf_activos/'||a.codigo_activo||'#raw_payload' AS source_ref,
    'sha256:'||encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'purpose',a.raw_payload->'purpose',
            'responsibilities',a.raw_payload->'responsibilities',
            'applies_to',a.raw_payload->'applies_to',
            'boundaries',a.raw_payload->'boundaries'
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ) AS source_revision
  FROM raw_profiles a
)
INSERT INTO public.lf_profile_selection_registry_v1(
  profile_code,canonical_profile_key,profile_slug,descriptor,
  source_kind,source_ref,source_revision,descriptor_status,
  stale_reason,synced_at,synced_by_execution_id
)
SELECT
  profile_code,canonical_profile_key,profile_slug,descriptor,
  source_kind,source_ref,source_revision,'CURRENT',
  NULL,clock_timestamp(),'MIG-20261024224500-PROFILE-SELECTOR-DESCRIPTORS'
FROM normalized
WHERE nullif(canonical_profile_key,'') IS NOT NULL
  AND nullif(profile_slug,'') IS NOT NULL
  AND nullif(descriptor->>'description','') IS NOT NULL
ON CONFLICT(profile_code) DO UPDATE SET
  canonical_profile_key=excluded.canonical_profile_key,
  profile_slug=excluded.profile_slug,
  descriptor=excluded.descriptor,
  source_kind=excluded.source_kind,
  source_ref=excluded.source_ref,
  source_revision=excluded.source_revision,
  descriptor_status='CURRENT',
  stale_reason=NULL,
  synced_at=clock_timestamp(),
  synced_by_execution_id=excluded.synced_by_execution_id;

CREATE OR REPLACE FUNCTION public.lf_profile_selector_catalog_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
WITH p AS (
  SELECT
    a.codigo_activo AS profile_code,
    a.nombre_canonico AS profile_name,
    a.subtipo_activo AS profile_subtype,
    a.estado_documental AS document_status,
    a.estado_operativo AS operational_status,
    a.runtime_estado AS runtime_status,
    a.version,
    a.metadata->>'canonical_profile_key' AS canonical_profile_key,
    a.metadata->>'profile_slug' AS profile_slug,
    r.descriptor,
    r.source_kind,
    r.source_ref,
    r.source_revision,
    CASE
      WHEN nullif(a.metadata->>'canonical_profile_key','') IS NULL
        THEN 'NONCANONICAL_PROFILE_RECORD'
      WHEN r.profile_code IS NULL
        THEN 'DESCRIPTOR_MISSING'
      ELSE r.descriptor_status
    END AS descriptor_status,
    (
      nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
      AND r.profile_code IS NOT NULL
      AND r.descriptor_status='CURRENT'
    ) AS selection_eligible
  FROM public.lf_activos a
  LEFT JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
  WHERE a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
),
agg AS (
  SELECT
    count(*)::integer AS total_profile_records,
    count(*) FILTER (WHERE canonical_profile_key IS NOT NULL)::integer AS canonical_profile_count,
    count(*) FILTER (WHERE selection_eligible)::integer AS selectable_profile_count,
    bool_and(
      CASE WHEN canonical_profile_key IS NULL THEN true
           ELSE descriptor_status='CURRENT' AND descriptor IS NOT NULL
      END
    ) AS all_canonical_descriptors_complete,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'profile_code',profile_code,
          'profile_name',profile_name,
          'profile_subtype',profile_subtype,
          'canonical_profile_key',canonical_profile_key,
          'profile_slug',profile_slug,
          'document_status',document_status,
          'operational_status',operational_status,
          'runtime_status',runtime_status,
          'version',version,
          'selection_eligible',selection_eligible,
          'descriptor_status',descriptor_status,
          'descriptor',descriptor,
          'descriptor_source_kind',source_kind,
          'descriptor_source_ref',source_ref,
          'descriptor_source_revision',source_revision
        )
        ORDER BY profile_code
      ),
      '[]'::jsonb
    ) AS profiles
  FROM p
)
SELECT jsonb_build_object(
  'schema_version','LF_PROFILE_SELECTOR_CATALOG_V1',
  'selection_mode','DETERMINISTIC_DISCOVERY_ONLY',
  'semantic_selection_performed',false,
  'total_profile_records',total_profile_records,
  'canonical_profile_count',canonical_profile_count,
  'selectable_profile_count',selectable_profile_count,
  'all_canonical_descriptors_complete',all_canonical_descriptors_complete,
  'profiles',profiles
)
FROM agg
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_catalog_v1() IS
'Returns the complete deterministic profile catalog and source-bound descriptors. It never performs semantic ranking or chooses a profile.';

REVOKE ALL ON FUNCTION public.lf_profile_selector_catalog_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_catalog_v1() TO service_role, supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_profile_selector_descriptor_sync_v1(
  p_profile_code text,
  p_descriptor jsonb,
  p_source_kind text,
  p_source_ref text,
  p_source_revision text,
  p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  a public.lf_activos%rowtype;
  v_slug text;
  v_key text;
BEGIN
  IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
     OR jsonb_typeof(p_descriptor) IS DISTINCT FROM 'object'
     OR p_descriptor->>'schema_version' IS DISTINCT FROM 'LF_PROFILE_SELECTION_DESCRIPTOR_V1'
     OR nullif(btrim(coalesce(p_descriptor->>'description','')),'') IS NULL
     OR jsonb_typeof(p_descriptor->'selection_evidence') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_descriptor->'selection_evidence')=0
     OR p_source_kind NOT IN ('GITHUB_SKILL','LF_ACTIVOS_RAW_PAYLOAD')
     OR nullif(btrim(coalesce(p_source_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_source_revision,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_actor_execution_id,'')),'') IS NULL
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_SYNC_INPUT_INVALID';
  END IF;

  IF p_source_kind='GITHUB_SKILL'
     AND p_source_revision !~ '^[0-9a-f]{40}$'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_GITHUB_REVISION_INVALID';
  END IF;

  IF p_source_kind='LF_ACTIVOS_RAW_PAYLOAD'
     AND p_source_revision !~ '^sha256:[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_RAW_REVISION_INVALID';
  END IF;

  SELECT * INTO a
  FROM public.lf_activos
  WHERE codigo_activo=p_profile_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_PROFILE_NOT_FOUND';
  END IF;

  v_slug:=a.metadata->>'profile_slug';
  v_key:=a.metadata->>'canonical_profile_key';

  IF nullif(v_slug,'') IS NULL OR nullif(v_key,'') IS NULL THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_PROFILE_NOT_CANONICAL';
  END IF;

  IF p_source_kind='GITHUB_SKILL' THEN
    IF nullif(a.metadata->>'repo_path','') IS NULL
       OR position('/'||(a.metadata->>'repo_path')||'/SKILL.md' IN p_source_ref)=0
    THEN
      RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_SOURCE_BINDING_INVALID';
    END IF;
  ELSE
    IF p_source_ref IS DISTINCT FROM
       'supabase://public/lf_activos/'||p_profile_code||'#raw_payload'
    THEN
      RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_RAW_SOURCE_BINDING_INVALID';
    END IF;
  END IF;

  INSERT INTO public.lf_profile_selection_registry_v1(
    profile_code,canonical_profile_key,profile_slug,descriptor,
    source_kind,source_ref,source_revision,descriptor_status,
    stale_reason,synced_at,synced_by_execution_id
  ) VALUES (
    p_profile_code,v_key,v_slug,p_descriptor,
    p_source_kind,p_source_ref,p_source_revision,'CURRENT',
    NULL,clock_timestamp(),p_actor_execution_id
  )
  ON CONFLICT(profile_code) DO UPDATE SET
    canonical_profile_key=excluded.canonical_profile_key,
    profile_slug=excluded.profile_slug,
    descriptor=excluded.descriptor,
    source_kind=excluded.source_kind,
    source_ref=excluded.source_ref,
    source_revision=excluded.source_revision,
    descriptor_status='CURRENT',
    stale_reason=NULL,
    synced_at=clock_timestamp(),
    synced_by_execution_id=excluded.synced_by_execution_id;

  RETURN jsonb_build_object(
    'outcome','SYNCED',
    'profile_code',p_profile_code,
    'canonical_profile_key',v_key,
    'profile_slug',v_slug,
    'descriptor_status','CURRENT',
    'source_kind',p_source_kind,
    'source_ref',p_source_ref,
    'source_revision',p_source_revision
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_selector_descriptor_sync_v1(text,jsonb,text,text,text,text)
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_descriptor_sync_v1(text,jsonb,text,text,text,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.lf_profile_selector_descriptor_invalidate_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF NEW.tipo_activo='PERFIL'
     AND (
       OLD.archived_at IS DISTINCT FROM NEW.archived_at
       OR OLD.metadata->>'entrypoint_sha' IS DISTINCT FROM NEW.metadata->>'entrypoint_sha'
       OR OLD.raw_payload->>'skill_sha' IS DISTINCT FROM NEW.raw_payload->>'skill_sha'
       OR OLD.raw_payload->'purpose' IS DISTINCT FROM NEW.raw_payload->'purpose'
       OR OLD.raw_payload->'responsibilities' IS DISTINCT FROM NEW.raw_payload->'responsibilities'
       OR OLD.raw_payload->'applies_to' IS DISTINCT FROM NEW.raw_payload->'applies_to'
       OR OLD.raw_payload->'boundaries' IS DISTINCT FROM NEW.raw_payload->'boundaries'
     )
  THEN
    UPDATE public.lf_profile_selection_registry_v1
    SET descriptor_status='STALE_SOURCE_CHANGED',
        stale_reason='PROFILE_SOURCE_CHANGED_REQUIRES_DESCRIPTOR_RESYNC',
        synced_at=clock_timestamp()
    WHERE profile_code=NEW.codigo_activo
      AND descriptor_status='CURRENT';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_selector_descriptor_invalidate_v1()
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;

DROP TRIGGER IF EXISTS trg_lf_profile_selector_descriptor_invalidate_v1
  ON public.lf_activos;

CREATE TRIGGER trg_lf_profile_selector_descriptor_invalidate_v1
AFTER UPDATE OF metadata, raw_payload, archived_at
ON public.lf_activos
FOR EACH ROW
EXECUTE FUNCTION public.lf_profile_selector_descriptor_invalidate_v1();

DO $postcheck$
DECLARE
  v_registry_count integer;
  v_bad_count integer;
  v_catalog jsonb;
  v_noncanonical_visible boolean;
BEGIN
  SELECT count(*) INTO v_registry_count
  FROM public.lf_profile_selection_registry_v1
  WHERE descriptor_status='CURRENT';

  IF v_registry_count <> 10 THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_COUNT_INVALID expected=10 actual=%',
      v_registry_count;
  END IF;

  SELECT count(*) INTO v_bad_count
  FROM public.lf_profile_selection_registry_v1 r
  JOIN public.lf_activos a ON a.codigo_activo=r.profile_code
  WHERE a.tipo_activo<>'PERFIL'
     OR a.archived_at IS NOT NULL
     OR nullif(a.metadata->>'canonical_profile_key','') IS NULL
     OR nullif(a.metadata->>'profile_slug','') IS NULL
     OR r.canonical_profile_key IS DISTINCT FROM a.metadata->>'canonical_profile_key'
     OR r.profile_slug IS DISTINCT FROM a.metadata->>'profile_slug'
     OR r.descriptor->>'schema_version'<>'LF_PROFILE_SELECTION_DESCRIPTOR_V1'
     OR nullif(btrim(coalesce(r.descriptor->>'description','')),'') IS NULL
     OR jsonb_typeof(r.descriptor->'selection_evidence')<>'array'
     OR jsonb_array_length(r.descriptor->'selection_evidence')=0
     OR nullif(btrim(r.source_ref),'') IS NULL
     OR nullif(btrim(r.source_revision),'') IS NULL;

  IF v_bad_count <> 0 THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_DESCRIPTOR_COMPLETENESS_FAILED count=%',v_bad_count;
  END IF;

  v_catalog:=public.lf_profile_selector_catalog_v1();

  IF (v_catalog->>'canonical_profile_count')::integer <> 10
     OR (v_catalog->>'selectable_profile_count')::integer <> 10
     OR coalesce((v_catalog->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE
     OR (v_catalog->>'semantic_selection_performed')::boolean IS NOT FALSE
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_CATALOG_POSTCHECK_FAILED:%',v_catalog;
  END IF;

  SELECT EXISTS(
    SELECT 1
    FROM jsonb_array_elements(v_catalog->'profiles') p
    WHERE p->>'profile_code'='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF-V06-CANDIDATE'
      AND p->>'descriptor_status'='NONCANONICAL_PROFILE_RECORD'
      AND (p->>'selection_eligible')::boolean IS FALSE
  ) INTO v_noncanonical_visible;

  IF NOT v_noncanonical_visible THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_NONCANONICAL_RECORD_NOT_VISIBLE';
  END IF;
END
$postcheck$;

COMMIT;
