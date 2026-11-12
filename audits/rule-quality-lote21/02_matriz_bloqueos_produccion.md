# Lote 21 — Matriz de bloqueos de producción y secuencia de cierre

**Estado de todos los bloqueos:** ABIERTO / NO-GO. Orden propuesto, NO procedimiento ejecutado. **OBJETIVO** para datos SQL de presencia/cantidad; **REQUIERE_REVISION_SEMANTICA** para cierre propuesto, dependencias y aceptación. Al resolver un bloqueo debe emitirse un recibo firmable independiente, no basta una declaración textual.

## 1. B02_RUN_SCOPE — Alcance de RUN abiertos (32 vs 232)
- **Qué lo cerraría:** Dueño identifica cohorte literal con firma y define si cubre 232; conserva todos hasta decisión.
- **Evidencia exacta aceptable (SUGERENCIA):** SELECT R01 232; SELECT S21_01 232/184/>30d; CSV IDs exactos de 232 y SHA del freeze de cohorte.
- **Quién la aporta / firma:** Dueño LF + Operaciones
- **Depende de:** Ninguna; abre diagnóstico dirigido
- **Decisiones:** L19-Q01
- **Estado:** PENDIENTE.

## 2. B03_RUN_EFFECTS — Reconciliación de efectos y leases
- **Qué lo cerraría:** Lectura independiente por RUN de escritor, estados, guardas SUCCEEDED, idempotencia y destino final; probar worker/heartbeat.
- **Evidencia exacta aceptable (SUGERENCIA):** Recibos RUN_PREIMAGE, EFFECT_RECON, LIVENESS, hashes de estado y commit destino; 8 leases vencidos; clasificación A/B/C/D revalidada.
- **Quién la aporta / firma:** Operaciones, DBA, custodios GitHub y proveedores; firma dueño
- **Depende de:** B02_RUN_SCOPE
- **Decisiones:** L19-Q02..Q05
- **Estado:** PENDIENTE.

## 3. B06_OWNER — No existe registry operativo owner por proyecto/familia
- **Qué lo cerraría:** Dueño nombra owner LF y SALY distinto de SUPER_ADMIN; registrar project_code, owner_profile_code, actor(sub), scope y firma verificable.
- **Evidencia exacta aceptable (SUGERENCIA):** Acta owner; bindings registrados + readback; negativos SUPER_ADMIN/cross-project; SELECT O3 / S21_05.
- **Quién la aporta / firma:** Dueños LF/SALY + IAM/Gobernanza
- **Depende de:** B02_RUN_SCOPE para autorizaciones de RUN; B08_IDENTITY para ejecución
- **Decisiones:** L19-Q06..Q08; L21-X08
- **Estado:** PENDIENTE.

## 4. B08_IDENTITY — Supabase Auth/PostgREST/roles y actor no acreditados
- **Qué lo cerraría:** Probar JWT real, issuer/aud/JWKS, sub→actor→perfil por proyecto, RLS/GRANT, ausencia de fallback a session_user o HMAC de ensayo.
- **Evidencia exacta aceptable (SUGERENCIA):** Recibo real de identity boundary, claims verificados por servicio, outcomes positivos/negativos, auditoría y readback de rol efectivo.
- **Quién la aporta / firma:** IAM/Seguridad + dueño
- **Depende de:** Contrato owner B06 definido; antes de activar writers
- **Decisiones:** L21-X06
- **Estado:** PENDIENTE.

## 5. B01_MFA — MFA obligatorio y factor 19 CANDIDATO
- **Qué lo cerraría:** Dejar AUTH-022→018 identificada. Promover solo con SAML/IdP admins, OTP Brevo entrega+validación, ADR-003 M1, factor 19 VIGENTE y prueba no AUTHENTICATED antes de MFA.
- **Evidencia exacta aceptable (SUGERENCIA):** Matriz 11 candidatas owner-confirmadas, policy 19 y 20, recibos SAML/IdP, Brevo API+webhook, tests negativos step-up, prueba fail-closed y trazabilidad por profile_id.
- **Quién la aporta / firma:** Dueño LF + IAM/Security + proveedor
- **Depende de:** B08_IDENTITY; decision L16-Q01, L21-X12
- **Decisiones:** L16-Q01; L21-X12; L16-Q11
- **Estado:** PENDIENTE.

## 6. B04_FAMILY — 15 familias y 23 adscripciones dudosas, frecuencia sin decisión
- **Qué lo cerraría:** Dueño firma mapeo primario LF, 23 casos uno a uno y política periodos LF/SALY; definir familias propias SALY.
- **Evidencia exacta aceptable (SUGERENCIA):** Acta de 15 familias con 23 veredictos, mapa categoría→familia sin colisiones, fuente L12/L16, LF/SALY intervalos expresos (90/60 no autorizados).
- **Quién la aporta / firma:** Dueños LF/SALY + Gobernanza
- **Depende de:** B06_OWNER (owner por familia)
- **Decisiones:** L16-Q07; L21-X01..X03
- **Estado:** PENDIENTE.

## 7. B05_RULES — 57 pendientes, 3 refs y 20 pares semánticos
- **Qué lo cerraría:** Decisiones de dueño sobre responsable y orden de los 57; no igualar por nombre y no promover candidatos sin reglas/hard gates.
- **Evidencia exacta aceptable (SUGERENCIA):** CSV 57 con respuesta, dictamen literal 3 dependencias, revisión de 20 pares con entidad/operación, SHA SELECT L16.
- **Quién la aporta / firma:** Dueño LF + especialistas Legal/Negocio/Seguridad
- **Depende de:** B04_FAMILY; B01_MFA para REF MFA
- **Decisiones:** L16-Q06; L16-Q07; L16-Q12
- **Estado:** PENDIENTE.

## 8. B12_LEGACY — Cuatro funciones legadas coexisten
- **Qué lo cerraría:** Compatibilidad contractual y regresión antes/después, firmas, permisos, resultados, errores e idempotencia; conservar apply_batch/decide_batch/report/guard.
- **Evidencia exacta aceptable (SUGERENCIA):** SELECT S21_04 cuatro funciones y firmas + diff función PG18 contra vivo autorizado + gates MD5 y suite positiva/negativa.
- **Quién la aporta / firma:** Arquitectura/DBA + dueño
- **Depende de:** B08_IDENTITY, B05_RULES; antes de migración
- **Decisiones:** L21-X09
- **Estado:** PENDIENTE.

## 9. B13_BACKUP — Backup físico y PITR no acreditados
- **Qué lo cerraría:** Política RPO/RTO, cifrado, retención, custodia, snapshot físico y PITR verificado documentalmente; cubrir LF/SALY.
- **Evidencia exacta aceptable (SUGERENCIA):** Receipt proveedor/backups con IDs verificables, retención y ventana PITR, checksums/metadata, firma DBA y custodio externo.
- **Quién la aporta / firma:** DBA/Continuidad + dueño
- **Depende de:** Ninguna; imprescindible antes de cualquier DDL
- **Decisiones:** L21-X10
- **Estado:** PENDIENTE.

## 10. B14_RESTORE — No hay prueba de restauración
- **Qué lo cerraría:** Restaurar backup/PITR en aislamiento, comprobar integridad, tiempos y readback de fuentes y claves.
- **Evidencia exacta aceptable (SUGERENCIA):** RUN restauración, medio/instancia aislada, SHA/diff antes-después, RPO/RTO medidos, evidencia auditada de recuperación.
- **Quién la aporta / firma:** DBA/Continuidad + dueño
- **Depende de:** B13_BACKUP
- **Decisiones:** L21-X11
- **Estado:** PENDIENTE.

## 11. B07_SCHEMA — Lifecycle no representable en fuentes
- **Qué lo cerraría:** Autorizar solo plan UP/DOWN, backfill, RLS, contratos, índices, efectos en consumidores y reversión no destructiva; LF 4 campos, SALY 5 (incluye lifecycle_state).
- **Evidencia exacta aceptable (SUGERENCIA):** DDL draft L20 con blobs/SHA, aprobación de diseño, prueba de migración con datos equivalentes, readback source/L13 y rollback seguro post-backfill.
- **Quién la aporta / firma:** Dueños LF/SALY + DBA
- **Depende de:** B04_FAMILY, B08_IDENTITY, B12_LEGACY, B14_RESTORE
- **Decisiones:** L21-X04; L21-X05
- **Estado:** PENDIENTE.

## 12. B09_E2E — Flujo nativo Router→perfil→RUN→IG→Step70/OIDC→cierre no probado
- **Qué lo cerraría:** Prueba real en entorno gobernado de la ruta oficial sin atajos; separar evidencia RAW y juez independiente.
- **Evidencia exacta aceptable (SUGERENCIA):** ACT-0001 Gate2, handoff, RUN ID, 11 pasos, Curator/Validator reales, cita exacta, Step70+OIDC, firma owner, fuente-readback, cierre terminal y pruebas negativas.
- **Quién la aporta / firma:** Plataforma/IG/Seguridad + dueño
- **Depende de:** B08_IDENTITY, B06_OWNER, B01_MFA si afecta Login, B07_SCHEMA; B03_RUN_EFFECTS
- **Decisiones:** L21-X07
- **Estado:** PENDIENTE.

## 13. B10_BUSINESS — Contratos de pagos, ledger, pricing, socio/aliado e IDV
- **Qué lo cerraría:** Decidir contratos de negocio y técnico con fuentes aprobadas; probar callbacks, integridad y operaciones.
- **Evidencia exacta aceptable (SUGERENCIA):** Matriz responsables, ledger canónico/conciliación, proveedor PCI, precios, SLA settlement, IDV, tests y readback.
- **Quién la aporta / firma:** Dueño LF + Producto/Finanzas/Operaciones
- **Depende de:** B08_IDENTITY, B05_RULES; B09_E2E antes de operar
- **Decisiones:** L16-Q02,Q03,Q05,Q10,Q11
- **Estado:** PENDIENTE.

## 14. B11_LEGAL — Legales/consentimientos, visuales y mora no aprobados
- **Qué lo cerraría:** Legal aprueba textos/consentimientos/Anexo I, terminación/mora y claims visuales solo con fuentes.
- **Evidencia exacta aceptable (SUGERENCIA):** Versiones exactas con firmas, documentos vigentes, capturas visuales approved, pruebas de rutas y no-publicación de placeholders.
- **Quién la aporta / firma:** Dueño LF + Legal/UX/Negocio
- **Depende de:** B05_RULES; antes de liberar superficies
- **Decisiones:** L16-Q04,Q08,Q09
- **Estado:** PENDIENTE.

## Orden visual propuesto

`B02→B03` (congelar y conciliar RUN); `B06→B08→B01` (owners/identidad/MFA); `B04→B05` (taxonomía y reglas); `B12` (compatibilidad); `B13→B14` (protección); `B07` (esquema); `B09` (E2E real); `B10 + B11` (cierre negocio/legal). Las cadenas pueden avanzar en paralelo cuando no hay dependencia declarada; **ningún bloque es aprobable solo por porcentaje**.

## Fuentes trazables
- L16 `audits/rule-quality-lote16/07_evidencia_select.sql` @63c96935dd594f13cec4e3291c2a58931094cb7a; SHA del inventario `59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9`.
- L19 `audits/rule-quality-lote19/09_manifest.md` @5ee4c92632d41c31fdec6807dee99a2207104d4a; R01 `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0`.
- L18 report blob `64f763defa2e929e87539a5507126860ffd61577`, CI HEAD `abeea154a559759dcf2f56f42c8fd106ca768b64`.
- L20 report blob `4b28a22978061bb049c541a0713636597e830d3b`, CI HEAD `b7e362b36e82b4075bc9effc363ec777c6756d87`.
- L21 SELECT `S21_01..S21_06` `06_select_evidencia_live.sql`, SHA específicos en archivo.
- Backup físico, PITR, restauración real y firmas owners **NO_VERIFICADO**; no se emite recibo falso.
