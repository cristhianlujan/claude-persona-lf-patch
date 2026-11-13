# L32 — Plantilla literal LIVENESS_RECEIPT / B03

**UNA INSTANCIA POR RUN del manifiesto G01, con prioridad para los 8 leases vencidos del corte L31. NO EMITIDA.** Un lease vencido no demuestra abandono; la inexistencia de heartbeat visible no certifica inactividad.

```yaml
receipt_type: LIVENESS_RECEIPT
schema_version: L32_DOCUMENTAL_DRAFT_V1
emission_status: NOT_ISSUED
gate: G02
execution_id: null
g01_receipt_ref: null
g01_membership_sha256: null
read_as_of_utc: null
execution_status_readback: null
lease:
  lease_owner: null
  lease_fence: null
  lease_expires_at_utc: null
  evaluated_at_utc: null
  expiry_classification: UNKNOWN
  checkpoint_seq: null
worker:
  worker_identifier: null
  process_or_job_identifier: null
  worker_instance_and_environment: null
  scheduler_or_queue_ref: null
  last_heartbeat_at_utc: null
  last_heartbeat_raw_ref: null
  provider_readback_ref: null
  worker_process_state: UNKNOWN
  fencing_token_verified: null
  concurrent_execution_search_ref: null
  pending_delivery_or_ack_ref: null
effects_linkage:
  effect_recon_receipt_ref: null
  possible_side_effects_ref: null
  reserved_guards_resolution_ref: null
  idempotency_key_sha256: null
checks:
  independent_liveness_probe_ref: null
  lease_expired_worker_still_active_negative_ref: null
  two_workers_same_fence_negative_ref: null
  heartbeat_without_matching_execution_negative_ref: null
  unknown_or_missing_worker_negative_ref: null
custodian:
  service_owner_role: null
  operator_identity_and_authority_ref: null
  raw_payload_sha256: null
  signed_receipt_ref: null
  readback_auditor_ref: null
verdict: PENDING
classification: UNDETERMINED
recommended_handling: OBSERVE_ONLY
may_retry: false
may_close: false
may_compensate: false
```

## Aceptación por RUN
- [ ] Dueño del worker/servicio y su entorno identificados. Si no hubo lease, se demuestra expresamente su ausencia y ruta de ejecución, no se falsifican datos.
- [ ] Lease owner, expiración, `lease_fence`, `checkpoint_seq`, heartbeat, job/queue y ack correlacionados con **ese RUN** y snapshot real.
- [ ] Si vencido, demostrar si está **ACTIVO**, **FINALIZADO_CON_EFECTO**, **ABANDONADO_SIN_EFECTO** o **INDETERMINADO** mediante señales independientes; `INDETERMINADO` bloquea G02.
- [ ] Comprobar negativos de worker vivo con lease vencido, fence duplicado, heartbeat ajeno, reserva/dispatch pendiente y efecto sin recibo.
- [ ] Correlacionar `EFFECT_RECON_RECEIPT`, identificar custodia y firma auténtica; auditor distinto hace readback.
- [ ] No invocar worker, reintentar, forzar release, cerrar RUN ni compensar.

**Dictamen NO-GO** ante heartbeat/lease incierto, evidencia incompleta, discrepancia de fence o ausencia de custodia. La clasificación propuesta no ordena acciones: solo documenta.
