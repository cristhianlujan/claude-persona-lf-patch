# PRODUCER PACKET — B29 (PE10_M29_E2) — case PE10-IG-M107-M109-P0

You are the PRODUCER INVESTIGATOR for this arm. This is a brand-new conversation. Use ONLY the material in this packet.
Do not use anything you may know or remember about this case from outside this packet. If you recognise prior findings about this case from anywhere other than this packet, say so immediately and mark the run CONTAMINATED.

## What you must do (in this single conversation)
1. Verify your identity, contract and sources against the hashes written in this packet (state what you can and cannot verify yourself; do not invent hashes).
2. Execute FIVE role-bound research passes, sequentially, in this order: ARCHITECTURE, PERFORMANCE, AUTHORITY, COVERAGE, INNOVATION. While running a role, do NOT consult your own earlier role reports (only the SYNTHESIZER reads all five). You are one model in one context: report that non-isolation risk honestly; never claim five independent agents.
3. At the end of each role pass, emit its report between the exact markers
   ===ROLE_REPORT:<ROLE> BEGIN=== ... ===ROLE_REPORT:<ROLE> END===
   and state "RAW FROZEN". A frozen report is immutable: do not edit it later.
4. After all five are frozen, run the SYNTHESIZER using ONLY those five frozen reports (plus the contract). Preserve every individually identified material edge/relation with its source identity and query ID, or give an explicit evidence-based exclusion reason. Counts or totals may never replace identities.
5. Final deliverable: one JSON object (marker ===SYNTHESIS BEGIN=== ... ===SYNTHESIS END===) with: findings (each: id, claim, evidence_refs, confidence, impact, new_vs_input), causal_model, candidate_repairs, chosen_repair, rejected_alternatives, omissions_searched, negative_falsifiers, constraints_preserved, unresolved, next_safe_step, plus provenance (sources, queries, falsifiers, omissions, uncertainties, measured costs only if actually measured; otherwise NO_MEDIDO).
6. Output state: RAW_FROZEN_UNGRADED. Do NOT self-grade. Do NOT claim READY/DONE/PASS/REPAIR from a lexical reference, and do not present CURRENT readbacks as P0 historical proof (label every observation P0_HISTORICAL or CURRENT).

## How to run read-only queries (you cannot reach any database yourself)
A coordinator will execute your read-only SQL on the LF Supabase PostgreSQL database (read-only connector) and paste the verbatim result back.
- To query, output ONE block exactly like:
  ```
  QUERY_REQUEST Q<number>
  <a single read-only SQL statement>
  ```
  then STOP and wait. The coordinator replies "QUERY_RESULT Q<number>" with the raw result (if large it is truncated and says so, with the full-result SHA-256; use LIMIT/OFFSET or narrower selects to page).
- There is NO arbitrary cap on the number of queries: choose and stop on evidence and investigative value. Run as many as you need.
- Only SELECT/read-only catalog queries. The coordinator does not interpret, advise, filter by relevance or suggest queries; it refuses only (a) any write/DDL, and (b) queries that would return material on the producer denylist (see envelope: post-cutoff material, prior PE10 result summaries, evaluator material, the other arm). A refusal is returned as QUERY_REFUSED with the reason; adapt and continue.
- The source event is public.lf_eventos id=20161 (a historical snapshot dated 2026-10-04; its payload_sha256 is in the envelope). You may read its payload in slices with jsonb operators. The two historical EKB rows are listed in the envelope by codigo.
- Anything read from the database after the cutoff 2026-10-15T00:00:00Z is CURRENT, not P0.

## Hard rules
- Mode READ_ONLY. No edits, no runtime changes, no simulated tools, no invented results: every observation must come from a QUERY_RESULT or from this packet.
- Hypotheses must be falsifiable, including "no defect". No predetermined diagnosis or object names are given to you.
- No READY/DONE claims. No blind-independence claim: you cannot prove provider-level isolation; say so.

Start now with step 1 (verification), then proceed to the ARCHITECTURE pass and issue your first QUERY_REQUEST when needed.

---

## COMMON P0 INPUT ENVELOPE (verbatim: COMMON_P0_INPUT_ENVELOPE_V1.json)

````json
{
  "schema": "PE10_E2_C3_CLEANROOM_COMMON_ENVELOPE_V1",
  "purpose": "Identical producer input envelope for PE10_E2_C3 B18/B29 reruns; no evaluator results or prior-arm outputs.",
  "case_ref": "PE10-IG-M107-M109-P0",
  "source_cutoff_utc": "2026-10-15T00:00:00Z",
  "source_event": {
    "id": 20161,
    "created_at": "2026-10-04T05:14:40.880842Z",
    "payload_sha256": "5ed03a1274444b49c630124ab26ed183ac964df503ba80b9baa5a0c9d95ae6cd",
    "historical_inventory_count": 38
  },
  "historical_ekb": [
    {
      "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
      "row_json_sha256": "9a2e10e0700d6bce30f354fee1c2e72c9dbbefbe8c7e40d91f6b27f53f5aa17c"
    },
    {
      "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
      "row_json_sha256": "065c722da4d6feba76fc6c35c2fabef7ab97b4594e3974fb333b098f56e94d9d"
    }
  ],
  "git_sources": {
    "p0_protocol": {
      "path": "docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md",
      "git_blob_sha1": "9cecaab714f6173a725bbb11e7043e8255889e71"
    },
    "e2_method_contract": {
      "path": "docs/profile_updater/experiments/pe10_e2/methods/M18_M29_E2_GENERIC_METHOD_CONTRACTS_V1.json",
      "git_blob_sha1": "5f0f1ca02adf711e3d4144072e1247c300be19c5"
    },
    "generic_census": {
      "path": "docs/profile_updater/experiments/pe10_e2/methods/GENERIC_REVERSE_CONSUMER_CENSUS_V1.sql",
      "git_blob_sha1": "93e144f6232dee2e82e2c7f4207a885b089b8685"
    },
    "generic_validator": {
      "path": "sandbox/lf_contract_gate_test/pe10_e2/generic_census_validator_v1.py",
      "git_blob_sha1": "5808c220cf169ae6796725b306245660d0c75e9d"
    },
    "s2_rule": {
      "path": "docs/profile_updater/experiments/pe10_e2/methods/E2_DECISION_RULE_S2_V1.json",
      "git_blob_sha1": "b3141ce75c793e1f53f429b89b86d71db99cea2c"
    }
  },
  "modules": {
    "B": "7341b9fa62cd5501f9fedc7fe07a1609c2a7eec67b387ec43fa672f0a0f48faa",
    "C": "8cd3e66b1c81880a98896b38f2695ff2eeff59390cdf31c878422cb17f3fe462",
    "D": "da04ec645508ad45d31154885498720e6bc287474e8aa88066e5c4fe0ff4b130",
    "E": "f8e327df11b6b450a51411cf64569e9fa33d66653a2e52d1863b362db47d216c"
  },
  "roles": {
    "ARCHITECTURE": "73a50dde20254d69789f49f6c690d251159087c9db02814b37a44aabc50d1f09",
    "PERFORMANCE": "da931944366562b37398f321f6de6820015bf97135741f6ac45e3e7732a9a5c5",
    "AUTHORITY": "5341281b99103d1490966612d915df6c9908ce98f0397cc89b97f839c1074a5b",
    "COVERAGE": "44cd235c1fddfcd481bfc5bc4bafdb681b957ae70335ebfae9caf85f19e62502",
    "INNOVATION": "37ae627359adbf572c1d533681a225f25054120592b931c9bd221468abd882e4",
    "SYNTHESIZER": "d383c0b412b419af79d8a17e6aab548512f5475eb9f9996ce85b9794e5a1af62"
  },
  "producer_allowlist": [
    "source_event_20161",
    "two_historical_ekb_rows_listed_in_this_envelope",
    "git_sources_listed_in_this_envelope",
    "assigned_original_method_contract",
    "assigned_module_definitions",
    "assigned_role_contracts",
    "authorized current read-only schema/source readbacks, explicitly labeled CURRENT"
  ],
  "producer_denylist": [
    "docs/profile_updater/experiments/pe10_e2/evaluator_only/**",
    "docs/profile_updater/experiments/pe10_methods32_p0/**",
    "prior PE10 result summaries or expected discoveries",
    "other C3 producer arm RAW/output",
    "external evaluator rubric/results",
    "post-cutoff observations represented as P0 historical facts"
  ],
  "environment_gate": {
    "must_be_new_producer_context": true,
    "prior_pe10_results_visible_before_source_access": "MUST_BE_FALSE",
    "memory_or_prior_context_inheritance": "MUST_BE_DISABLED_OR_ABSENT",
    "self_report_alone_is_not_provider_attestation": true,
    "if_isolation_unknown_or_prior_results_visible": "MARK_CONTAMINATED_AND_DO_NOT_CLAIM_BLIND"
  },
  "execution_rules": {
    "mode": "READ_ONLY",
    "same_case": true,
    "no_arbitrary_query_limit": true,
    "five_role_reports_freeze_before_synthesis": true,
    "synthesizer_receives_only_five_frozen_role_reports": true,
    "current_readbacks_are_not_historical_proof": true,
    "no_ready_done_repair_from_lexical_reference": true,
    "raw_must_freeze_before_evaluator_access": true
  },
  "required_provenance_output": [
    "producer_context_id",
    "input_envelope_sha256",
    "assigned_overlay_sha256",
    "source_access_log_with_hashes",
    "denylist_access_log",
    "environment_isolation_attestation",
    "five_role_raw_sha256",
    "synthesis_sha256",
    "raw_freeze_timestamp_utc",
    "blindness_state"
  ]
}
````

## YOUR PRODUCER OVERLAY (verbatim: B29_PRODUCER_OVERLAY_V1.json)

````json
{
  "schema": "PE10_E2_C3_PRODUCER_OVERLAY_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "common_envelope_sha256": "93d4f5cba4564ddb0cc46f731375d5d83d81b724e195dfc213b2d98fc9ebc090",
  "common_envelope_path": "docs/profile_updater/experiments/pe10_e2/c3_cleanroom/COMMON_P0_INPUT_ENVELOPE_V1.json",
  "producer_instruction": "Act as the actual producer investigator. Use only the common envelope plus this assigned overlay. Execute five role-bound research passes, freeze each RAW before synthesis, then synthesize from only those five reports. Do not inspect evaluator-only files, prior PE10 result summaries, original M01-M32 outputs, or the other arm. If prior PE10 findings are already visible before source access, mark CONTAMINATED and do not claim blind independence.",
  "output_state_before_external_grading": "RAW_FROZEN_UNGRADED",
  "forbidden_claims": [
    "blind independence without environment-level evidence",
    "P0 historical proof from CURRENT readbacks",
    "runtime execution from static lexical reference",
    "REPAIR_REQUIRED without demonstrated defect",
    "checkpoint DONE without governed closure"
  ],
  "producer_arm": "B29",
  "evolved_variant": "PE10_M29_E2",
  "original_method": "PE10_M29",
  "base": "B",
  "algorithms": [
    "C",
    "E"
  ],
  "original_execution_contract_sha256": "6e020e1973d318722a2bdbe060e4f15a3a9a2967b48c447f664163c623a7b283",
  "overlay_sha256": "a39ac7843d5a869de7ae8b6488b13f93082febd02375dd31aa3ea170372d6de5"
}
````

## GIT SOURCE: P0 case and protocol (P0_CASE_AND_PROTOCOL.md)

````markdown
# PE10 · IG M10.7/M10.9 — paquete ciego P0

**Coordinación:** Claude (Chrome solo si realmente está conectado). **Ejecución:** GPT Native en chats independientes. **Modalidad:** READ_ONLY, experimento no admitido como cambio de perfil.

**Corte informativo:** 2026-10-15 00:00 UTC. **Subject:** `PE10-IG-M107-M109-P0`.
El caso estudia si la optimización de Curator/Validator alcanza mejor rendimiento integral sin perder independencia, trazabilidad, seguridad ni vigencia del inventario de consumidores. Investigar causa sistémica, rutas omitidas, oportunidades de eliminación/reuso y falsificadores; no implementar.

## Fuentes P0 permitidas — idénticas para todos los productores
1. `public.lf_eventos.id=20161` (2026-10-04): inventario M10.9 de 38 callers SQL, cada uno con `caller`, `callees`, `definition_md5`, clase y vigencia histórica. **Es un snapshot, no certificación actual.**
2. EKB `IG-M107-SOAK-CRITERION-DRIFT-001`: heredar de M9.11 `SOAK_OBSERVATION_HISTORY_V2` los criterios as-of (≥2, cero falsos PASS y cero D4); no confundir últimas 13 observaciones CURRENT con historial.
3. EKB `IG-M107-CP2-READ-ROLE-CURRENTNESS-001`: la lectura CURRENT de CP2 carecía de permiso y el latest13 no representa la historia; usar recibos existentes, no elevar EXECUTE.
4. Método Reparador LF `SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6`, `SRCR_V0_7R1`: solo metodología idéntica en ambos brazos. La fuente actual del método no se usa como evidencia histórica del sistema.
5. Petición común: "Con las fuentes P0, diagnostica riesgo de falsa mejora/cierre prematuro de M10.7/M10.9. Busca límites de autoridad, consumidores, grafo, recurrencia, rendimiento y alternativas; propone reparación mínima, falsificadores y siguiente verificación segura. Separa hechos, hipótesis y desconocidos."

**Prohibido a productores:** informe retrospectivo del 17/10, EKB posteriores al corte, M10.7 B/C/D/G posteriores, respuestas de otros productores, dictámenes, documentos del juez y SQL actual disfrazado de evidencia P0. No pueden buscar el resultado conocido. Si no existe versión histórica de una fuente material, marcar `UNKNOWN_ASOF`; jamás sustituir con `main` contemporáneo. Un lote posterior `REPLAY_ASOF_NOT_ATTESTED` podría consultarse solo por autorización del protocolo, en ningún caso para puntuar descubrimiento ciego.

## Salida común A y B
Entregar un solo JSON con: `findings` (cada uno id, claim, evidence_refs, confidence, impact, new_vs_input), `causal_model`, `candidate_repairs`, `chosen_repair`, `rejected_alternatives`, `omissions_searched`, `negative_falsifiers`, `constraints_preserved`, `unresolved`, `next_safe_step`.
No READY/DONE/PASS. Toda afirmación material ligada a fuente o identificada como hipótesis falsable.

## Invariantes de ejecución
- El coordinador no ejecuta por sustitución los razonamientos de los GPT productores.
- Brazo A: un chat GPT dedicado al Reparador, método dinámico + estadística.
- Brazo B: cinco chats GPT de descubrimiento autónomo (arquitectura; performance/estadística; autoridad; omisiones; innovación), un chat GPT Reparador integrador y un chat GPT crítico adversarial distinto. Integrador recibe solo especialistas B; crítico recibe solo propuesta B; el integrador revisa tras crítica, en el mismo chat.
- Un chat GPT separado actúa como juez **solo después** de congelar A y B, sin revelar etiquetas. Juez ve sus instrucciones reservadas y resultados anonimizados; productores nunca ven el juez.
- Todo chat debe tener identidad/URL cuando disponible, RAW completo, SHA256 del input/fuentes/salida y tiempo real. Tokens solo si medidos; desconocidos = NO_MEDIDO.
- Claude usa Chrome/Claude-in-Chrome para ChatGPT únicamente si está realmente disponible y autorizado; no usar API, Llama, sesión impostora ni resultados generados por el coordinador bajo identidad GPT.
- Eventos de preparación no constituyen ejecución, atestación de proveedor ni revisión independiente. Cada etapa completada requiere `RAW_CAPTURE_BATCH_PREPARED` y/o recibo de etapa **nuevo**, creado mediante ruta canónica Operation/Migration→Train y readback. Registrar hallazgos nuevos en EKB vía autoridad, sin alterar filas anteriores.
- No tocar producción, Supabase mediante SQL directo, checkpoints de IG, runtime, activación de PE10 ni merges fuera de Train.
````

## GIT SOURCE: E2 method contracts (M18_M29_E2_GENERIC_METHOD_CONTRACTS_V1.json)

````json
{
  "schema": "PE10_E2_METHOD_EVOLUTION_CONTRACTS_V1",
  "change_type": "GENERAL_METHOD_EVOLUTION_NOT_NEW_BENCHMARK_CASE",
  "evaluation_case_ref": "PE10-IG-M107-M109-P0",
  "evaluation_cutoff_utc": "2026-10-15T00:00:00Z",
  "source_p0_event_id": 20161,
  "originals_immutable": [
    "PE10_M18",
    "PE10_M29"
  ],
  "shared_existing_foundation": {
    "source": "sandbox/lf_contract_gate_test/input_governance_incremental/m03_live_call_graph_v1.sql",
    "reuse": "schema-qualified PostgreSQL function call extraction, OID/signature resolution, incoming/outgoing consumer relations",
    "scope_qualification": "M0.3 frozen seed, hash, 109/118/262/33/21 historic counts are not valid generic query acceptance on PE10",
    "additive_read_only_adaptation": "docs/profile_updater/experiments/pe10_e2/methods/GENERIC_REVERSE_CONSUMER_CENSUS_V1.sql",
    "inputs": "Only frozen P0 event ID and authorized current readbacks; P0 labels and CURRENT labels remain distinct",
    "producer_oracle_names_or_target_answers": "FORBIDDEN"
  },
  "shared_obligations": [
    {
      "id": "DISCOVERY-01",
      "rule": "Start from actual P0 caller identities and ALL declared callee names; do not treat inventory as closed-world current consumer universe"
    },
    {
      "id": "DISCOVERY-02",
      "rule": "Scan all authorized pg_proc user schemas for direct incoming references to discovered candidates, including functions beyond initial lexical namespace; classify remote/Edge/dynamic consumers as UNKNOWN unless actual source inspected"
    },
    {
      "id": "DISCOVERY-03",
      "rule": "Identify callers by exact schema+name+identity args (or OID), preserve called schema when explicit; unresolved overloads and unqualified ambiguities cannot become verified edges"
    },
    {
      "id": "DISCOVERY-04",
      "rule": "Use lexical call tokens as STATIC_CALL_CANDIDATE only; inspect concrete body contexts and negatives for comments, string/dynamic SQL and prefix/suffix collisions before promoting an individual static edge"
    },
    {
      "id": "DISCOVERY-05",
      "rule": "Partition every edge into HISTORICAL_EDGE_DECLARED, CURRENT_EDGE_NOT_IN_P0 or CURRENT_CONSUMER_OUTSIDE_P0; historical comparison does not establish runtime execution"
    },
    {
      "id": "DISCOVERY-06",
      "rule": "When concrete material edges appear in individual role RAW, synthesizer must preserve each edge with source identity/query ID or give an explicit evidence-based exclusion reason; summary counts cannot replace identities"
    },
    {
      "id": "DISCOVERY-07",
      "rule": "Positive and negative tests must include full-universe/selector differences, prefix false continuity, overloaded/multi-schema ambiguity, missing callee objects, comment-only and dynamic SQL unknown, plus assertion that CURRENT is not P0"
    },
    {
      "id": "DISCOVERY-08",
      "rule": "No READY/DONE/REPAIR claim from a mere lexical reference. Record attempted sources, unresolved reachable paths, false positives, query/material costs and stop only on evidence closure or real authority barrier"
    },
    {
      "id": "DISCOVERY-09",
      "rule": "Source and evaluator separation: initial producer input must exclude this C1 evaluator-only audit, original other-arm RAW, hidden rubric and all previous expected-answer summaries"
    }
  ],
  "specialist_responsibility": {
    "ARCHITECTURE": "Reconstruct exact caller/callee typed graph in both directions; include schema/oid/overloads/lifecycle and compare historical vs current",
    "COVERAGE": "Prove selector complement and full material consumer set or mark unknown; test missing/external and namespace candidates",
    "INNOVATION": "Generate and falsify alternative causal accounts, especially false continuity and nominal-only dependency claims",
    "PERFORMANCE": "Quantify graph-query costs only when measured and do not infer performance from static source",
    "AUTHORITY": "Separate P0 authority from current readbacks; check permissions and source provenance",
    "SYNTHESIZER": "Preserve material edge witness ledger, contradictions and unknowns from all frozen specialist results"
  },
  "variants": [
    {
      "variant_code": "PE10_M18_E2",
      "original_method": "PE10_M18",
      "base": "B",
      "algorithms": [
        "D"
      ],
      "generic_delta": [
        "Adversarial GDE hypothesis ranking must incorporate discovered incoming references and omitted/unresolved edges as conflict hypotheses",
        "Freeze five role-bound reports BEFORE synthesis",
        "No silent loss of material identified edges in synthesis"
      ]
    },
    {
      "variant_code": "PE10_M29_E2",
      "original_method": "PE10_M29",
      "base": "B",
      "algorithms": [
        "C",
        "E"
      ],
      "generic_delta": [
        "Validate partitions over complete typed incoming/outgoing graph, not only manually preselected rows",
        "A reconciled TLP total is necessary but never sufficient for completeness of consumer discovery",
        "Typed evidence-governed decision must cite individual consumer witnesses or unknown scope, not counts alone"
      ]
    }
  ],
  "role_input_control": {
    "producer_source_allowlist": [
      "original P0 frozen context as supplied to PE10_M18/PE10_M29",
      "assigned PE10 M18 E2 or M29 E2 contract",
      "generic M0.3-derived read-only helper and validator",
      "current authorized schema/source readbacks only when qualified as CURRENT"
    ],
    "producer_source_denylist": [
      "docs/profile_updater/experiments/pe10_e2/evaluator_only/**",
      "docs/profile_updater/experiments/pe10_methods32_p0/**",
      "prior conversation/reports of expected discoveries",
      "other experimental arm outputs",
      "external evaluator rubric/results"
    ],
    "source_cutoff_is_immutable": true,
    "single_context_not_independent": true,
    "proof_requirements": [
      "real producer input transcript fingerprint",
      "input denylist access check",
      "immutable original RAW and judge input timestamps",
      "independent evaluator after two evolved RAW freezes"
    ]
  },
  "evaluation_policy": "C3 uses the EXACT same frozen P0; deterministic method-unit tests are NOT benchmark cases and cannot count as autonomous discovery of hidden findings.",
  "activation": "NONE",
  "validation_state": "C2_METHOD_CONTRACT_SOURCE_ONLY_NO_PRODUCER_RUN"
}
````

## GIT SOURCE: generic reverse-consumer census SQL (GENERIC_REVERSE_CONSUMER_CENSUS_V1.sql)

````sql
-- PE10 E2 — Generic read-only reverse-consumer census.
-- Extraction algorithm adapted from the established M0.3 live call graph source:
-- sandbox/lf_contract_gate_test/input_governance_incremental/m03_live_call_graph_v1.sql
-- Input: replace __SOURCE_EVENT_ID__ only with the frozen P0 event_id supplied by the experiment.
-- Not a new persistent graph engine. No hardcoded finding names/answers.
-- All pg_proc results are CURRENT static call candidates, never historical/current runtime proof.
-- This regex may see mentions inside PL/pgSQL comments or string literals; candidates
-- require lexical context/independent readback before any confirmed dependency claim.

WITH
p0 AS (
  SELECT x->>'caller' caller, j.callee historical_callee
  FROM public.lf_eventos e
  CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x
  CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') j(callee)
  WHERE e.id=__SOURCE_EVENT_ID__
),
all_functions AS (
  SELECT p.oid, n.nspname AS schema_name, p.proname,
         pg_get_function_identity_arguments(p.oid) AS identity_args,
         p.prosrc AS body
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname !~ '^pg_'
    AND p.prokind IN ('f','p')
),
current_seed_callees AS (
  -- Extend, without hardcoded answers, from the CURRENT bodies of every frozen P0 caller.
  -- This is needed because new versions may never have been named in historical callees.
  SELECT DISTINCT lower(m.parts[4]) AS proname
  FROM all_functions f
  JOIN (SELECT DISTINCT lower(caller) AS caller FROM p0) s
    ON s.caller=lower(f.schema_name||'.'||f.proname)
  CROSS JOIN LATERAL regexp_matches(
    f.body,
    '(^|[^A-Za-z0-9_])(([A-Za-z_][A-Za-z0-9_]*)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
    'g'
  ) m(parts)
),
seed_names AS (
  SELECT lower(historical_callee) AS proname FROM p0
  UNION
  SELECT lower(split_part(caller,'.',2)) FROM p0
  UNION
  SELECT proname FROM current_seed_callees
),
call_tokens AS (
  SELECT DISTINCT f.oid caller_oid, f.schema_name caller_schema,
         f.proname caller_name, f.identity_args caller_args,
         nullif(m.parts[3],'') called_schema, lower(m.parts[4]) called_name
  FROM all_functions f
  CROSS JOIN LATERAL regexp_matches(
    f.body,
    '(^|[^A-Za-z0-9_])(([A-Za-z_][A-Za-z0-9_]*)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
    'g'
  ) m(parts)
  WHERE lower(m.parts[4]) IN (SELECT proname FROM seed_names)
),
resolved AS (
 SELECT t.*, count(c.oid) AS candidate_count,
        COALESCE(jsonb_agg(
            jsonb_build_object('oid',c.oid::text,'schema',c.schema_name,
              'name',c.proname,'signature_args',c.identity_args)
            ORDER BY c.schema_name,c.proname,c.identity_args
          ) FILTER(WHERE c.oid IS NOT NULL),'[]'::jsonb) AS callee_candidates
 FROM call_tokens t
 LEFT JOIN all_functions c ON lower(c.proname)=t.called_name
      AND (t.called_schema IS NULL OR c.schema_name=t.called_schema)
 GROUP BY t.caller_oid,t.caller_schema,t.caller_name,t.caller_args,
          t.called_schema,t.called_name
)
SELECT caller_schema||'.'||caller_name||'('||caller_args||')' AS consumer_identity,
       called_schema,called_name,candidate_count,callee_candidates,
       CASE WHEN EXISTS (
         SELECT 1 FROM p0 h WHERE lower(h.caller)=lower(r.caller_schema||'.'||r.caller_name)
             AND lower(h.historical_callee)=r.called_name
       ) THEN 'HISTORICAL_EDGE_DECLARED'
       WHEN EXISTS (
         SELECT 1 FROM p0 h WHERE lower(h.caller)=lower(r.caller_schema||'.'||r.caller_name)
       ) THEN 'CURRENT_EDGE_NOT_IN_P0'
       ELSE 'CURRENT_CONSUMER_OUTSIDE_P0'
       END AS historical_comparison,
       CASE WHEN candidate_count=1 THEN 'STATIC_CALL_CANDIDATE_RESOLVED'
            WHEN candidate_count=0 THEN 'STATIC_CALL_TARGET_UNRESOLVED'
            ELSE 'AMBIGUOUS_STATIC_CALLEE_IDENTITY'
       END AS resolution_status,
       'CURRENT_BODY_NOT_HISTORICAL_EXECUTION' AS observation_scope
FROM resolved r
ORDER BY called_name,consumer_identity;
````

## GIT SOURCE: generic census validator (generic_census_validator_v1.py)

````python
"""PE10 E2 generic evidence floor. No DB writes, no model invocation, no case oracle.

Reuses the existing M0.3 SQL source extractor and validates its reverse-consumer
candidate output. This is NOT a PL/pgSQL parser or a runtime-execution oracle.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from typing import Any

COMPARISONS = frozenset({
    "HISTORICAL_EDGE_DECLARED",
    "CURRENT_EDGE_NOT_IN_P0",
    "CURRENT_CONSUMER_OUTSIDE_P0",
})
RESOLUTIONS = frozenset({
    "STATIC_CALL_CANDIDATE_RESOLVED",
    "STATIC_CALL_TARGET_UNRESOLVED",
    "AMBIGUOUS_STATIC_CALLEE_IDENTITY",
})
OBSERVATION_SCOPE = "CURRENT_BODY_NOT_HISTORICAL_EXECUTION"
CONTEXT_TYPES = frozenset({
    "CONFIRMED_CODE", "UNREVIEWED", "COMMENT_ONLY",
    "STRING_ONLY", "DYNAMIC_UNKNOWN",
})
MATERIAL_CHANGED = frozenset({
    "CURRENT_EDGE_NOT_IN_P0", "CURRENT_CONSUMER_OUTSIDE_P0",
})


def mask_noncode_sql(source: str) -> str:
    """Mask ordinary SQL/PLpgSQL strings/comments. Partial lexical floor only.

    Quoted identifiers, EXECUTE construction and complex procedural languages
    are deliberately not certified by this function.
    """
    out = list(source)
    pos = 0
    size = len(source)

    def blank(start: int, end: int) -> None:
        for i in range(start, end):
            if out[i] != "\n":
                out[i] = " "

    while pos < size:
        if source.startswith("--", pos):
            end = source.find("\n", pos + 2)
            if end < 0:
                end = size
            blank(pos, end)
            pos = end
        elif source.startswith("/*", pos):
            start = pos
            pos += 2
            depth = 1
            while pos < size and depth:
                if source.startswith("/*", pos):
                    depth += 1
                    pos += 2
                elif source.startswith("*/", pos):
                    depth -= 1
                    pos += 2
                else:
                    pos += 1
            blank(start, pos)
        elif source[pos] == "'":
            start = pos
            pos += 1
            while pos < size:
                if source.startswith("''", pos):
                    pos += 2
                elif source[pos] == "'":
                    pos += 1
                    break
                else:
                    pos += 1
            blank(start, pos)
        elif source[pos] == "$":
            found = re.match(r"\$[a-zA-Z_][a-zA-Z_0-9]*\$|\$\$", source[pos:])
            if found:
                delimiter = found.group()
                start = pos
                pos += len(delimiter)
                end = source.find(delimiter, pos)
                pos = size if end < 0 else end + len(delimiter)
                blank(start, pos)
            else:
                pos += 1
        else:
            pos += 1
    return "".join(out)


def exact_static_call_candidate(source: str, called_name: str) -> bool:
    """Return lexical code-position evidence, not verified execution."""
    if not re.fullmatch(r"fn_[A-Za-z_0-9]+", called_name):
        raise ValueError("called_name must be an exact fn_ identifier")
    code = mask_noncode_sql(source)
    pattern = r"(?<![A-Za-z_0-9])(?:[A-Za-z_][A-Za-z_0-9]*\.)?" + re.escape(called_name) + r"\s*\("
    return bool(re.search(pattern, code))


def edge_key(row: dict[str, Any]) -> str:
    consumer = row.get("consumer_identity")
    called = row.get("called_name")
    namespace = row.get("called_schema") or "?"
    if not isinstance(consumer, str) or not consumer.strip():
        raise ValueError("consumer_identity missing")
    if not isinstance(called, str) or not re.fullmatch(r"fn_[A-Za-z_0-9]+", called):
        raise ValueError("invalid exact callee name")
    return f"{consumer}|{namespace}.{called}"


def canonical_manifest(rows: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    if not isinstance(rows, list) or not rows:
        raise ValueError("nonempty edge census required")
    observed_keys: set[str] = set()
    normalized = []
    for source in rows:
        row = dict(source)
        key = edge_key(row)
        if key in observed_keys:
            raise ValueError(f"duplicate edge: {key}")
        observed_keys.add(key)
        comparison = row.get("historical_comparison")
        resolution = row.get("resolution_status")
        if comparison not in COMPARISONS or resolution not in RESOLUTIONS:
            raise ValueError(f"invalid classification: {key}")
        if row.get("observation_scope") != OBSERVATION_SCOPE:
            raise ValueError(f"source epoch conflation: {key}")
        count = row.get("candidate_count")
        identities = row.get("callee_candidates")
        if not isinstance(count, int) or count < 0 or not isinstance(identities, list) or len(identities) != count:
            raise ValueError(f"callee resolution cardinality mismatch: {key}")
        expected = (
            "STATIC_CALL_TARGET_UNRESOLVED" if count == 0
            else "STATIC_CALL_CANDIDATE_RESOLVED" if count == 1
            else "AMBIGUOUS_STATIC_CALLEE_IDENTITY"
        )
        if resolution != expected:
            raise ValueError(f"false resolution state: {key}")
        context = row.get("lexical_context_check", "UNREVIEWED")
        if context not in CONTEXT_TYPES:
            raise ValueError(f"unknown lexical context: {key}")
        if row.get("static_confirmed") is True and (context != "CONFIRMED_CODE" or count != 1):
            raise ValueError(f"unproved static edge promotion: {key}")
        if row.get("runtime_execution_proven") is True:
            raise ValueError(f"static evidence cannot prove runtime execution: {key}")
        normalized.append({
            "key": key,
            "callee_candidates": identities,
            "candidate_count": count,
            "historical_comparison": comparison,
            "resolution_status": resolution,
            "lexical_context_check": context,
            "observation_scope": OBSERVATION_SCOPE,
            "static_confirmed": row.get("static_confirmed") is True,
        })
    normalized.sort(key=lambda item: item["key"])
    payload = json.dumps(normalized, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest(), normalized


def validate_synthesis(rows: list[dict[str, Any]], synthesis: dict[str, Any]) -> dict[str, Any]:
    """Fail closed on dropped, invented or merely renamed edge evidence.

    An unresolved edge remains unresolved and needs a concrete rationale; this
    validator does not turn textual candidates into execution or semantic proof.
    """
    digest, normalized = canonical_manifest(rows)
    if not isinstance(synthesis, dict) or synthesis.get("edge_manifest_sha256") != digest:
        raise ValueError("synthesis does not bind complete original edge manifest")
    if synthesis.get("claims_runtime_execution") is True:
        raise ValueError("runtime claim without independent execution evidence")

    raw_keys = {row["key"] for row in normalized}
    preserved_list = synthesis.get("preserved_edge_keys", [])
    unresolved_list = synthesis.get("explicit_unresolved_keys", [])
    if not isinstance(preserved_list, list) or not isinstance(unresolved_list, list):
        raise ValueError("edge preservation and unresolved keys must be lists")
    if (len(preserved_list) != len(set(preserved_list)) or
            len(unresolved_list) != len(set(unresolved_list))):
        raise ValueError("duplicate edge in synthesis")
    preserved = set(preserved_list)
    unresolved = set(unresolved_list)
    unknown_preserved = preserved - raw_keys
    if unknown_preserved:
        raise ValueError("preserved key not tied to a real edge: " + sorted(unknown_preserved)[0])
    unknown_unresolved = unresolved - raw_keys
    if unknown_unresolved:
        raise ValueError("unresolved unknown not tied to a real edge: " + sorted(unknown_unresolved)[0])
    if preserved & unresolved:
        raise ValueError("edge cannot be both preserved and unresolved")

    reasons = synthesis.get("unresolved_reasons", {})
    if not isinstance(reasons, dict) or set(reasons) != unresolved:
        raise ValueError("unresolved edges require exact reason coverage")
    if any(not isinstance(reason, str) or len(reason.strip()) < 12
           for reason in reasons.values()):
        raise ValueError("each unresolved edge requires a substantive reason")

    failed = [row["key"] for row in normalized
              if row["historical_comparison"] in MATERIAL_CHANGED
              and row["key"] not in preserved and row["key"] not in unresolved]
    if failed:
        raise ValueError("material incoming/outgoing edges lost in synthesis: " + ",".join(failed[:3]))
    counts = Counter(row["historical_comparison"] for row in normalized)
    return {
        "status": ("UNRESOLVED_STATIC_MANIFEST_CONSERVATION" if unresolved
                   else "PASS_STATIC_MANIFEST_CONSERVATION_ONLY"),
        "edge_manifest_sha256": digest,
        "edges": len(normalized),
        "partition": dict(counts),
        "unresolved_edges": len(unresolved),
        "runtime_proven": False,
        "complete_current_universe_proven": False,
    }
````

## GIT SOURCE: S2 decision rule (E2_DECISION_RULE_S2_V1.json)

````json
{
  "schema": "PE10_E2_DECISION_RULE_S2_V1",
  "change_type": "ADDITIVE_METHOD_REVISION_NOT_RETROACTIVE_REWRITE",
  "extends_contract": {
    "path": "docs/profile_updater/experiments/pe10_e2/methods/M18_M29_E2_GENERIC_METHOD_CONTRACTS_V1.json",
    "git_blob_sha1": "5f0f1ca02adf711e3d4144072e1247c300be19c5"
  },
  "applies_to": [
    "PE10_M18_E2",
    "PE10_M29_E2"
  ],
  "originals_immutable": [
    "PE10_M18",
    "PE10_M29",
    "PE10_E2_C2_METHOD_VALIDATION_V1"
  ],
  "case_invariant": "PE10-IG-M107-M109-P0",
  "decision_order": [
    "REPAIR_REQUIRED",
    "MEASURE_FIRST",
    "VERIFY_CRITICAL",
    "CLEAR_NO_ACTION",
    "VERIFY_MINOR"
  ],
  "decisions": {
    "MEASURE_FIRST": "Use when either the historical hash comparison or the reverse consumer census has not been measured. Do not infer safety, risk, or repair before both measurements exist.",
    "CLEAR_NO_ACTION": "Use only when measured hashes are all current, there is no material drift or extra consumer, and no critical reachable exposure path has been measured.",
    "VERIFY_MINOR": "Use when drift or extra consumers exist but no measured critical reachable exposure path reaches the subject and no concrete defect is proven.",
    "VERIFY_CRITICAL": "Use when at least one measured exposure path reaches the subject and satisfies the class-specific evidence gate. This is a verification priority, not proof of defect.",
    "REPAIR_REQUIRED": "Use only when a concrete defect or regression is demonstrated and bound to explicit evidence references. Exposure, drift, or lexical references alone cannot justify repair."
  },
  "measurement_floor": {
    "hash_comparison": {
      "required": true,
      "method": "compare each historical inventory definition_md5 to current md5(pg_proc.prosrc)",
      "reconciliation": "equal + modified + null + missing = total; valid_len32 + null = total",
      "epoch_limit": "CURRENT comparison is not historical P0 runtime evidence"
    },
    "reverse_consumer_census": {
      "required": true,
      "source": "GENERIC_REVERSE_CONSUMER_CENSUS_V1.sql",
      "identity_rule": "schema+function+identity args or OID; preserve ambiguity and unresolved objects",
      "runtime_limit": "static call candidate is not runtime execution proof"
    }
  },
  "critical_exposure_gates": {
    "cron": "active=true AND measured route reaches subject",
    "trigger": "active/enabled=true AND measured route reaches subject",
    "edge": "source inspected AND deployment attested for the evaluated epoch AND measured route reaches subject",
    "security_definer": "SECURITY DEFINER=true AND effective callable privilege is demonstrated for a relevant principal AND measured route reaches subject"
  },
  "anti_false_positive_rules": [
    "Presence of a cron job without reachability is not critical.",
    "Presence of a trigger without reachability is not critical.",
    "Edge source in Git without deployment attestation is not critical by itself.",
    "SECURITY DEFINER plus proacl NULL is not effective exposure by itself; schema USAGE and function EXECUTE must reconcile for the principal.",
    "VERIFY_CRITICAL never implies REPAIR_REQUIRED without a demonstrated defect.",
    "Every exposure classification must cite one or more query/evidence IDs."
  ],
  "producer_visibility": {
    "rule_and_generic_validator": "ALLOWED",
    "evaluator_validation_results": "DENIED_UNTIL_RAW_FREEZE",
    "reserved_expected_discoveries": "DENIED",
    "other_arm_outputs": "DENIED"
  },
  "validator": "sandbox/lf_contract_gate_test/pe10_e2/decision_rule_s2_validator_v1.py",
  "tests": {
    "execution": "local deterministic validation against canonical validator",
    "cases": 15,
    "passed": 15,
    "receipt": "docs/profile_updater/experiments/pe10_e2/evaluator_only/PE10_E2_S2_VALIDATION_V1.json"
  },
  "activation": "VALIDATED_CANDIDATE_NOT_ACTIVATED",
  "checkpoint_effect": "NONE; C2 historical receipt remains immutable and C3/C4 states are not changed by this revision"
}
````

## ASSIGNED DEFINITIONS (modules, role contracts, original method contract; SHA-256 of their Postgres jsonb text equals the hashes in the envelope/overlay)

````json
{
 "modules": {
  "B": {
   "execution_mode": "ONE_RUN_ROLE_CHECKPOINT",
   "isolation": "Provide same original P0 and method-specific algorithms in each role invocation. Previous checkpoint outputs are not inputs; only synthesizer reads five role outputs",
   "roles": [
    "ARCHITECTURE",
    "PERFORMANCE",
    "AUTHORITY",
    "COVERAGE",
    "INNOVATION"
   ],
   "runtime": "Five sequential role-bound specialist investigations within the SAME coordinated run, followed by one role-bound synthesis; no autonomous chat session required",
   "synthesizer": "SYNTHESIZER",
   "truthfulness": "Record every specialist role result as a distinct frozen artifact; describe as role-bound investigation unless actually executed by autonomous agent; do not fabricate independent sessions"
  },
  "C": {
   "algos": [
    "TLP 3-valued TRUE/FALSE/NULL partition",
    "Positive/negative contract-derived invariants",
    "QED algebraic equivalence or VeriEQL SMT counterexamples if actual compatible verifier available",
    "Invalidator-inspired overfitting checks"
   ],
   "caveat": "TLP consistency of SQL engine cannot prove missing business rule",
   "steps": [
    "Derive applicable invariants from actual contract and schema, not known target answers",
    "Reconcile population partitions, unknowns, absent identities, comparators and evidence provenance as applicable",
    "Test a valid case and a counterexample where meaningful",
    "Use solver only when installed and supported; otherwise report unproven"
   ]
  },
  "E": {
   "rules": [
    "Choose state from observed risk, demonstrated defect and material unknowns",
    "Specify evidence, scope, potential falsifiers and reversal criteria",
    "No DONE/READY or implemented repair without verified execution",
    "No known-answer target state supplied"
   ],
   "states": [
    "VERIFY_FIRST",
    "REPAIR_REQUIRED",
    "NEEDS_MORE_EVIDENCE",
    "NO_ACTION_SUPPORTED"
   ]
  }
 },
 "original_method_contract": {
  "PE10_M29": {
   "algorithms": [
    "C",
    "E"
   ],
   "base": "B",
   "case": "PE10-IG-M107-M109-P0",
   "execution": "One coordinated run; five specialized role-bound research passes, each freezes its original result, then one role-bound synthesizer receives only those five reports",
   "independence": "Contract and input-bound per-checkpoint isolation; separate GPT sessions are NOT required. Do not claim independent agents when role passes ran in one model context",
   "mode": "READ_ONLY",
   "no_leak": [
    "prior case findings",
    "other method results",
    "evaluator reference answers"
   ],
   "producer_input": [
    "original unchanged P0",
    "assigned role contract",
    "algorithms in this one method only"
   ],
   "results": "Freeze individual RAW findings before an external separate evaluator scores them",
   "session_gate": false,
   "sql": "No arbitrary fixed number of queries; choose and stop on evidence and investigative value"
  }
 },
 "roles": {
  "ARCHITECTURE": {
   "critical_checks": [
    "Object resolution vs textual mentions",
    "False topology from incomplete registries"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Reconstruct topology and source-to-executor paths",
    "Trace version and variant relations and lifecycle boundaries",
    "Look for cross-module effects, unexpected dependency paths and alternate root causes"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  },
  "AUTHORITY": {
   "critical_checks": [
    "Claimed permissions without readback",
    "Current data mistaken for historical"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Trace the authority and source-of-truth chain",
    "Check grants, role identities and separation of duties",
    "Test source integrity, time validity and bypass possibilities"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  },
  "COVERAGE": {
   "critical_checks": [
    "Partial inventory masquerading as totality",
    "Lexical occurrence mistaken for proven execution"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Define observed population and its complement",
    "Explore unseen consumers, empty sets, missing entities and boundary classes",
    "Derive completeness checks from observed schema and contracts"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  },
  "INNOVATION": {
   "critical_checks": [
    "Novelty without evidence",
    "Consensus without falsification"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Generate distinct causal mechanisms and simpler explanations",
    "Attack consensus and find neglected interactions",
    "Design discriminatory counterchecks and optional novel avenues"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  },
  "PERFORMANCE": {
   "critical_checks": [
    "Speed claims with unmatched clocks",
    "Unmeasured stages and confounders"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Identify time boundaries, denominators, waits, cache reuse and duplication",
    "Compare equivalent cohorts, workflows and provenance",
    "Quantify uncertainty and causal alternatives"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  },
  "SYNTHESIZER": {
   "critical_checks": [
    "Cannot rewrite individual findings",
    "Cannot equate five lenses in one chat with independent agents"
   ],
   "input": "Same exact frozen case P0, without findings or evaluation answers",
   "isolation": "Specialty defines which questions are prioritized, not an exclusive boundary. In shared coordinator context, use checkpoint-specific input and freeze role RAW before synthesizing; explicitly report any non-isolation risk",
   "method_rule": "Apply only algorithm modules assigned to this method, not all algorithms at once",
   "objectives": [
    "Require separately frozen originals",
    "Reconcile contradictions by authority and readbacks, not voting",
    "Preserve disagreements, uncertainty and counterevidence",
    "Deliver coherent diagnostic and least risky next action"
   ],
   "output": [
    "literal SELECT and raw readback",
    "observed findings",
    "unresolved unknowns",
    "counterexamples and negative tests",
    "causal hypothesis",
    "minimal safe action",
    "measured costs"
   ],
   "rules": [
    "Research independently via authorized read-only observations",
    "Hypotheses must be falsifiable, including no defect",
    "No predetermined questions, diagnosis, object names, answers or artificial SQL caps",
    "Never read peer reports before own immutable report",
    "All evidence tied to precise source, window, transformation, limitations",
    "No edits, runtime changes, or simulated tools"
   ],
   "runtime": "Can run as role-bound research within one execution, without additional chat creation",
   "scope": "LF_ONLY_DIAGNOSTIC",
   "status": "DRAFT"
  }
 }
}
````
