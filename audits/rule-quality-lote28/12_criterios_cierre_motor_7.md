# L28 — Siete pruebas EXACTAS de cierre de Motor temporal

**Estado de esta especificación:** `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`; no modifica los 14 recibos vacíos, contrato desplegado, SQL ni RUN. **Siete bloqueos abiertos = 0/7.** Evidencia de PG18 o un PR no sustituye readback real. Fecha de la enmienda: 13-nov-2026, sin hora exacta acreditada.

## Definiciones de identidad y owner

**B08 temporal ≠ autenticación humana.** Toda decisión atribuida **documentalmente** a `Cristhian Luján`. Campos de decisión: `decisor`, `veredicto`, `fecha`, `frase_literal`, `codigo_regla`, `propuesta_sha256`, `source_sha256`, `parent_execution_id`, `proponente`, `decision_record_sha256`, `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`. No verificar ni declarar firma humana mediante Supabase Auth/JWT/MFA; un UUID `owner_sub` que aparezca en #3803 es **placeholder no autenticado**. El riesgo de suplantación debe etiquetarse sin ocultarlo. Esto no elimina el OIDC técnico que sea exigible al proveedor/host de Step70 o al Train, ni habilita capacidades productivas.

**B06 temporal:** `lf_activos.owner_name=LF_GOVERNANCE` como owner de activos único (NO es el texto del decisor). Base preimagen reportada: 238 activos, 83 ya con owner canónico, 155 a cambiar (144 no archivados y 11 archivados); 13 archivados totales. #3804 = guard/DEFAULT/triggers/writer; #3806 = backfill DATA y recibos. #3803 = prerequisito SQL/catálogo/owner documental. Mantener separación entre proyecto LF y SALY, sin declarar owner humano del segundo por extrapolación.

## Pruebas de cierre (ninguna ejecutada aquí)

### B02_RUN_SCOPE · G01
**Exacta:** inventariar sobre la base temporal y congelar **cada ID** del universo L21 232, identificar el subconjunto 32 o justificar nuevo universo por autoridad y as_of; SELECT R01/S21_01 actualizado, CSV IDs, hash SHA-256, estados y comparación explícita con los **61 RUN reportados en una lectura de PR #3803** (no asumir que 61 = 232). Positivo: exhaustividad y cohortes sin exclusiones silenciosas. Negativo: ID faltante/duplicado, estado cambiado o corrida posterior no se acepta. **Prohibido editar/reintentar/cerrar históricos.**
**Falta:** freeze/conciliación real + recibo de dueño/Operaciones. **PR:** no cubierto por #3803/#3804/#3806; requiere pieza de inventario/freeze L21 actualizada. **ABIERTO.**

### B03_RUN_EFFECTS · G02
**Exacta:** para el 100 % de IDs de B02, SELECT de RUN preimage/hash, estado, pasos, writes, leases, heartbeat, claves idempotentes, destino Git/DB/proveedor, clasificación A/B/C/D y ocho leases históricos vencidos revalidados. Probar que efecto real y estado coinciden y no hay replay ciego; un log ausente ≠ ausencia de efecto. Negativo: efecto sin recibo, lease vencido sin resolución o idempotencia duplicada = NO-GO.
**Falta:** EFFECT_RECON_RECEIPT + LIVENESS_RECEIPT por RUN, custodios y readback externo; depende B02. **PR:** pieza Operaciones/DBA nueva (no contenida en tres PR). **ABIERTO.**

### B06_OWNER · G03
**Exacta:** aplicar por **Train autorizado** #3803 → #3804 → #3806, con preflight y SHA de cada objeto afectado. SELECT real sobre `public.lf_activos`: población 238/238, 238 filas `owner_name='LF_GOVERNANCE'`, cero variantes, archivo 13/13 inalterado, los 155 IDs exactos convertidos y **155 recibos `APPLIED`** con before/after SHA-256 y execution_id en registrador oficial. Guardas INSERT fuerzan canónico, UPDATE con variante se rechaza, pruebas negativas stale SHA, repetición y self-approval documental. Cero RUN antiguos alterados.
**Falta:** #3803 Train+readback, #3804 guard DRAFT y rebase contra nuevo HEAD, #3806 backfill DRAFT + aplicación/readback final. CI PG18 de fixture **no cierra**. **ABIERTO.**

### B07_SCHEMA · G11
**Exacta:** SQL/catálogo de ciclo LF **4 columnas** y SALY **5** (incluida `lifecycle_state`, sin falsear SALY.`estado` VALIDADO); DDL UP/DOWN versionado, índices/constraints/RLS/consumidores, preimagen SHA por cambio, simulación PG18 y PG17.6 con muestra representativa, rollback tras datos sin pérdida, SELECT real antes/después. Conserva interfaz B04 y baseline B12, sin exigir firma integral Contenido.
**Falta:** SQL lifecycle LF4/SALY5/recibo y prueba post-datos completa (no se encuentran demostrados por #3803/#3804/#3806); #3803 solo ofrece contrato/objetos V2/V3/rollback parcial. Falta Train/readback de la ruta oficial. **ABIERTO.**

### B08_IDENTITY · G04 — criterio REESCRITO (temporal)
**Exacta:** después de #3803 por Train, realizar *una decisión documental de prueba registrada por el escritor oficial* con todos los campos citados arriba, `identity_verified=false`, literal de decisor, fecha, SHA de record, SHA preimagen/propuesta, proponente distinto, parent RUN real elegible y readback en tabla/registro. Verificar negativa para decisor distinto, autorevisión documental, stale hash, decisión duplicada, fecha incorrecta y cualquier intento de marcar `identity_verified=true` sin prueba. No usar Supabase Auth/JWT/MFA para **identificar al humano** en temporal; no afirmar atribución física ni firma del dueño por el mero string.
**Falta:** #3803 despliegue por Train, ejecución y recibo documental **real** + negativa; #3804/#3806 enlazan modelo owner/receipts, pero ninguna prueba SQL aislada demuestra decisión en Supabase real. Riesgo/alcance registrado pendiente de firma. **IAM real requerido en la base productiva final**. **ABIERTO.**

### B09_E2E · G12
**Exacta:** RUN **nuevo** de perfil por ruta EKB ACT-0001→Gate2→Perfil→RUN→IG/Curator/Validator→proveedor nativo genuino→Step70/juez independiente con recibo verificable→escritor oficial niño 7/7→promoción/corrección de regla→Step80 oficial→11/11 pasos `STEP_PASS_WITH_EVIDENCE`, RUN `COMPLETED`, terminal `READY` y VIGENTE/readback exactos. Probar regla nueva y corrección existente, negativos HMAC_TEST/MOCK, juez no independiente, rechazo de paso sin RAW y sin suplantar criterio de Login B01 fail-closed.
**Falta:** #3803 `lf_ig_rule_cycle_once_v3` y adapter candidate, pero `lf_ig_verified_native_provider_receipt_v1` NO INSTALADO, dispatch no conectado a proveedor, CI último HEAD falló; **no E2E positivo nativo real**. Falta ruta productora + juez genuino + recibo y prueba total. **ABIERTO.**

### B12_LEGACY · G08
**Exacta:** congelar md5 y ACL/prototypes de cuatro funciones `apply_batch`, `decide_batch`, `report` y `guard` del L21, más 6 firmas V1 que PR #3803 preflightea. Comparar antes/después de #3803/#3804/#3806 en PG18 y PostgreSQL 17.6 y, tras Train, SELECT live; positivos/negativos para idempotencia, denegar-by-default, no pérdida de reglas, no regressions, compatibilidad B05 baseline. Verificar MD5 congelados L21: apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8_guard `522d12f0843be1da3c785cef3c0bf3fc`; son **históricos, no re-medidos en este lote**.
**Falta:** subsanar R17 del HEAD #3803 (run 43376438216 FAIL), revalidar migraciones #3804/#3806 contra HEAD aplicado, leer 4 funciones reales post-Train y comparar pruebas/reglas en ambiente final de ensayo. **ABIERTO.**

## Política de readback para cerrar cualquier Bnn
Solo marcar CERRADO si hay `operation_code`, `execution_id` nuevo o prueba SELECT equivalente, SHA exactos, entorno, actor operacional (no autenticación humana ficticia), timestamp real, evidencia RAW, negativos, idempotencia, veredicto de control y recibo autenticado por **el mecanismo que realmente corresponda al carril**, con decisión de dueño pendiente si no está firmada. No confundir una decisión documental no autenticada con una aprobación formal. Las plantillas Bnn originales siguen vacías.

## Ruta migratoria en disputa
**Decisión en conversación:** «migraciones directo por LF Migration Merge Train, sin Router». Esto significa el **Train como único operador**; no llamar ACT-0001 manual antes de la migración. **Sin embargo**, #3803 actual exige `router_authority_receipt` para un RUN `ACTUALIZACION_DB_LF` y #3804/#3806 todavía enumeran ACT-0001 como requisito. El plan NO elimina una comprobación activa. Resolver de forma gobernada el contrato exacto del Train y su origen de receipt, o mantener NO-GO. La ruta ACT-0001 del perfil EKB permanece independiente y no debe reinterpretarse como migración.
