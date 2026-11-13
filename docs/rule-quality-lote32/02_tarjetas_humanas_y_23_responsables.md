# LF L32 — Tarjetas de decisión del dueño y distribución de las 23 bloqueadas

**Fecha del corte:** 13-nov-2026. **Criterio:** lector de Supabase + GitHub; SIN DML/DDL, sin invocación del writer V2, sin decisión atribuida al dueño y sin promoción.

## Estado: 3 tarjetas listas para revisión, 0 registros enviados al writer

- El V2 `public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)` **sí existe** en Supabase y fue leído directamente; texto real de la función y firma verificados.
- **Peligro funcional:** `p_decision.veredicto='APROBAR'` llama la skill `RULE_UPDATE_APPLY` y `lf_ig_rule_finalize_v2`, con posibilidad de `VIGENTE_VERIFIED`. `RECHAZAR` registra rechazo sin mutación de regla, pero igualmente ES una escritura de decisión. Este lote no llama la función.
- Se verificó por SQL que el writer de reglas CANDIDATO acepta `DOCUMENTARY_ONLY`, tres llaves exactas `rule_code,change_kind,changes` y `changes` con **solo título/descripción/razón**. Las propuestas antiguas L31 también cambiaban `valor_config`; **NO serían aplicables íntegramente por ese writer**. Los parches de abajo se limitan a `descripcion`.
- Se conservan dos hashes distintos. El del candidato L31 **no debe** copiarse a `propuesta_sha256` de V2; allí va `SHA256(PG jsonb::text del governed_rule_patch exacto registrado por el perfil)`.
- Es obligatorio un `p_parent` admitido, RUN `IN_PROGRESS` del Product Director, `input_validate`, `output_validate` y `semantic_judge` independientes en PASS, `execute_profile` con patch idéntico y `product_decision.proposed_by` diferente de `decisor`. Si no existe esa evidencia no habrá escritura legítima.
- Las seis llaves son EXACTAS: `codigo_regla`, `propuesta_sha256`, `veredicto`, `decisor`, `fecha`, `frase_literal`. **Todos sus valores son string.** Se dejan placeholders únicamente en los tres campos que dependen de la decisión humana: veredicto, fecha, frase literal. Por tanto son **formularios documentales con estructura exacta**, aún NO inputs válidos invocables.
- `p_source_sha256` exige el SHA canónico de `lf_asset_snapshot_sha_v1`, cuya lectura está denegada a la conexión read-only: **PENDIENTE**. No usar el SHA de fila como sustituto.
- `AUTH-033` está vinculada solo a `B2B-AUTH-004` y `B2B-AUTH-005`; **no pertenece a `B2B-AUTH-001`**. Debe tener un RUN seleccionado para pantalla vinculada.
- El RUN observado `EXEC-PROFILE-GATE2-40471E6F661A53D7CE7A4A1B` sigue con 7/11 pasos registrados y no aporta `output_validate` ni juez independiente para la decisión de regla. No reabrir ni modificar un RUN anterior para simularlo.

---

## Tarjeta 1 — B2B-RULE-AUTH-018: MFA solo cuando la política central lo exija

**Qué dice hoy.** Hoy, después de validar la contraseña, la regla exige el segundo factor para los seis perfiles humanos. No concede sesión ni permisos sin completar MFA.

**Qué cambiaría.** El servidor revisaría la política central y exigiría MFA solo cuando corresponda al acceso. La cobertura de perfiles no equivale a pedir un código siempre. Los 30 días sin uso y tres meses sin cambiar contraseña se definirían en la política 3, nunca en esta regla.

**Por qué cambiarla.** Evita duplicar umbrales en pantalla y permite MFA condicional como decidió el dueño, preservando bloqueo de sesión si se exige el factor.

**Sugerencia.** FAVORABLE AL CAMBIO DOCUMENTAL, PERO NO APROBAR EN V2 TODAVÍA: política 3 sigue VIGENTE con otra exigencia; faltan sucesión gobernada, disparadores adicionales, dictamen de seguridad y juez independiente.

**Si se aprueba.** Después de cumplir gates, el writer V2 cambiaría solo la descripción y podría promover la regla. NO cambiaría automáticamente política 3, sus parámetros ni backend; una aprobación inmediata sin esos ajustes dejaría contradicciones.

**Si se rechaza.** La descripción original permanece; continúa MFA exigido a los seis perfiles según la política actual. Q01 queda pendiente de conciliación documental y técnica.

**SHA-256 preimagen de fila completa:** `70f6effce7976fa30a0022862649738c1d161246dc97d2db69d7b727110d75de`  
**SHA-256 del candidato íntegro L31 (incluye configuración; NO es aplicable por V2):** `46e118ed2febbb49eea4ba95c040f4e3837dd7eff417dea2f945014eb8330914`  
**SHA-256 del patch V2 (solo descripción, validado SQL):** `c45b974b519ee985a3ae8fd4a0be8d4d0417eb6a113ea3732112efc86a793ef1`  
**Pantalla vinculada:** `B2B-AUTH-001`.  
**Dictamen:** PROPUESTA DOCUMENTAL; SIN DECISIÓN ACTUAL; no invocable hasta completar requisitos de perfil, jueces y dueño.

**Registro de seis campos para que complete el dueño:** 
```json
{
  "codigo_regla": "B2B-RULE-AUTH-018",
  "propuesta_sha256": "c45b974b519ee985a3ae8fd4a0be8d4d0417eb6a113ea3732112efc86a793ef1",
  "veredicto": "<APROBAR_O_RECHAZAR>",
  "decisor": "Cristhian Luján",
  "fecha": "<ISO8601_AL_MOMENTO_DE_DECIDIR>",
  "frase_literal": "<TEXTO_LITERAL_ESCRITO_POR_EL_DUENO>"
}
```

**Datos de llamada fuera de los seis campos:** `p_parent` = RUN vigente de perfil seleccionado para esta regla/pantalla, con juez independiente y `governed_rule_patch` idéntico; `p_rule` = `B2B-RULE-AUTH-018`; `p_source_sha256` = snapshot canónico de `public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-018')` leído por la ruta autorizada, NO la preimagen de fila SHA; `p_decision` = registro de seis campos después del texto literal y veredicto real del dueño.

**Bloqueos que impiden invocar ahora:** `POLICY_3_VIGENTE_REQUIRES_GOVERNED_SUCCESSOR`, `OTHER_MFA_TRIGGERS_PENDING_OWNER`, `OIDC_BINDING`, `INDEPENDENT_JUDGE_AND_CURRENT_RUN_REQUIRED`.


---

## Tarjeta 2 — B2B-RULE-AUTH-020: Recuperar identidad sin saltarse MFA

**Qué dice hoy.** La cuenta no puede recuperarse con contraseña sola ni enviando un OTP al correo comprometido; el procedimiento independiente para no administradores sigue sin definición funcional terminada y administradores se derivan al antiguo esquema Google.

**Qué cambiaría.** Se documentaría recuperación asistida por soporte con documento y verificación independiente, dos personas autorizadas, espera de 48 horas en política 20, aviso al contacto anterior, auditoría, revocación/reinscripción de factor y ninguna sesión durante el trámite. Perfiles de administradores requieren decisión aparte.

**Por qué cambiarla.** Define una recuperación segura en línea con Q11 sin introducir un bypass del segundo factor.

**Sugerencia.** FAVORABLE A LA DESCRIPCIÓN, NO A ACTIVARLA TODAVÍA: faltan método IDV comprobado, doble control y autorización real, política 20 y alcance de perfiles 1 y 2.

**Si se aprueba.** Con gates cumplidos, el writer podría registrar la nueva descripción y promover la regla; NO instalará soporte, IDV, permiso ni regla de espera 48 h en política 20.

**Si se rechaza.** Se conserva el estado de recuperación no definida; el acceso por contraseña sola continúa prohibido; no se habilita un canal alternativo.

**SHA-256 preimagen de fila completa:** `f17060b3b5c28a4c6b1736a5b78673c3951aebac6623b3dd1b7f16245f6cc18c`  
**SHA-256 del candidato íntegro L31 (incluye configuración; NO es aplicable por V2):** `c0a4238b25cae6f92402a22a9dba3c08a40a05822be6083f2ff966734aae37ef`  
**SHA-256 del patch V2 (solo descripción, validado SQL):** `696c2504d0bbe220d8d616fed545d73b89e9c69efa06f51ab60f78a888f3cd3c`  
**Pantalla vinculada:** `B2B-AUTH-001`.  
**Dictamen:** PROPUESTA DOCUMENTAL; SIN DECISIÓN ACTUAL; no invocable hasta completar requisitos de perfil, jueces y dueño.

**Registro de seis campos para que complete el dueño:** 
```json
{
  "codigo_regla": "B2B-RULE-AUTH-020",
  "propuesta_sha256": "696c2504d0bbe220d8d616fed545d73b89e9c69efa06f51ab60f78a888f3cd3c",
  "veredicto": "<APROBAR_O_RECHAZAR>",
  "decisor": "Cristhian Luján",
  "fecha": "<ISO8601_AL_MOMENTO_DE_DECIDIR>",
  "frase_literal": "<TEXTO_LITERAL_ESCRITO_POR_EL_DUENO>"
}
```

**Datos de llamada fuera de los seis campos:** `p_parent` = RUN vigente de perfil seleccionado para esta regla/pantalla, con juez independiente y `governed_rule_patch` idéntico; `p_rule` = `B2B-RULE-AUTH-020`; `p_source_sha256` = snapshot canónico de `public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')` leído por la ruta autorizada, NO la preimagen de fila SHA; `p_decision` = registro de seis campos después del texto literal y veredicto real del dueño.

**Bloqueos que impiden invocar ahora:** `IDV_NOT_SELECTED_OR_TESTED`, `SUPPORT_DUAL_CONTROL_AND_PERMISSIONS_MISSING`, `POLICY_20_CANDIDATE_NOT_GOVERNED`, `ADMIN_PROFILES_1_2_SCOPE_PENDING`, `INDEPENDENT_JUDGE_AND_CURRENT_RUN_REQUIRED`.


---

## Tarjeta 3 — B2B-RULE-AUTH-033: Dispositivo conocido no reemplaza la verificación MFA

**Qué dice hoy.** Tras la contraseña, la regla reconoce el dispositivo. Para perfiles no administradores, el reconocido puede continuar sin OTP; el desconocido debe pasar a verificación por correo. El servidor controla el dispositivo y las rutas.

**Qué cambiaría.** Antes de dar una sesión, el servidor reevaluaría MFA central y la confianza real. Aunque el dispositivo sea reconocido, no omitiría MFA central exigido. Un dispositivo nuevo o revocado seguiría requiriendo OTP; sin sesión ni ruta pública durante el desafío.

**Por qué cambiarla.** Impide que la marca de 'dispositivo confiable' neutralice los disparadores centrales de MFA o la revocación de AUTH-039.

**Sugerencia.** FAVORABLE A LA DESCRIPCIÓN Y AL CONTROL FAIL-CLOSED, PERO NO APROBAR V2 HASTA RECONCILIAR POLÍTICA 25, DISPARADORES MFA Y EL RUN SELECCIONADO PARA PANTALLA VINCULADA.

**Si se aprueba.** Con RUN de perfil de B2B-AUTH-004 o B2B-AUTH-005 y gates, writer V2 actualizaría solo descripción; sin cambiar política 25 ni credenciales de dispositivo. La aprobación sin reconciliación podría crear incongruencia funcional.

**Si se rechaza.** Sigue texto original, donde dispositivo conocido continúa sin OTP salvo otros controles efectivos. La contradicción potencial con MFA condicional sigue sin resolver.

**SHA-256 preimagen de fila completa:** `181389dac198874c07781bce78b9981803a52c9e845ed01926b86bd2f8ff939b`  
**SHA-256 del candidato íntegro L31 (incluye configuración; NO es aplicable por V2):** `b06846214880f86c470a1d004d80cd9409211cd1470591dfca98eff74079ecee`  
**SHA-256 del patch V2 (solo descripción, validado SQL):** `6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769`  
**Pantalla vinculada:** `B2B-AUTH-004`.  
**Dictamen:** PROPUESTA DOCUMENTAL; SIN DECISIÓN ACTUAL; no invocable hasta completar requisitos de perfil, jueces y dueño.

**Registro de seis campos para que complete el dueño:** 
```json
{
  "codigo_regla": "B2B-RULE-AUTH-033",
  "propuesta_sha256": "6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769",
  "veredicto": "<APROBAR_O_RECHAZAR>",
  "decisor": "Cristhian Luján",
  "fecha": "<ISO8601_AL_MOMENTO_DE_DECIDIR>",
  "frase_literal": "<TEXTO_LITERAL_ESCRITO_POR_EL_DUENO>"
}
```

**Datos de llamada fuera de los seis campos:** `p_parent` = RUN vigente de perfil seleccionado para esta regla/pantalla, con juez independiente y `governed_rule_patch` idéntico; `p_rule` = `B2B-RULE-AUTH-033`; `p_source_sha256` = snapshot canónico de `public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-033')` leído por la ruta autorizada, NO la preimagen de fila SHA; `p_decision` = registro de seis campos después del texto literal y veredicto real del dueño.

**Bloqueos que impiden invocar ahora:** `SCREEN_SCOPE_B2B_AUTH001_NOT_LINKED`, `POLICY_25_DEVICE_ONLY_RECONCILIATION`, `MFA_TRIGGERS_PENDING_OWNER`, `OIDC_BINDING`, `INDEPENDENT_JUDGE_AND_SEPARATE_PROFILE_RUN_REQUIRED`.


## Segunda parte — 23 bloqueadas por responsable principal

Se asigna **un responsable principal por regla** para sumar 23 sin duplicidad. Los bloqueos de varios equipos siguen vigentes; una asignación no equivale a capacidad exclusiva de cierre.

| Responsable principal | Cantidad | Códigos | Trabajo y límite |
|---|---:|---|---|
| Dueño / Seguridad y Producto | **6** | `AUTH-003`, `AUTH-019`, `AUTH-021`, `AUTH-039`, `AUTH-043`, `AUTH-047` | Política MFA 3/19; perfil 1/SMS y seguridad de Admin Empresa; parámetro 5 de Q12 sin unidad; disparadores revocación y dispositivo; Caps Lock y contador password-failure. |
| Motor IG / Arquitectura | **2** | `AUTH-002`, `AUTH-040` | 002 exige modelo físico multiempresa acreditado por Arquitectura, no lo puede crear IG. 040 permite propuesta documental para reconciliar política 25/semántica de dispositivo y QA, sin promoción ni cierre autónomo. |
| Brevo / SMS | **4** | `AUTH-034`, `AUTH-037`, `AUTH-044`, `AUTH-045` | Integración correo OTP, proveedor de entrega, credenciales, webhook firmado, rotación y QA reales; SMS contingencia sin proveedor. AUTH-034 también depende de políticas 3/25. |
| OIDC / Identidad | **11** | `AUTH-013`, `AUTH-015`, `AUTH-016`, `AUTH-017`, `AUTH-022`, `AUTH-026`, `AUTH-028`, `AUTH-030`, `AUTH-035`, `AUTH-036`, `AUTH-048` | ADR-003 M1/IdP real y binding OIDC, issuer/JWKS/JWT, adapter, outcomes, sesión, recuperación, timeout y submit; varios tienen además dependencia Brevo. |
| **TOTAL** | **23** | **23 códigos distintos** | **0 cierres verificados** |

### ¿Qué puede resolver el motor sin nuevas decisiones del dueño?

- **`AUTH-040`: SÍ puede preparar** comparación/diff de la política 25 y controles de dispositivo aprovechando la decisión Q01 existente y conservación de AUTH-039. **NO puede darla por cerrada** sin adjudicar la política, QA y validación gobernada.
- **`AUTH-002`: SÍ puede auditar fuentes y evidenciar** relación multiempresa; **NO puede construir ni declarar existente** un modelo físico de autorización que sigue `PENDING_FUNCTIONAL_DEFINITION`. Arquitectura/DB y QA son dependencias externas.
- **`AUTH-003`: SÍ puede preparar** sucesora de política 3 con umbrales Q01 y conservar cobertura, pero el original está **VIGENTE** y requiere decisión formal y operación gobernada. Se clasificó en dueño por esa compuerta.
- **`AUTH-034` y dependientes:** IG puede preparar reglas y pruebas, pero Brevo entrega y QA real son externos.
- **Todas las demás:** IG puede documentar y controlar, no inventar identidad, SMS, proveedor ni consentimiento del dueño. La familia `AUTH-019` mantiene conflicto OTP/Brevo perfil 2 vs `PHISHING_RESISTANT`.

**Cierre autónomo actual del motor: 0/23 (0%)**. Preparación de correcciones/reconciliación sin nuevas decisiones: `AUTH-040`; auditoría posible con evidencia adicional: `AUTH-002`. Las otras 21 requieren decisión, implementación o evidencia externa antes del cierre.

## Readback y trazabilidad
- Tarjetas 3/3, propuesta writer V2 válida en forma 3/3, fuente SHA fila sin drift 3/3 y pantalla vinculada 3/3 al utilizar alcance correcto para AUTH-033.
- Clasificación exclusiva 23/23 con motivos exactos preservados en `01_tarjetas_3_y_registros_v2.json`.
- No se probó ejecución del writer porque el alcance excluye escrituras, decisiones formales y promoción.
- Estado: **3 TARJETAS PARA REVISIÓN / REGISTROS DE SEIS CAMPOS CON PLACEHOLDERS / NO-GO DE INVOCACIÓN**. Cierre de bloqueos productivos: ninguno.
