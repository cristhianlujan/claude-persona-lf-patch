# L37 — Alcance, vigencia y decisiones complementarias (borrador)

**ESTADO GENERAL:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA, salvo las cuatro excepciones/riesgos que requieren aceptación explícita. Cero firma autenticada, cero llamadas a escritores, cero DML/DDL Supabase. Autoría del borrador: GPT-6, no auditor independiente.

## Fuentes y precedencia sin cambiar fuentes oficiales

- **L27** registró Q03, Q04 y Q05; **L30** registró Q01, Q02, Q06–Q12 y L30-APPROVAL-MODEL-001. Las 12 preguntas se declaran decididas conversacionalmente, **0 firmadas**; 20 adicionales del dossier L21 **no están decididas** y NO son elegibles para firma como si lo estuvieran.
- **L33 freeze**: el dueño autorizó todos los RUN IN_PROGRESS y priorizó 32; el corte 13-nov-2026 08:36:22.461152 UTC contiene 235 ID, SHA de miembros, y borrador G01 `NOT_ISSUED`. Firma de Operaciones y audit independiente faltan; 1 RUN cambió a COMPLETED tras el corte.
- **L33 Login AUTH033**: propuso patches AUTH-002/003/040 y handoff sin RUN; **NO hubo decisión de dueño nueva** sobre aprobación de esas propuestas. Excluir de aprobación en bloque de reglas.
- **L34 AUTH019 FIDO2 opción C está SUPERADO** por corrección L35 opción A (Admin Empresa, perfil 2: usuario/contraseña y correo OTP Brevo cuando MFA aplica). **L36** extiende al Admin LF perfil 1, también sin FIDO2/passkey; perfiles 3–6 conservan OTP. Ni AUTH019 ni política central 19 están promovidos.
- **L28** es fuente documental de B06/B08/Train/G15; sus textos de estado de migraciones son históricos. Firmar riesgos no retroactiva su vigencia ni deshace controles runtime.

## Decisiones conversacionales complementarias registradas en este paquete

### DEC-B07-PADRE-HIJA-001 · NUEVA NORMALIZACIÓN DOCUMENTAL
- Decidió en conversación el 13-nov-2026: **B07 utiliza modelo padre/hija, NO añadir 4 columnas LF + 5 SALY** como solución final. **Padre:** versión vigente de la regla. **Hija:** historial completo de versiones, decisor, hash, fecha y trazabilidad.
- Estado: `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. Este texto es **normalización para firma**, no transcripción literal original ya versionada; el dueño debe ratificarlo mediante el bloque.
- No da por acreditados historial previo inexistente, migración, RLS/índices/consumidores, rollback y reconciliación con el escritor V2. Exigir historia insertada atómicamente con las modificaciones y readback; backfill sólo de versión base cuando la historia real anterior no exista. **B07 continúa abierto**.

### DEC-B09-NATIVO-JUEZ-MISMO-LLM-001 · NUEVA NORMALIZACIÓN DOCUMENTAL
- Decidió en conversación el 13-nov-2026: ejecución con **GPT nativo en un chat nuevo**, sin API keys/credenciales externas; un componente de instrucciones del **mismo LLM** ejerce revisión/juez de propuestas; conservar SHA-256 de recibos.
- Estado: `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. Es normalización de declaración previa; no hay comprobante de proveedor independiente.
- Diferencia material frente a criterio B09/G12 vigente: **juez del mismo LLM no acredita independencia**, aunque exista rol o prompt separado. Función V2 actual exige `PASS_INDEPENDENT_SEMANTIC`; **no forzar ni falsear este recibo**. Un nuevo chat tampoco prueba invocación nativa transportada por ruta Router→Perfil→RUN ni 11/11 pasos. Bloquear G12 hasta cambio gobernado de contrato, evidencia genuina y readback; B09 abierto.

### DEC-B06-OWNER-LF-GOVERNANCE-001 · L28
- Owner canónico de activos `LF_GOVERNANCE`, sin variantes ni herencia automática a SALY; decisor humano documental distinto. Mantener SHA de preimagen, guard, archivados y readback; aprobación del dueño no sustituye recibos B06/G03.
- Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`.

### DEC-B08-DECLARACION-TEMPORAL-001 · L28
- En base temporal se atribuyen declaraciones del dueño a `Cristhian Luján` con `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false`; **no afirmar firma humana autenticada**, JWT, MFA ni sub humano comprobado. IAM humano real será exigible para base final.
- Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`.

### DEC-TRAIN-DIRECTO-001 · L28
- Migraciones exclusivamente mediante Merge Train; no invocar Router manualmente como paso previo externo. **No retirar** validaciones de autoridad/procedencia que aún exige el Train; reconciliar el contrato por vía oficial si existe conflicto. Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`.

### DEC-G15-TEMPORAL-7-GATES-001 · L28
- Evaluar GO técnico **solo temporal** del Motor con siete bloqueos B02/B03/B06/B07/B08/B09/B12 y gates G01/G02/G03/G04/G08/G11/G12; mantener B01/B04/B05/B10/B11 para Contenido y B13/B14 para Infra final. **No** igualarlo a GO productivo o cierre de 14/14.
- Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. La redefinición del contrato operativo G15 aún requiere implementación y verificación.

### DEC-TEMPORAL-BACKUP-ROLLBACK-001 · L28
- Base actual temporal, no contratar PITR ni crear otro Supabase de prueba temporal. Exigir preimagen SHA, rollback seguro y readback para cada cambio; B13/B14 quedan abiertos para base de producción final, con restore real. Afirmación de 7 copias del panel = testimonio, no readback verificado.
- Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`.

### PROP-RIESGO-RECIBOS-DUENO-001 · NUEVO AJUSTE A FIRMAR
- Propuesta del paquete: dueño suscribe **conformidad/aceptación** sobre recibos emitidos por Operaciones, DBA y auditor. **NO transforma** una autodeclaración del dueño en prueba independiente de quién operó o auditó; emisor y readback deben estar trazados.
- Estado `PROPUESTA_RIESGO_PENDIENTE_ACEPTACION`, no afirmar decisión previa.

## Límites de ejecución
**No llamar** `public.lf_ig_rule_owner_decide_v2`, `public.lf_ig_rule_cycle_once_v3`, `lf_skill_invoke_v1` ni registrar/persistir por SQL. Una sola frase firmable para este manifiesto NO es la tarjeta SQL de seis campos exigida por V2 y **NO debe convertirse automáticamente en APROBAR**. Firmar el paquete sólo formaliza alcance y aceptación documental de riesgos; cada gate técnico sigue gobernado por su propio contrato y recibo.
