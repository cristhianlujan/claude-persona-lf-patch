# L32 — Plantilla literal G01 / B02_RUN_SCOPE

**PLANTILLA SIN EMITIR.** No es recibo, firma, PASS ni aprobación. No sustituye la plantilla vacía `L28/recibos/B02_RUN_SCOPE.md`. Completar solo con RAW verificable.

```yaml
receipt_type: G01_SCOPE_FREEZE_RECEIPT
schema_version: L32_DOCUMENTAL_DRAFT_V1
emission_status: NOT_ISSUED
gate: G01
blocker: B02_RUN_SCOPE
project: LF
environment: null
supabase_project_ref: null
operation_code: null
source_contract_revision: null
source_query_ref: null
source_query_git_blob_sha: null
source_snapshot:
  as_of_utc: null
  pg_version: null
  database: null
  read_only_role: null
  isolation_level: REPEATABLE_READ_READ_ONLY
  mvcc_snapshot_literal: null
  captured_at_utc: null
cohort:
  selection_predicate_literal: null
  eligibility_exclusions_literal: null
  frozen_count: null
  distinct_id_count: null
  literal_csv_ref: null
  literal_csv_sha256_utf8: null
  membership_manifest_json_ref: null
  membership_sha256_utf8: null
  preimage_manifest_sha256_utf8: null
  id_list_sorted_lexicographically: null
  historic_232_overlap: null
  historic_missing_ids_ref: null
  priority_32_overlap: null
  new_or_outside_snapshot_delta_ref: null
pr3803_61:
  source_pr_ref: null
  source_commit: null
  as_of_utc: null
  sql_predicate_literal: null
  literal_61_ids_ref: null
  literal_61_ids_sha256: null
  intersection_ids_ref: null
  only_61_ids_ref: null
  only_cohort_ids_ref: null
  reconciliation_verdict: NOT_VERIFIED
authority:
  owner_decision_literal: null
  decision_at_utc: null
  owner_identity_mode: null
  owner_identity_verified: false
  owner_signature_or_approval_ref: null
  owner_scope_sha256: null
  custodian_name_and_role: null
  custodian_attestation_ref: null
evidence:
  raw_export_ref: null
  raw_export_sha256: null
  positive_check_refs: []
  negative_missing_id_check_ref: null
  negative_duplicate_id_check_ref: null
  negative_changed_state_check_ref: null
  negative_new_run_after_freeze_check_ref: null
  independent_readback_ref: null
  independent_auditor_identity_ref: null
  verifier_mechanism: null
  receipt_payload_sha256: null
verdict: PENDING
reasons: []
exceptions: []
signature_verification_status: NOT_VERIFIED
```

## Criterios de aceptación — todos obligatorios
- [ ] Owner **autoriza literalmente** 32 o universo completo, delimita exclusiones y aporta comprobante válido por el mecanismo vigente. Una conversación no prueba autenticación.
- [ ] Freeze de **cada ID** elegible con `as_of` real, snapshot, lista CSV, conteos, orden y SHA sobre bytes; su reproducción coteja **la lista literal**, no una consulta temporal recalculada.
- [ ] 232 RUN L19 y 32 priorizados conciliados por ID. Se explican cada falta/alta/estado distinto sin edición del RUN.
- [ ] La lectura de **61** RUN de PR #3803 trae lista, filtro SQL y `as_of`, y produce diferencia de conjuntos completa; no se exige identidad de conjuntos si realmente tenían distinto alcance.
- [ ] Negativos reproducibles: ID faltante, duplicado, cambio de estado/preimagen y alta fuera del corte **bloquean** la aceptación o se segregan como delta sin incluirse automáticamente.
- [ ] Operaciones custodia el RAW; auditor **distinto** realiza readback; identidad y ámbito de firmantes comprobados según carril aplicable.
- [ ] No se ejecutó DML/DDL ni se reintentó, cerró, reanudó o cambió RUN anterior.

**Salida permitida:** `ACCEPTED` únicamente con todos los requisitos verificables y autoridad válida; de lo contrario `PENDING/REJECTED`. `L31 B02 JSONB SHA d145... ` es referencia histórica, **no** SHA de este recibo.
