# Mini Judge — SKILL ORQUESTADOR PIPELINE LF (ACT-0058)

Verificar antes de aceptar cualquier output del orquestador:

1. ¿Se ejecutó Router y se verificó v_lf_fuente_operativa?
2. ¿ACT-0058 está en EN_REVISION/CANDIDATO con impacto_automatico=BLOQUEADO?
3. ¿source_url pertenece a la lista de dominios autorizados?
4. ¿Se verificó deduplicación por source_url en ventana de 24h?
5. ¿Al menos un keyword objetivo fue detectado antes de avanzar el pipeline?
6. ¿capture_run_id corresponde a lf_capture_runs.status=COMPLETED?
7. ¿homolog_record_id corresponde a lf_homologated_records.homolog_status=APROBADO?
8. ¿Se verificó consumer_gate_passed=TRUE antes de KB_WRITE?
9. ¿Si hitl_required=TRUE, el pipeline fue detenido y marcado stage_current=HITL?
10. ¿retry_count no supera 3?
11. ¿updated_at fue actualizado en cada transición de stage?
12. ¿El cierre registró evento en lf_eventos?

Si cualquier respuesta es NO → RETURN_TO_ORCHESTRATOR o BLOCK_PIPELINE.

## Códigos de bloqueo

| Código | Trigger |
|---|---|
| ROUTER_VERIFICATION_FAILED | ACT-0058 ausente en v_lf_fuente_operativa |
| DEDUP_BLOCK_24H | source_url con COMPLETED en < 24h |
| OUT_OF_SCOPE_DOMAIN | Dominio no autorizado |
| NO_KEYWORD_MATCH | Sin keyword objetivo en metadata |
| CAPTURE_NOT_COMPLETED | lf_capture_runs.status != COMPLETED |
| HOMOLOG_NOT_APPROVED | homolog_status != APROBADO |
| HIGH_RISK_GATE_NOT_PASSED | risk_level=HIGH sin consumer_gate_passed |
| HITL_INTERVENTION_REQUIRED | hitl_required=TRUE detectado |
| KB_WRITE_GATE_NOT_PASSED | consumer_gate_passed=FALSE o hitl activo |
| MAX_RETRY_EXCEEDED | retry_count > 3 |
| AUDIT_TRAIL_MISSING | updated_at sin cambio tras transición |
| COMPLETION_REGISTRATION_FAILED | Falla en evento lf_eventos |

