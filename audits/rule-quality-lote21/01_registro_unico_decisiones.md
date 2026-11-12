# LOTE 21 — Registro único de decisiones del dueño

**32 decisiones, 3 DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA, 1 RECOMENDADA_SIN_CONFIRMAR, 28 PENDIENTE; 0 FIRMADAS; 12 L16 + 8 L19 + 12 L21.** Cada sugerencia es no vinculante. La firma documental NO ejecuta ni autoriza DML/DDL, activación ni RUN.

## Nota de trazabilidad Q01
L16 original: A=promover, B=mantener y C=quitar referencia. El dossier L21 registró la convención **C=dejar**, pero **el dueño no confirmó la recomendación C**. L27 registra RECOMENDADA_SIN_CONFIRMAR. Se conserva el origen L16 sin reescribirlo. No se reescribe ni falsifica el original.

### L16-Q01 — ¿Se puede operar MFA mientras AUTH-018 continúa CANDIDATO?
- Prioridad **P1** · bloqueo `B01_MFA` · **RECOMENDADA_SIN_CONFIRMAR**.
- **Opciones:** A=promover AUTH-018 tras prueba completa; B=quitar referencia solo con sustituto equivalente aprobado; C=dejar AUTH-022→AUTH-018 como dependencia identificada, fail-closed, sin promoción.
- **REGISTRO L27:** **RECOMENDACIÓN C NO CONFIRMADA.** Dejar AUTH-022→AUTH-018 identificada sin promoción; ninguna firma ni elección del dueño. Mantener fail-closed, candidata MFA y pruebas pendientes.
- **SUGERENCIA:** C (RECOMENDADA_SIN_CONFIRMAR): dejar referencia y gate identificado, sin promover. Para promover AUTH-018: SAML/IdP administradores probado, Brevo OTP correo probado incluyendo entrega y validación servidor, ADR-003 spike M1 decidido, política de factor ID 19 VIGENTE, y prueba de que ningún AUTHENTICATED ni permiso precede a MFA. Se informó 11 reglas MFA CANDIDATO; este lote no certifica conteo exacto.
- **Firmante:** DUEÑO LF + Seguridad/Owner (identidad no acreditada aún).
- **Evidencia:** L16 S03 SHA256 8b70da4a3d3b381620473202de4a569d4b09fcfda6b3973e81661c3d2631b46a; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a; L21 S21_03 SHA256 3cff7e13769ed846a69c274f88e4f89cabea989a13c2c6488a6e7acc0ca371ee; 11 candidatas MFA = declaración verificada por dueño, no retesteada.
- **Calificación:** DECLARACION_DUENO_EN_CONVERSACION / REQUIERE_REVISION_SEMANTICA; ver L25 y CSV; **FIRMA FORMAL: NO_ACREDITADA**. Evidencia histórica permanece referenciada.

### L19-Q01 — ¿Qué RUN integran exactamente la cohorte 32 frente a los 232 vivos en SQL?
- Prioridad **P1** · bloqueo `B02_RUN_SCOPE` · **PENDIENTE**.
- **Opciones:** A=232 íntegros; B=32 IDs literales del dueño; C=32 prioritarios propuestos.
- **SUGERENCIA:** Conservar universo 232 e investigar 32 prioritarios; fijar lista sin ambigüedad.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 R01 SHA256 b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0; L19 H1/H2 SHA256 89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385 / 5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X06 — ¿Qué identidad real se aceptará: Supabase Auth y sub→perfil/actor por proyecto?
- Prioridad **P1** · bloqueo `B08_IDENTITY` · **PENDIENTE**.
- **Opciones:** A=diseñar binding JWT/RLS probado; B=NO-GO; C=usar HMAC fixture.
- **SUGERENCIA:** B hasta JWT real, rol efectivo, aislamiento por proyecto y denegación SUPER_ADMIN.
- **Firmante:** DUEÑO + IAM/Seguridad (identidad no acreditada aún).
- **Evidencia:** L21 S21_05 SHA256 44e9708a9659dcec3d11e9dcc4ff304a025c23606cce150852058b7a08512f83; L17 blob 6c873b32f9bd7004b82f80c64e40c297cdb1a3af.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X07 — ¿Se aprueba solo plan de prueba nativa ACT-0001→perfil→RUN→IG→Step70/OIDC→cierre?
- Prioridad **P1** · bloqueo `B09_E2E` · **PENDIENTE**.
- **Opciones:** A=ensayo real controlado; B=mantener NO-GO; C=aceptar L18 como prueba nativa.
- **SUGERENCIA:** A como plan futuro; no confundir fixtures de L18 con Step70/OIDC real.
- **Firmante:** DUEÑO + Gobernanza/Plataforma (identidad no acreditada aún).
- **Evidencia:** L18 CI HEAD abeea154a559759dcf2f56f42c8fd106ca768b64; report Git blob 64f763defa2e929e87539a5507126860ffd61577; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X10 — ¿Se exige respaldo físico + PITR con retención, RPO y RTO explícitos?
- Prioridad **P1** · bloqueo `B13_BACKUP` · **PENDIENTE**.
- **Opciones:** A=evidencia física/PITR y política; B=NO-GO; C=asumir backups.
- **SUGERENCIA:** B hasta recibos de proveedor/DBA; SELECT no acredita backup ni PITR.
- **Firmante:** DUEÑO + DBA/Continuidad (identidad no acreditada aún).
- **Evidencia:** NO_VERIFICADO; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X11 — ¿Se exige ensayo real de restauración en entorno aislado antes de migrar?
- Prioridad **P1** · bloqueo `B14_RESTORE` · **PENDIENTE**.
- **Opciones:** A=restauración y prueba checksum/tiempos; B=NO-GO; C=aceptar DOWN SQL.
- **SUGERENCIA:** B hasta A: DOWN no es rollback seguro tras poblar datos.
- **Firmante:** DUEÑO + DBA/Continuidad (identidad no acreditada aún).
- **Evidencia:** NO_VERIFICADO; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X12 — ¿Se aprueba contrato MFA de factor 19 y recuperación sin bypass para 11 reglas candidatas?
- Prioridad **P1** · bloqueo `B01_MFA` · **PENDIENTE**.
- **Opciones:** A=aprobar contrato y pruebas SAML/Brevo/ADR-003; B=mantener CANDIDATO; C=activar sin prueba.
- **SUGERENCIA:** B hasta todo probado y política 19 VIGENTE; correo OTP no acredita AAL2 nativo.
- **Firmante:** DUEÑO + Seguridad/Auth (identidad no acreditada aún).
- **Evidencia:** L21 S21_03 SHA256 3cff7e13769ed846a69c274f88e4f89cabea989a13c2c6488a6e7acc0ca371ee; 11 candidatas = alcance informado por dueño.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q02 — ¿Cómo resolver los 56 B con señales de escritura?
- Prioridad **P2** · bloqueo `B03_RUN_EFFECTS` · **PENDIENTE**.
- **Opciones:** A=conciliar destinos/commits primero; B=reintentar; C=cerrar sin readback.
- **SUGERENCIA:** A; B/C bloqueadas hasta idempotencia y recibos.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 R01 SHA256 b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0; L19 H1/H2 SHA256 89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385 / 5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q03 — ¿Qué hacer con los 4 posiblemente vivos?
- Prioridad **P2** · bloqueo `B03_RUN_EFFECTS` · **PENDIENTE**.
- **Opciones:** A=confirmar heartbeat y worker; B=mantener sin cambios; C=forzar cierre.
- **SUGERENCIA:** B hasta A; no C.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 R01 SHA256 b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0; L19 H1/H2 SHA256 89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385 / 5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X04 — ¿Se autoriza el diseño de columnas LF reviewed_at,next_review_at,successor_rule_code,effective_to?
- Prioridad **P2** · bloqueo `B07_SCHEMA` · **PENDIENTE**.
- **Opciones:** A=aprobar contrato y borrador UP/DOWN; B=posponer; C=ejecutar SQL directo.
- **SUGERENCIA:** A documental, requiere backfill, RLS/GRANT, compatibilidad, rollback seguro posterior.
- **Firmante:** DUEÑO LF + DBA/Arquitectura (identidad no acreditada aún).
- **Evidencia:** L21 S21_02 SHA256 0a8624c58887c553249137fe556594d311ced96ced7ed4cf12d7af0fa34c7090; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b; UP_SHA256 ef65c2f5d8c64547d017d410e14093403890de281d83aaf924437b7d6db29819.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X05 — ¿Se autoriza diseño de columnas SALY más lifecycle_state separado de estado VALIDADO?
- Prioridad **P2** · bloqueo `B07_SCHEMA` · **PENDIENTE**.
- **Opciones:** A=cinco campos+plan; B=posponer; C=reutilizar estado.
- **SUGERENCIA:** A documental sin reutilizar estado; DOWN solo seguro previo a datos.
- **Firmante:** DUEÑO SALY + DBA/Arquitectura (identidad no acreditada aún).
- **Evidencia:** L21 S21_02 SHA256 0a8624c58887c553249137fe556594d311ced96ced7ed4cf12d7af0fa34c7090; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b; DOWN_SHA256 c2bd75ea6e2858cc4e4c692b6a5c253637fd16fb3f7a6638135cbd8a1ca84b30.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X08 — ¿Se aprueba registro operativo project_code+owner_profile_code+actors+familias?
- Prioridad **P2** · bloqueo `B06_OWNER` · **PENDIENTE**.
- **Opciones:** A=diseñar mapa autenticado por proyecto; B=sin owner; C=usar B2B Admin tácito.
- **SUGERENCIA:** A con dueño real LF/SALY y no SUPER_ADMIN, sin activar fuentes sintéticas.
- **Firmante:** DUEÑO LF/SALY + IAM (identidad no acreditada aún).
- **Evidencia:** L21 S21_01 SHA256 4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933; L21 S21_05 SHA256 44e9708a9659dcec3d11e9dcc4ff304a025c23606cce150852058b7a08512f83; L19 O1-O4 SHA256 ver 09_manifest.md @5ee4c92632d41c31fdec6807dee99a2207104d4a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X09 — ¿Se aprueba matriz de compatibilidad apply_batch,decide_batch,report,guard?
- Prioridad **P2** · bloqueo `B12_LEGACY` · **PENDIENTE**.
- **Opciones:** A=contratos y regresiones antes adopción; B=posponer; C=sustituir funciones directo.
- **SUGERENCIA:** A antes de cualquier despliegue, respetando funciones existentes y gates.
- **Firmante:** DUEÑO LF + DBA/Arquitectura (identidad no acreditada aún).
- **Evidencia:** L21 S21_04 SHA256 344c5611f98c1933f8e6337e53e24b74e3cdda4af7e045ba96335878e7e97016; L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q04 — ¿Cómo investigar 166 D sin efectos demostrados?
- Prioridad **P3** · bloqueo `B03_RUN_EFFECTS` · **PENDIENTE**.
- **Opciones:** A=ampliar fuentes y contratos por operación; B=archivar masivamente; C=asumir sin efectos.
- **SUGERENCIA:** A; no B/C.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 R01 SHA256 b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0; L19 H1/H2 SHA256 89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385 / 5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q05 — ¿Pueden 6 A declararse huérfanos sin efectos?
- Prioridad **P3** · bloqueo `B03_RUN_EFFECTS` · **PENDIENTE**.
- **Opciones:** A=verificar sinks externos adicionales; B=asumir cero efecto; C=cerrar de inmediato.
- **SUGERENCIA:** A; clasificación sigue provisional.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 R01 SHA256 b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0; L19 H1/H2 SHA256 89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385 / 5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X01 — ¿Qué intervalo de revisión LF se aprueba (en días)?
- Prioridad **P3** · bloqueo `B04_FAMILY` · **PENDIENTE**.
- **Opciones:** A=intervalo documentado; B=posponer; C=90 días sintéticos.
- **SUGERENCIA:** B mientras no haya política real; 90 solo fixture.
- **Firmante:** DUEÑO LF + Gobernanza (identidad no acreditada aún).
- **Evidencia:** L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X02 — ¿Qué intervalo de revisión SALY se aprueba (en días)?
- Prioridad **P3** · bloqueo `B04_FAMILY` · **PENDIENTE**.
- **Opciones:** A=intervalo documentado; B=posponer; C=60 días sintéticos.
- **SUGERENCIA:** B mientras no haya política real; 60 solo fixture.
- **Firmante:** DUEÑO SALY + Gobernanza (identidad no acreditada aún).
- **Evidencia:** L20 CI HEAD b7e362b36e82b4075bc9effc363ec777c6756d87; report Git blob 4b28a22978061bb049c541a0713636597e830d3b.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L21-X03 — ¿Se aprueban las 15 familias LF propuestas y la resolución individual de 23 pertenencias dudosas?
- Prioridad **P3** · bloqueo `B04_FAMILY` · **PENDIENTE**.
- **Opciones:** A=aprobar tras revisión 23/23; B=mantener provisional; C=remapear automáticamente.
- **SUGERENCIA:** A mediante acta separada, sin mutar categorización en este lote.
- **Firmante:** DUEÑO LF + Gobernanza (identidad no acreditada aún).
- **Evidencia:** L16 S01 SHA256 59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9; L13 blob 26a06c7c64ab40368f4da22d478298676bdcbfcd.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q07 — ¿Se deben corregir las 23 pertenencias dudosas de las 15 familias?
- Prioridad **P4** · bloqueo `B04_FAMILY` · **PENDIENTE**.
- **Opciones:** A=resolver familia primaria caso a caso; B=conservar propuesta provisional; C=remapear en masa.
- **SUGERENCIA:** A como dictamen documental, sin mutación automática.
- **Firmante:** DUEÑO LF + Gobernanza/Owner (identidad no acreditada aún).
- **Evidencia:** L16 S01 SHA256 59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q06 — ¿Quién debe ser owner real de calidad de reglas de LF?
- Prioridad **P4** · bloqueo `B06_OWNER` · **PENDIENTE**.
- **Opciones:** A=nombrar perfil distinto de SUPER_ADMIN; B=usar B2B_ADMIN_LF como owner automático; C=dejar sin owner.
- **SUGERENCIA:** A con prueba de competencia y vínculo a actor; no B automático.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 O1-O4 SHA256 ver 09_manifest.md @5ee4c92632d41c31fdec6807dee99a2207104d4a; L21 S21_01 SHA256 4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q07 — ¿Quién será owner de SALY y de cada familia?
- Prioridad **P4** · bloqueo `B06_OWNER` · **PENDIENTE**.
- **Opciones:** A=nombrar owner SALY y mapas propios; B=heredar LF; C=usar proyecto sin actor.
- **SUGERENCIA:** A; conservar aislamiento SALY/LF.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 O1-O4 SHA256 ver 09_manifest.md @5ee4c92632d41c31fdec6807dee99a2207104d4a; L21 S21_01 SHA256 4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L19-Q08 — ¿Se autoriza un futuro diseño gobernado del registro de owners y recibos de reconciliación?
- Prioridad **P4** · bloqueo `B06_OWNER` · **PENDIENTE**.
- **Opciones:** A=aprobar solo diseño/plan con identidad verificada; B=implantar L13/L17 sandbox sin adaptar; C=mantener NO-GO.
- **SUGERENCIA:** A como fase separada, sin adoptar sandbox directamente ni tocar RUN.
- **Firmante:** DUEÑO LF + responsable de Operaciones/Gobernanza (identidad no acreditada aún).
- **Evidencia:** L19 O1-O4 SHA256 ver 09_manifest.md @5ee4c92632d41c31fdec6807dee99a2207104d4a; L21 S21_01 SHA256 4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q06 — ¿Los 20 pares de parámetros nombran el mismo control o controles distintos?
- Prioridad **P5** · bloqueo `B05_RULES` · **PENDIENTE**.
- **Opciones:** A=documentar sujeto+evento+alcance; B=igualar valores automáticamente; C=ignorar diferencias.
- **SUGERENCIA:** A, conservar umbrales separados mientras se valida contexto.
- **Firmante:** DUEÑO LF + Seguridad/Observabilidad (identidad no acreditada aún).
- **Evidencia:** L16 S04 SHA256 815d9f903189c7fe98c5b6c8ae7a32ca4b061d3422033010140fe60230f2dd3f; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q11 — ¿Qué proveedor IDV step-up respaldará recuperación Cliente?
- Prioridad **P5** · bloqueo `B01_MFA` · **PENDIENTE**.
- **Opciones:** A=seleccionar y probar proveedor; B=mantener step-up condicionado; C=omitir control.
- **SUGERENCIA:** B hasta A; no C.
- **Firmante:** DUEÑO LF + Seguridad/Integraciones (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q12 — ¿Cómo calibrar señales de riesgo y umbrales sin datos históricos?
- Prioridad **P5** · bloqueo `B05_RULES` · **PENDIENTE**.
- **Opciones:** A=telemetría/baseline; B=definir cifras arbitrarias; C=descartar señal.
- **SUGERENCIA:** A; mantener control cualitativo mientras se valida.
- **Firmante:** DUEÑO LF + Riesgos/Seguridad (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q02 — ¿Cuál es el ledger/snapshot canónico para pagos, cuotas y conciliación?
- Prioridad **P6** · bloqueo `B10_BUSINESS` · **PENDIENTE**.
- **Opciones:** A=reutilizar estructura acreditada; B=diseñar canónico gobernado; C=usar DEMO.
- **REGISTRO L27:** **ALCANCE DETERMINADO POR DUEÑO, OPCIÓN DE LEDGER PENDIENTE:** construcción de ledger asignada a Producto/QA, fuera de Input Governance. No hay selección A/B ni implementación acreditada. L22 únicamente documentó requisitos.
- **SUGERENCIA:** A si existe; B si se prueba que falta; nunca C.
- **Firmante:** DUEÑO LF + Arquitectura/Finanzas (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** DECLARACION_DUENO_EN_CONVERSACION / REQUIERE_REVISION_SEMANTICA; ver L25 y CSV; **FIRMA FORMAL: NO_ACREDITADA**. Evidencia histórica permanece referenciada.

### L16-Q03 — ¿Qué proveedor de pago y frontera PCI están habilitados en producción?
- Prioridad **P6** · bloqueo `B10_BUSINESS` · **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**.
- **Opciones:** A=aprobar binding con QA; B=mantener pago bloqueado; C=usar credenciales/branding DEMO.
- **REGISTRO L27:** **DECISIÓN DEL DUEÑO EN CONVERSACIÓN — OPCIÓN A:** Niubiz es el proveedor unico de recaudo, tarjeta y Yape (opcion A). Para pasar a produccion exige: contrato, callbacks probados, captura de tarjeta solo en componente del proveedor, ledger de Q02, sin credenciales DEMO. **GATE:** esto no habilita producción ni aprueba reglas. Referencia documental L25 13 propuestas CANDIDATO, no promovidas.
- **SUGERENCIA HISTORICA L21 (no es decisión):** B hasta contratos, callbacks y evidencia.
- **Firmante:** DUEÑO LF + Pagos/Integraciones/Seguridad (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** DECLARACION_DUENO_EN_CONVERSACION / REQUIERE_REVISION_SEMANTICA; ver L25 y CSV; **FIRMA FORMAL: NO_ACREDITADA**. Evidencia histórica permanece referenciada.

### L16-Q05 — ¿Qué configuración de pricing/quote y elegibilidad es autoridad?
- Prioridad **P6** · bloqueo `B10_BUSINESS` · **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**.
- **Opciones:** A=config canónica APROBADO/VIGENTE; B=continuar solo DEMO; C=hardcodear valores.
- **REGISTRO L27:** **DECISIÓN DEL DUEÑO EN CONVERSACIÓN — OPCIÓN A:** Opcion A: tabla de pricing con historial y vigencias; valor aplicable segun la vigencia; una sola version vigente por fecha, sin solapes ni huecos; si no hay version vigente no se cotiza y no se hace fallback a la anterior; historial inmutable (cerrar y abrir version); plan ya activado conserva snapshot; montos actualizados desde el sistema por actor cuyo perfil tenga permiso de actualizacion. Dependencia: permiso de pricing no existe segun declaracion del dueño; 45 permisos y 0 asignaciones usuario-perfil constan en evidencias historicas L19/L21, 16 resource_type y ausencia de pricing declarados por el dueño (SIN SELECT NUEVO L27). El permiso de actualizar precios será una dependencia de Producto + registro operativo de owners. **No se ejecutó SELECT en L27:** las 16 tipologías de recurso y ausencia de pricing constan por declaración del dueño y requieren readback externo para acreditación independiente.
- **SUGERENCIA HISTORICA L21 (no es decisión):** B hasta tener A; nunca C.
- **Firmante:** DUEÑO LF + Producto/Arquitectura (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** DECLARACION_DUENO_EN_CONVERSACION / REQUIERE_REVISION_SEMANTICA; ver L25 y CSV; **FIRMA FORMAL: NO_ACREDITADA**. Evidencia histórica permanece referenciada.

### L16-Q04 — ¿Quién aprueba gracia, vencimiento, mora y terminación recurrente?
- Prioridad **P7** · bloqueo `B11_LEGAL` · **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**.
- **Opciones:** A=Legal+Negocio formalizan política; B=ocultar claims de mora; C=inferir plazos.
- **REGISTRO L27:** **DECISIÓN DEL DUEÑO EN CONVERSACIÓN (SUBDECISIONES, NO OPCIÓN L16 COMPLETA):** Estados de cuota: PENDIENTE, EN_PROCESO, PAGADA, VENCIDA, CANCELADA; sin gracia: el dia siguiente a la fecha sin pago es VENCIDA; el rechazo por si solo no marca vencida. Corte a medianoche America/Lima. Reconciliar EN_PROCESO con Niubiz en medianoche; si NO_DETERMINADO se conserva EN_PROCESO, se registra excepcion, se escala a humano y se envia alerta por correo con destinatario configurable y sin datos de tarjeta ni nombre del cliente. Cancelacion por cuota o plan completo; EN_PROCESO no se cancela hasta reconciliar; VENCIDA si se puede cancelar. Cancelacion automatica por antiguedad: parametro ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES, valor inicial 12 meses calendario desde fecha cuota; cancela todas las cuotas no pagadas del plan; PAGADA conserva estado; EN_PROCESO espera reconciliacion y reevalua en corrida siguiente. Deuda cancelada = INCOBRABLE, falla cerrada si falta parametro; pantalla de mantenimiento de parametros por Producto, fuera de IG. Siguen ABIERTOS SOLO: reintentos de cobro automatico, recordatorios, mora, destino contable de deuda INCOBRABLE (Negocio/Legal/Finanzas, REQUIERE_REVISION_SEMANTICA). **RESTAN SOLO ESTOS SUBTEMAS:** REINTENTOS_COBRO_AUTOMATICO | RECORDATORIOS | MORA | DESTINO_CONTABLE_DEUDA_INCOBRABLE. No se elige unilateralmente A de la taxonomía original L16 ni se certifican firmas.
- **SUGERENCIA HISTORICA L21 (no es decisión):** B mientras se obtiene A; no inventar consecuencias.
- **Firmante:** DUEÑO LF + Legal/Negocio/Operaciones (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** DECLARACION_DUENO_EN_CONVERSACION / REQUIERE_REVISION_SEMANTICA; ver L25 y CSV; **FIRMA FORMAL: NO_ACREDITADA**. Evidencia histórica permanece referenciada.

### L16-Q08 — ¿Qué textos legales, consentimientos y Anexo I pueden publicarse?
- Prioridad **P7** · bloqueo `B11_LEGAL` · **PENDIENTE**.
- **Opciones:** A=Legal aprueba texto y evidencia; B=mantener pendientes; C=usar placeholders.
- **SUGERENCIA:** B hasta A.
- **Firmante:** DUEÑO LF + Legal/Contenido (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q09 — ¿Qué copys, rutas y visuales de Home tienen evidencia publicable?
- Prioridad **P7** · bloqueo `B11_LEGAL` · **PENDIENTE**.
- **Opciones:** A=validar visual+registro canónico; B=ocultar claims no verificados; C=inventar rutas.
- **SUGERENCIA:** B hasta A; no afirmar aliados/prensa sin fuente.
- **Firmante:** DUEÑO LF + UX/Legal (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

### L16-Q10 — ¿Qué workflow y SLA confirman settlement y Carta de No Adeudo?
- Prioridad **P7** · bloqueo `B10_BUSINESS` · **PENDIENTE**.
- **Opciones:** A=acordar API/SLA/registros con aliado; B=dejar estado informativo; C=confirmar sin evidencia.
- **SUGERENCIA:** B hasta A; nunca C.
- **Firmante:** DUEÑO LF + Operaciones/Aliados (identidad no acreditada aún).
- **Evidencia:** L16 S02 SHA256 2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce; L16 HEAD 63c96935dd594f13cec4e3291c2a58931094cb7a.
- **Calificación:** SUGERENCIA / REQUIERE_REVISION_SEMANTICA. Datos objetivos en hashes/commits citados.

Las respuestas son campos vacíos del CSV 05. Las decisiones L21 no representan instrucciones de producción sino elección sobre una futura fase autorizable.

## Adenda L27 — Estado de captura y alcance

- Decididas en conversación: **L16-Q03, L16-Q04 (subdecisiones), L16-Q05**. No son firmas, aprobaciones de reglas, operaciones gobernadas ni GO productivo.
- Recomendación no confirmada: **L16-Q01 MFA C**.
- Ledger: **L16-Q02 PENDIENTE de alternativa**, construcción Producto/QA fuera de IG.
- **L16-Q04 conserva exclusivamente 4 subtemas abiertos:** reintentos de cobro automático, recordatorios, mora, destino contable de deuda INCOBRABLE por Negocio/Legal/Finanzas. El tratamiento técnico previo a producción (Niubiz/ledger) es dependencia, no subdecisión nueva del dueño.
- Restantes: **28 PENDIENTE**; **0 firmas** verificadas. Otras decisiones L19/L21 intactas.
- Evidencia histórica L21/L19 y L25; este lote **NO EJECUTÓ SELECT** ni PG18. Los 45 permisos y 0 asignaciones provienen de lecturas anteriores; 16 `resource_type` y ausencia de permiso pricing son **afirmación del dueño sin readback SQL en L27**. Consulta reproducible documental en `audits/rule-quality-lote27/02_pricing_permission_select_no_ejecutado.sql`.
- Juez/autor: **GPT-6, mismo modelo, no independiente**; firma formal del dueño inexistente. **NO-GO / UNVERIFIED.**
