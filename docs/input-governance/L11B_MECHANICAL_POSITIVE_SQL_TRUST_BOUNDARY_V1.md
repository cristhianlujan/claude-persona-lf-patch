# LF — Lote 11B | Positivo mecánico y cuatro negativos pareados

**Estado:** `DRAFT/NO-GO`. Prueba aislada PostgreSQL 18.6, una transacción `BEGIN…ROLLBACK` por variante. No merge, producción, live apply, Router, segundo IG/juez/modelo ni RUN históricos. **No se modifica ninguna función ni MD5 del gate**.

## Distinción imprescindible: SI del código ≠ autoridad real
El caso **K00E813F0** y su cita `En producción, otp_code solo puede persistirse como hash` proceden del export de revisión pasada 1. El texto y veredicto ALLOW son reales como datos aportados por el dueño; SHA-256 de las 154 líneas `d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc`.

El fixture sintético de PG18 escribe un valor idéntico al que solicita la columna `rule_promotion_citation_provenance`, pero mantiene los metadatos `sandbox_fixture_provenance=MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E` y `system_attestation=false`. No es prueba de emisor, paso70 o IG auténticos, ni debe llevarse a otra base.

**Hallazgo de seguridad conocido, fuera de alcance para corregir:** `supabase/migrations/20261111235500_lf_rule_promotion_exact_citation_capture_v1.sql`:
- Línea **220** aprox. (registro): el código copia `rule_promotion_citation_provenance` desde `evidence_payload` a `source_provenance`.
- Línea **318**: `IF x.source_provenance IS DISTINCT FROM 'OFFICIAL_STEP70_VERIFIED_NATIVE_IG' THEN`.
- Línea **323**: devuelve `VERIFIED_CAPTURE_BINDING`.
- Líneas **205/281**: impide `test_only_synthetic=true`, pero en el fixture L7 el bit es `false` aunque la fila siga siendo sintética.
- **Consecuencia:** la función compara una **cadena de texto**, sin firmar ni comprobar criptográficamente el emisor de ese valor. Una identidad con capacidad de escribir `lf_operation_execution_steps` podría introducir el valor afirmativo. Este lote solo reproduce el comportamiento en PG18, sin cambiar la vulnerabilidad.

## Secuencia exigida
En PG18 aislado y con el propietario distinto del actor IG, el ensayo encadena `request → calidad determinista → IG con API stub #3682 → fuente congelada → captura L7/L8 → VERIFIED_CAPTURE_BINDING → pin caso ALLOW → IG READY_FOR_PROFILE_APPROVAL → propietario simulado L4D → APPROVED → apply → VIGENTE → readback VERIFIED → perfil retorno READY`; comprueba **0 filas remanentes** tras ROLLBACK.

| Variante | Control | Resultado esperado |
|---|---|---|
| POSITIVE | mismos hashes, caso K, propietario de prueba distinto de IG | `APPLIED / VIGENTE / READY` dentro de la transacción |
| QUOTE_TAMPER | cita cambia 1 carácter | `HUMAN_DECISION_REQUIRED`, no promoción |
| RULE_DRIFT | descripción de regla cambia tras captura, con propietario ya aprobado | `L7_EXACT_CITATION_NOT_CURRENT` |
| OWNER_EQ_IG | identidad IG en el registro de propietario | rechazo por **CHECK** canónico, previo a aprobar |
| READBACK_FAILURE | trigger sintético impide persistir VIGENTE; función **real** de readback sigue intacta | `RETRY_REQUIRED / RULE_READBACK_FAILED_NO_VIGENTE`, regla CANDIDATO |

El último caso usa únicamente un **trigger de fallo de prueba dentro de la transacción**: no sustituye ni parchea `lf_rule_promotion_rule_readback_v1`, `apply` u otra función del gate.

## Tablero 12 etapas y límites
`SANDBOX_VERIFIED`: Validator (aceptación estructural), Retorno perfil (**solo función readback**, sin transporte), Promoción (**en PG18**), VIGENTE (**en PG18**), Readback (**PG18**). `NOT_PROVEN`: Router, Perfil real, RUN oficial, IG real, Curator, Ejecución íntegra, Cierre terminal.

**Modelo:** `ChatGPT` declarado por el dueño; `OWNER_DECLARED_NOT_SYSTEM_ATTESTED`. IG/perfil/revisor pueden acreditar consistencia, no independencia.

**UNVERIFIED:** receptor oficial de IG #3682, firma/autenticación del escritor Step70, autoridad real del perfil dueño, integridad del transporte, 11/11 pasos, cierre READY terminal, PASE, reproducción del lote en banco del auditor. Estado global: **NOT_PROVEN**, siempre.

Evidencia RAW: `sandbox/lf_contract_gate_test/rule_promotion_v1/lote11b_mechanical_positive_5_variants_runtime.json`, generado y archivado exclusivamente por GitHub CI. No presentar esta prueba como recibo oficial ni como una ruta operativa de producción.
