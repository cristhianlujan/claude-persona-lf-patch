# LF E21 — Lista canónica de login/sesión B2B (SELECT 2026-11-16)

**Criterio SQL reproducible:** todas las `B2B-RULE-AUTH-*` (incluida `AUTH-STATE-001`), `B2B-RULE-SESSION-*`, y las seis transversales aplicables: `RATE-001`, `TIMEOUT-001`, `PRIVACY-001`, `RETENTION-001`, `INPUT-APPLICABILITY-001`, `SECURITY-BASELINE-001`.

**Alcance:** hay 56 reglas de la familia funcional extendida; de ellas, 40 están vinculadas físicamente a pantalla 51 (`B2B-AUTH-001`) y las otras 16 son dependencias de pantallas de recuperación, OTP, MFA u otras. No inventar vínculos a 51.

**Corrección de la lista anterior:** el conjunto previo de 37 contenía `PRIVACY-001`, `RETENTION-001` y omitía `INPUT-APPLICABILITY-001`, `TIMEOUT-001` por una selección manual incongruente, no por una decisión de alcance ni por evidencia de no-aplicabilidad. Las cuatro aplican al login como transversales; no se deben intercambiar ni omitir. Al incorporar AUTH-049 el universo de pantalla 51 es 40.

**Lote 1 declarado como 12 por mensaje del owner pero enumera realmente 13 reglas VIGENTE.** Se adopta la lista explícita de 13. Este PR ensaya solo comportamiento de seguridad de base existente; no acredita implementación Spring Boot/OIDC ni registra falsos PASS. Para acreditar 40 puntos A cada regla exige test completo de su propio comportamiento y CI PG17/18 con provenance.

| Código canónico | Estado SELECT | En pantalla 51 | Tratamiento | Motivo de inclusión |
|---|---|---|---|---|
| `B2B-RULE-AUTH-001` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Denegar por defecto |
| `B2B-RULE-AUTH-002` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Aislamiento por empresa |
| `B2B-RULE-AUTH-003` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: MFA según políticas centrales de perfil y acción |
| `B2B-RULE-AUTH-004` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Mensaje genérico ante credenciales inválidas |
| `B2B-RULE-AUTH-005` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Contraseña solo en runtime |
| `B2B-RULE-AUTH-006` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Recuperación de contraseña visible y separada |
| `B2B-RULE-AUTH-007` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Mostrar u ocultar contraseña sin alterar el valor |
| `B2B-RULE-AUTH-008` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Protección anti-bot invisible en Login |
| `B2B-RULE-AUTH-011` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Entrada compatible con gestores de credenciales |
| `B2B-RULE-AUTH-012` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Un solo intento de autenticación en vuelo |
| `B2B-RULE-AUTH-013` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Autenticación desacoplada y fail-closed |
| `B2B-RULE-AUTH-014` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Resultados normalizados del servicio de autenticación |
| `B2B-RULE-AUTH-015` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Contrato de solicitud hacia la capa de autenticación LF |
| `B2B-RULE-AUTH-016` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Timeout y reintento controlado de autenticación |
| `B2B-RULE-AUTH-017` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Sobre de respuesta seguro de autenticación |
| `B2B-RULE-AUTH-018` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: MFA obligatorio antes de sesión autenticada |
| `B2B-RULE-AUTH-019` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Factor de segundo control gobernado por política central |
| `B2B-RULE-AUTH-020` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Recuperación del segundo control sin bypass |
| `B2B-RULE-AUTH-021` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Protección adaptativa contra abuso de autenticación |
| `B2B-RULE-AUTH-022` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Creación de sesión únicamente tras autenticación completa |
| `B2B-RULE-AUTH-023` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Destino post-login resuelto contra rutas autorizadas |
| `B2B-RULE-AUTH-024` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Auditoría segura de eventos de autenticación |
| `B2B-RULE-AUTH-025` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Errores de autenticación canónicos y trazables |
| `B2B-RULE-AUTH-026` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Proveedor OIDC desacoplado; binding pendiente del spike M1 |
| `B2B-RULE-AUTH-027` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Recuperación sin enumeración de cuentas |
| `B2B-RULE-AUTH-028` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Solicitud de recuperación mediante la frontera LF |
| `B2B-RULE-AUTH-029` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: OTP de recuperación verificado y contexto restringido |
| `B2B-RULE-AUTH-030` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Cambio de contraseña gobernado por política central |
| `B2B-RULE-AUTH-031` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Recuperación finaliza con nueva autenticación completa |
| `B2B-RULE-AUTH-032` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Entrada de nueva contraseña compatible y segura |
| `B2B-RULE-AUTH-033` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Enrutamiento del segundo control gobernado por política |
| `B2B-RULE-AUTH-034` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Desafío OTP por correo verificado por LF |
| `B2B-RULE-AUTH-035` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Contrato legado de enrolamiento TOTP fuera del flujo normal |
| `B2B-RULE-AUTH-036` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Contrato de acciones del Login |
| `B2B-RULE-AUTH-037` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Desafío OTP de recuperación por correo |
| `B2B-RULE-AUTH-038` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Expiración y reenvío OTP gobernados por política |
| `B2B-RULE-AUTH-039` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Ciclo de vida del dispositivo confiable |
| `B2B-RULE-AUTH-040` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Token opaco de dispositivo confiable protegido por servidor |
| `B2B-RULE-AUTH-041` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Uso único, reenvío estable y renovación controlada del OTP por correo |
| `B2B-RULE-AUTH-042` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Rate limit de recuperación aislado por operación funcional |
| `B2B-RULE-AUTH-043` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Rate limit de segundo control aislado por operación funcional |
| `B2B-RULE-AUTH-044` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Entrega OTP mediante Brevo Transactional Email API |
| `B2B-RULE-AUTH-045` | CANDIDATO | No | L2 CANDIDATO | Comportamiento auth: Autenticación del webhook de entrega Brevo |
| `B2B-RULE-AUTH-046` | VIGENTE | Sí | L1 VIGENTE | Comportamiento auth: Precedencia de seguridad sobre divulgación visual antes de sesión operativa |
| `B2B-RULE-AUTH-047` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Aviso de Bloq Mayús ligado a política de intentos de contraseña |
| `B2B-RULE-AUTH-048` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Divulgación progresiva local sin duplicar lógica de autenticación por viewport |
| `B2B-RULE-AUTH-049` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Contabilización de fallos de contraseña sin umbral asumido |
| `B2B-RULE-AUTH-STATE-001` | CANDIDATO | Sí | L2 CANDIDATO | Comportamiento auth: Máquina de estados del flujo de autenticación B2B |
| `B2B-RULE-INPUT-APPLICABILITY-001` | VIGENTE | Sí | Transversal VIGENTE | Dependencia transversal: Aplicabilidad explícita de Feature Flags e I18N en autenticación B2B |
| `B2B-RULE-PRIVACY-001` | VIGENTE | Sí | Transversal VIGENTE | Dependencia transversal: PII prohibida en telemetría |
| `B2B-RULE-RATE-001` | VIGENTE | Sí | L1 VIGENTE | Dependencia transversal: Límites por recurso |
| `B2B-RULE-RETENTION-001` | VIGENTE | Sí | Transversal VIGENTE | Dependencia transversal: Retención gobernada por política central pendiente |
| `B2B-RULE-SECURITY-BASELINE-001` | CANDIDATO | Sí | L2 CANDIDATO | Dependencia transversal: Baseline técnico de seguridad del Login B2B |
| `B2B-RULE-SESSION-001` | VIGENTE | Sí | L1 VIGENTE | Sesión compartida: Inactividad controlada |
| `B2B-RULE-SESSION-002` | VIGENTE | Sí | L1 VIGENTE | Sesión compartida: Rotación y concurrencia gobernadas por políticas centrales |
| `B2B-RULE-TIMEOUT-001` | VIGENTE | Sí | L1 VIGENTE | Dependencia transversal: Timeout y reintentos centralizados |

## Siguiente paso Step50 (propuesta, no ejecutado)

- `scripts/lf_profile_native_resume.py:1487-1512`: recibe el RAW del perfil, ejecuta el validador y lo envía a `profile_native_continue_v1`; **no ejecuta** cambio de reglas o PR/Train y no captura efectos antes/después.
- `scripts/lf_profile_native_resume.py:669-691`: en SRCR separa `candidate` y `evidence_manifest`; las referencias de fuentes externas solo se adjuntan como pruebas de transporte, no como recibos de una escritura real.
- `profiles/systemic_root_cause_repair_lf/SKILL.md:29,59-79`: exige reparación material con readback para `EXECUTED_WITH_READBACK`; incluye todavía una prohibición absoluta de promoción en `SKILL.md:12,29,374` que contradice el E20 condicionado por dueño. Requiere corregir esa contradicción sin conceder autoridad de promoción al perfil.
- `profiles/systemic_root_cause_repair_lf/schemas/output.schema.json:2266-2409`: `repair_execution` admite `AUTHORIZED_NOT_EXECUTED` y `EXECUTED_WITH_READBACK`; no obliga prueba de efecto vinculada a 40/50/60/70 para cada regla.
- `public.lf_rule_promotion_score_v1(text,text)` (SELECT): B busca `profile_output.deliverable_created.product_decision.source_refs[*].source_ref = supabase://lf_ops.reglas/<RULE_CODE>`. El RAW SRCR actual no llena ese contrato Product Director, aunque exista `profile_output.implementation_package`.
- PR propuesto posterior (sin ejecutar corrida): extender bridge/runner para adjuntar **recibos reales** de un PR/Train verificado por regla, con before/after + `source_ref` canónica en un contrato SRCR propio; enseñar al scorer a leer ambas rutas solo con hashes del RAW y Step40/60/70 válidos. Prohibir rellenar esos recibos desde texto del modelo.
- No tocar #4040, E7/E8 ni una corrida ya cerrada.
