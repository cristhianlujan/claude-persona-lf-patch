# L32 — Manifiesto de entrega documental y límites de verificación

**Lote: solo documentos/SQL de lectura; NO-GO técnico.** Los criterios `G01/G02` no se cierran con estas plantillas. Fuente: EKB `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4` (candidato parcialmente verificado), L28 documento 12 y evidencia L31.

## Fuentes efectivamente releídas
- L28 rama `lf/issue-3779-lote28-blocker-closure-plan-v1`, base exacta al crear L32: `fccf9be511bdf6f0a56c9770f8c7c47d38e267e3`.
- L28 `12_criterios_cierre_motor_7.md` blob `130d474921e0ad010e94a645a8f350f3ca86e611`; L28 tablero 04 y ruta 15, recibos originales B02 y B03 **no alterados**.
- L31 rama `lf/issue-3779-lote31-b02-b03-readonly-pg18-evidence-v1` HEAD `91eed67ec8d25ebb8eb4a2fbc7d6664f19c202af`; reporte 11 y manifiesto 12, R01 L19 blob `d0885393fe987c723f39f464b007d4c489029540`.
- L31 cut B02 234 RUN (232 históricos presentes), B03 los mismos 234; hashes canónicos B02 `d14568937e82995b0c141cd8be75bc7091fb0076164933209e0c616b1d564acc` y B03 `ec233aa608d66167f9a0206cac3f4db9d0e40167fbf6daf15437b06e8ea3b60f`. CI PG18.7 `43386747597` 16/16 PASS, **sin cerrar criterios**.

## Archivos NUEVOS y propósito
1. `01_paquete_decision_dueno_cohorte.md`: alternativas 32 vs universo, riesgos, recomendación, decisión sin firmar.
2. `02_plantilla_G01_SCOPE_FREEZE_RECEIPT.md`: recibo G01 **NO EMITIDO** con decisión, fuente, corte, SHA, 61 PR, negativos, custodia y readback.
3. `03_plantilla_EFFECT_RECON_RECEIPT.md`: por cada RUN, efecto esperado/real, sinks, hash, causalidad, negativos; **NO EMITIDO**.
4. `04_plantilla_LIVENESS_RECEIPT.md`: por RUN, lease/fence/heartbeat/worker y clasificación; **NO EMITIDO**.
5. `05_freeze_cohorte_asof_readonly.sql`: transacción REPEATABLE READ READ ONLY; captura instantánea con `as_of`+MVCC; export literal, hashes y comparación posterior contra la lista congelada; delta fuera de cohorte; comparación por ID contra lista PR #3803. Los parámetros de readback `[]` son **plantillas de bloqueo**, NO son datos reales.

## Readback documental efectuado (antes de este propio manifiesto)
- Comparación Git `fccf9be...d38e267e3` → HEAD `d58f4de463f9092f01ba41d01f9700724ef58d86`: **5 commits ahead, 0 behind; 5 archivos ADDED; 0 archivos MODIFIED/REMOVED**. Solo `audits/rule-quality-lote32/**`.
- Readback desde GitHub de los 5 archivos, blobs Git: decisión `da53d1b4b534c0c38093bddd1c2f0cbeb193a60a`; G01 `d7f940f5b7c3abff86ad6edba044f2ae4505f8eb`; efectos `97b3701eb632891eac23a70fa0e8b67b377b96c8`; liveness `9ca6cd4b2bef009b887cbec9168fb93d23ca96f8`; SQL `9a015ed8b6c18c52bd642f91de32796d8c305afc`.
- Confirmación textual: las tres plantillas contienen `emission_status: NOT_ISSUED` y criterios de aceptación; SQL contiene dos transacciones `REPEATABLE READ READ ONLY` terminadas por `ROLLBACK`, sin sentencias DML/DDL según inspección textual.
- **NO probado**: ejecución SQL contra PostgreSQL, permisos reales, independencia de auditor, firma humana, READBACK de sinks/worker, recepción oficial y G01/G02. El SQL debe ser revisado/ejecutado por Operaciones autorizadas, usando **una sola sesión** para F0/F1/F2. La sola fecha `as_of` no ofrece time travel MVCC; conservar literalmente el snapshot exportado.

## Estado y siguiente paso
- L21: **BLOQUEOS 0/14 CERRADOS (0%)**; L28 Motor 0/7; B02 y B03 0/2.
- **Dueño:** decidir alcance **universo completo al corte (recomendado)** o excepción TOP32; no está firmado.
- **Operaciones:** capturar y custodiar freeze con G01; **DBA/Train:** presentar los 61 IDs con filtro y as_of; **custodios:** efectos por RUN y liveness de 8 leases; **auditor independiente:** verificar evidencia y dictamen.
- No se alteraron ramas L28/L31 ni RUN históricos; no se usó Supabase con escritura, ni se emitió recibo/GO. Cualquier futura emisión debe seguir la ruta oficial y dejar auditoría independiente.

**Este documento relata comprobaciones efectuadas, no acta de aceptación técnica.**
