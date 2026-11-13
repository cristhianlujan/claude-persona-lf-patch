# L39 — Segundo bloque, 23 temas para revisión previa, SIN DECISIÓN NI FIRMA

**Origen:** L21 20 preguntas históricas pendientes + L29 tres propuestas AUTH. No atribuir aprobación al dueño. Revisión de opciones obligatoria antes de copiar la frase.

| ID | Pregunta o tema histórico | Sugerencia extraída (NO decisión) | SHA-256 del archivo fuente |
|---|---|---|---|
| `L19-Q01` | ¿Qué RUN integran exactamente la cohorte 32 frente a los 232 vivos en SQL? | Conservar universo 232 e investigar 32 prioritarios; fijar lista sin ambigüedad. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X06` | ¿Qué identidad real se aceptará: Supabase Auth y sub→perfil/actor por proyecto? | B hasta JWT real, rol efectivo, aislamiento por proyecto y denegación SUPER_ADMIN. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X07` | ¿Se aprueba solo plan de prueba nativa ACT-0001→perfil→RUN→IG→Step70/OIDC→cierre? | A como plan futuro; no confundir fixtures de L18 con Step70/OIDC real. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X10` | ¿Se exige respaldo físico + PITR con retención, RPO y RTO explícitos? | B hasta recibos de proveedor/DBA; SELECT no acredita backup ni PITR. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X11` | ¿Se exige ensayo real de restauración en entorno aislado antes de migrar? | B hasta A: DOWN no es rollback seguro tras poblar datos. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X12` | ¿Se aprueba contrato MFA de factor 19 y recuperación sin bypass para 11 reglas candidatas? | B hasta todo probado y política 19 VIGENTE; correo OTP no acredita AAL2 nativo. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q02` | ¿Cómo resolver los 56 B con señales de escritura? | A; B/C bloqueadas hasta idempotencia y recibos. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q03` | ¿Qué hacer con los 4 posiblemente vivos? | B hasta A; no C. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X04` | ¿Se autoriza el diseño de columnas LF reviewed_at,next_review_at,successor_rule_code,effective_to? | A documental, requiere backfill, RLS/GRANT, compatibilidad, rollback seguro posterior. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X05` | ¿Se autoriza diseño de columnas SALY más lifecycle_state separado de estado VALIDADO? | A documental sin reutilizar estado; DOWN solo seguro previo a datos. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X08` | ¿Se aprueba registro operativo project_code+owner_profile_code+actors+familias? | A con dueño real LF/SALY y no SUPER_ADMIN, sin activar fuentes sintéticas. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X09` | ¿Se aprueba matriz de compatibilidad apply_batch,decide_batch,report,guard? | A antes de cualquier despliegue, respetando funciones existentes y gates. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q04` | ¿Cómo investigar 166 D sin efectos demostrados? | A; no B/C. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q05` | ¿Pueden 6 A declararse huérfanos sin efectos? | A; clasificación sigue provisional. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X01` | ¿Qué intervalo de revisión LF se aprueba (en días)? | B mientras no haya política real; 90 solo fixture. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X02` | ¿Qué intervalo de revisión SALY se aprueba (en días)? | B mientras no haya política real; 60 solo fixture. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L21-X03` | ¿Se aprueban las 15 familias LF propuestas y la resolución individual de 23 pertenencias dudosas? | A mediante acta separada, sin mutar categorización en este lote. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q06` | ¿Quién debe ser owner real de calidad de reglas de LF? | A con prueba de competencia y vínculo a actor; no B automático. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q07` | ¿Quién será owner de SALY y de cada familia? | A; conservar aislamiento SALY/LF. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `L19-Q08` | ¿Se autoriza un futuro diseño gobernado del registro de owners y recibos de reconciliación? | A como fase separada, sin adoptar sandbox directamente ni tocar RUN. | `cce04b452afd2076cb5a2731249292d54160b8fd3a703c2cb3a6ed0de9c662e5` |
| `B2B-RULE-AUTH-018` | AUTH-018 Login B2B | PENDIENTE_RECONCILIACION_CON_Q01_Q11_POLITICAS_Y_CAMBIO_EXACTO; NO_APROBAR_SOLO_CODIGO | `13f0ac49390f5f62a7e078366174de48d7f6e5b350b47a7744a9c4a1bad7de9d` |
| `B2B-RULE-AUTH-020` | AUTH-020 Login B2B | PENDIENTE_RECONCILIACION_CON_Q01_Q11_POLITICAS_Y_CAMBIO_EXACTO; NO_APROBAR_SOLO_CODIGO | `13f0ac49390f5f62a7e078366174de48d7f6e5b350b47a7744a9c4a1bad7de9d` |
| `B2B-RULE-AUTH-033` | AUTH-033 Login B2B | PENDIENTE_RECONCILIACION_CON_Q01_Q11_POLITICAS_Y_CAMBIO_EXACTO; NO_APROBAR_SOLO_CODIGO | `13f0ac49390f5f62a7e078366174de48d7f6e5b350b47a7744a9c4a1bad7de9d` |

**Advertencias:** la entrada SALY no se aprueba en nombre de dueño LF. FIDO2 L34 fue superado en el bloque 1; B07 padre/hija prevalece sobre columnas antiguas. AUTH-018/020/033 requieren propuesta exacta SHA antes de writer V2. Bloque 2 no altera bloque 1.

**Estado:** `BORRADOR_SIN_DECISION_NI_FIRMA_DEL_DUENO` para 23 entradas. Ningún cambio productivo, cierre o firma humana.
