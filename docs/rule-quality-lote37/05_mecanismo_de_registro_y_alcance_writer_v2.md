# L37 — Mecanismo exacto de registro y compatibilidad V2

**Estado:** PROCEDIMIENTO CANDIDATO, SIN EJECUTAR. Cero writers, cero SQL Supabase, cero firmas verificadas. Autoridad técnica: código GitHub `supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql` leído en `main`, blob Git `e5fec99442933300478fd9ff46034a29b50e1df5`; EKB V1.4 (candidato parcialmente verificado). No se verificó en este lote que la función desplegada coincida byte a byte con el archivo de GitHub.

## A. Registro documental del bloque (no es una función SQL)
1. **Fuente inmutable:** `01_manifiesto_firma_en_bloque_v1.json`, SHA-256 **ae43acb08d1783859607921ca54d58d60da89a8dff55ee38e9da37113712e9c7** de bytes UTF-8; contiene 24 ID, ruta+ref Git exacta y SHA-256 de cada **documento fuente**, estado y precedencia de revisiones; 23 decididos pendientes de firma y 1 riesgo nuevo pendiente de aceptación.
2. **Frase única para copiar (UNA VEZ):** el contenido integral de `03_firma_unica_copiar.txt`. No modificar ni resumir antes de firmar; si cambia un ID o SHA, invalidar frase y emitir nueva revisión + nuevo hash.
3. **Futuro recibo documental:** guardar exactamente `block_id`, `manifest_sha256`, `phrase_literal`, `decision_at_utc` (hora del acto real, no inventada), `decisor='Cristhian Luján'`, `identity_mode='UNVERIFIED_CHAT_DECLARATION'`, `identity_verified=false`, `signature_record_sha256` (SHA de los bytes canónicos del recibo), `source_ref`, `actor_operational`, `readback_ref`, `superceded_refs`. Sin autenticación del humano: **no decir firma criptográfica o autoría física comprobada**.
4. **Trazabilidad:** registrar en documentación/versionado del repositorio con commit/branch/head, sin alterar documentos históricos. Si requiere persistencia en registros oficiales, será una **operación futura por la ruta gobernada** con autorización específica y evidencia/readback; nunca DML directo ni simular una función que no existe.
5. **Separación:** firma del dueño sobre recibos de Ops/DBA/auditor es **conformidad**, no evidencia de ejecución o independencia de esas partes. Conservar evidencia RAW y atestación individual de cada custodio, o mantener G01/G02 bloqueados.
6. **Salida de este lote:** DRAFT / `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. No convertir directamente a APROBADO, VIGENTE ni CERRADO por copiar una frase.

## B. ¿Qué admite el escritor V2?
El SQL verificado declara `public.lf_ig_rule_owner_decide_v2(p_parent text,p_rule text,p_source_sha256 text,p_decision jsonb)` y requiere **exactamente SEIS campos de texto** dentro de `p_decision`:

```json
{
  "codigo_regla": "B2B-RULE-AUTH-019",
  "propuesta_sha256": "<SHA256_JSONB_PATCH_EXACTO_DEL_PERFIL>",
  "veredicto": "APROBAR",
  "decisor": "Cristhian Luján",
  "fecha": "<FECHA_ISO8601_REAL_DEL_ACTO>",
  "frase_literal": "<DECISION_INDIVIDUAL_SOBRE_EL_SHA_EXACTO>"
}
```

**Esto es una plantilla, NO una orden de ejecución.** Los placeholders no son una decisión válida. `p_source_sha256` es el hash de snapshot canónico del activo o el sentinel del inexistente, **NO** SHA del documento Git ni de la fila completa; `propuesta_sha256` es SHA del `candidate_patch::jsonb::text`, no SHA UTF-8 del archivo. No mezclar hashes.

El writer verifica un parent RUN `EJECUCION_PERFIL_LF` admitido para `PERFIL-PRODUCT-DIRECTOR-LF`, `input_validate` y `output_validate` PASS, `semantic_judge` `PASS_INDEPENDENT_SEMANTIC`, propuesta RAW exacta, segregación documental proponente≠decisor, elección de pantalla y SHA de preimagen, y distingue `CREATE`, `UPDATE_CANDIDATE`, `CORRECT_VIGENTE`. Para `APROBAR`, **invoca escritor/hijo oficial y finaliza promoción/corrección en una sola transacción**. `RECHAZAR` no escribe la regla, pero registra decisión V2. No llamar a esta función desde una sesión de inspección.

| Decisión del paquete | ¿Elegible para V2? | Motivo / gate |
|---|---|---|
| `L35-OWNER-AUTH019-OPTION-A-001` → regla `B2B-RULE-AUTH-019` | **POTENCIAL, NO EJECUTABLE AHORA** | Regla CANDIDATO; requiere nueva decisión *por regla y SHA exacto*, parent elegible, contrato de política 19 reconciliado y juez independiente real. Frase de bloque no satisface 6 campos. |
| `L36-...PROFILE1-OTP...` → política central 19 | **NO** | Política, no `lf_ops.reglas` por `RULE_UPDATE_APPLY`. Requiere carril gobernado de políticas distinto y QA/Seguridad. |
| Q01–Q12, modelo de autoridad, G01, B06/B08, Train, G15, temporal | **NO** | Decisiones de alcance/negocio/infra o recibos, no decisión individual de `p_rule`. |
| B07 padre/hija, B09 nativo-juez, R01–R05 | **NO** | Cambios de especificación/aceptación de riesgo. Contratos/reglas técnicas deben ajustarse y probarse primero. |
| AUTH-002, AUTH-003, AUTH-040 de rama L33 Login | **FUERA DEL BLOQUE** | Solo patches propuestos, no decisión individual firmada del dueño. Su elegibilidad se reevalúa con el estado vigente y writer aplicable, nunca se autoaprueba. |

**Contradicción crítica B09:** un juez como instrucciones del **mismo LLM** no aporta independencia. La función V2 en GitHub exige `PASS_INDEPENDENT_SEMANTIC`; no generar un recibo falso, no bajar el gate por la firma del bloque. Sin cambio oficial de contrato verificado, B09/G12 sigue abierto.

## C. Gates y límites
- Documento y frase no son recibos de Ops/DBA/auditor; se exige autenticidad acorde al carril y readback independiente.
- La decisión B07 cambia el criterio histórico LF4/SALY5: no escribir DDL hasta especificación padre/hija, migración, consumidores, rollback y pruebas aceptadas por ruta oficial.
- Cobertura G15 **solo Motor temporal 7/7**; sus 7 cierres no están acreditados. Los otros siete bloqueos tampoco; **producción NO-GO**.
- Ningún RUN histórico cambiado, reintentado, cerrado, reanudado o aprobado en este lote; sin escritores ni SQL live.
