# L32 — Plantilla literal EFFECT_RECON_RECEIPT / B03_RUN_EFFECTS

**UNA INSTANCIA POR CADA RUN congelado en G01. PLANTILLA NO EMITIDA.** El número de instancias debe coincidir exactamente con el manifiesto G01 firmado, aun cuando el RUN no tenga efectos observados. Nunca asumir que ausencia de log implica ausencia de efecto.

```yaml
receipt_type: EFFECT_RECON_RECEIPT
schema_version: L32_DOCUMENTAL_DRAFT_V1
emission_status: NOT_ISSUED
gate: G02
blocker: B03_RUN_EFFECTS
g01_receipt_ref: null
g01_manifest_sha256: null
execution_id: null
operation_code: null
environment: null
read_as_of_utc: null
run_preimage:
  status: null
  entire_row_sha256: null
  steps_sha256: null
  guard_rows_sha256: null
  lease_owner: null
  lease_expires_at_utc: null
  lease_fence: null
  checkpoint_seq: null
  idempotency_key_sha256: null
  dispatch_key_sha256: null
  proposed_class_abcd: null
  reviewed_class_abcd: null
  reason_for_classification: null
scope_and_intent:
  expected_operation_and_sinks: []
  source_execution_and_parent_refs: []
  trusted_writer_invocation_refs: []
  raw_step_evidence_refs: []
effect_inventory:
  inventory_complete: null
  effects: []
  # Cada elemento DEBE incluir:
  # effect_id, effect_kind, intended_action, guard_state,
  # guard_receipt_ref, dispatch_key_sha256, idempotency_key_sha256,
  # sink_kind, sink_locator, target_id_or_pk, commit_or_tx_id,
  # before_sha256, after_sha256, sink_readback_ref, observed_status,
  # expected_vs_actual, causal_link_evidence_ref, custodian_attestation_ref
  source_without_effect_assertion_ref: null
  external_destinations_checked: []
  possible_unlogged_effects_checked: null
worker_liveness:
  liveness_receipt_ref: null
  lease_fence_consistent: null
  heartbeat_correlation_ref: null
negative_evidence:
  effect_without_receipt_check_ref: null
  succeeded_without_external_readback_check_ref: null
  duplicated_idempotency_check_ref: null
  partial_or_unknown_effect_check_ref: null
  replay_without_owner_authority_blocked_ref: null
custody_and_review:
  db_owner_attestation_ref: null
  github_or_provider_attestation_refs: []
  operations_attestation_ref: null
  independent_auditor_ref: null
  independent_readback_ref: null
  signed_receipt_ref: null
  signed_receipt_sha256: null
verdict: PENDING
safe_to_retry: false
safe_to_close: false
exceptions: []
unresolved_effects: []
```

## Aceptación por RUN
- [ ] `execution_id` pertenece exactamente al manifiesto G01; preimagen completa, paso, guard e idempotencia tienen hashes de origen y readback.
- [ ] **Cada destino** DB/GitHub/Edge/proveedor se coteja con su custodio y objeto real: PK/commit/tx, before/after SHA, resultado, recibo del escritor **y evidencia causal** del RUN. Que un PR exista no acredita el write causal.
- [ ] Guard `SUCCEEDED/RESERVED/ABANDONED` conciliado individualmente; todo `SUCCEEDED` con efecto/recibo o control negativo, ningún `RESERVED` ambiguo sin resolución.
- [ ] Idempotencia y `lease_fence` cotejados; negativos de duplicado, efecto sin recibo y persistencia no observada.
- [ ] Se adjunta `LIVENESS_RECEIPT` por RUN (especialmente 8 leases vencidos); clase A/B/C/D revisada, no inferida solo por edad.
- [ ] Custodios/DBA y auditor independiente acreditan RAW, alcance y coherencia; desconocido = `PENDING`, no `NO_EFFECT`.
- [ ] Sin replay, compensación, cierre, reanudación ni modificación de RUN. Este recibo no los autoriza.

**G02 solo puede aceptarse cuando el número de recibos individuales válidos es idéntico al de G01 y todos los efectos/desconocidos están conciliados; ningún PASS sintético ni 29/29 enlaces existentes lo sustituye.**
