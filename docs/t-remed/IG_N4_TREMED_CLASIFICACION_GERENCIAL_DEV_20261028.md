# Input Governance LF — T-REMED + N-4: evaluación, clasificación y decisión gerencial (DESARROLLO)

**Fecha:** 2026-10-28 · **Estado:** DEV / NO APROBADO PARA PRODUCCIÓN · **Ruta:** modificación de diseño/código en rama GitHub, sin Router, sin Supabase writes, sin merge.

## 1. Propósito, límites y naturaleza de cada componente

- **T-REMED** es un reparador de brechas de Input Governance: detecta familias incompletas, propone referencias/links y sugiere reglas reutilizables o provenientes de pantallas similares. Conserva sus fases de reconciliación, recomendación, promoción controlada, recibos y reversión. No debe decidir directamente el alcance efectivo.
- **N-4** es la autoridad técnica de *matching*: calcula contexto canónico, valida selectores `applicability_v1` y devuelve coincidencias para un consumidor. El veredicto de pertinencia de negocio proviene de una decisión autorizada, no del algoritmo de coincidencia.
- **Curator / Validator / gestión** revisan la evidencia y resuelven incertidumbre o conflictos; no son nuevos motores persistentes. La calificación de T-REMED es **asesoría**, no autorización.
- **Cascada** significa reutilización condicional de reglas a través del contexto canónico (p. ej. shell, módulo, pantalla y otros atributos *si están documentados en la fuente*). **No** implica que todas las reglas superiores se copien a todas las pantallas ni que exista hoy un operador de precedencia completa negocio→canal→módulo→pantalla.
- **Separación de lifecycle**: que una regla esté `VIGENTE` no significa que tenga alcance universal. Que sea `CANDIDATO` no significa que sea ejecutable; sí puede ser visible para evaluación.

EKB relevante: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`.

## 2. Flujo de evaluación, paso a paso

| Paso | Actor / reutilización | Entrada | Salida y compuerta |
|---|---|---|---|
| 1. Detectar | T-REMED + selector de familias IG | Pantalla/objetivo, estado de familias, reglas propias | Brecha concreta; no recorrer las 47 familias por defecto |
| 2. Recuperar evidencia | Curator con EKB, regla, referencia, política, pantallas comparables | Significado de la regla, condiciones, fuente vigente y excepciones | Evidencia con procedencia y fecha. Sin evidencia => revisión |
| 3. Proponer hipótesis | T-REMED con contexto de N-4 | Alternativas de alcance: p. ej. sesión autenticada, onboarding, módulo, pantalla | Selectores candidatos y contraejemplos; **no ACTIVE** |
| 4. Clasificar | Puntuación ligera del Curator; validador determinístico | Evidencias verificables por criterio | 0..6 por hipótesis, motivos y descartes |
| 5. Desempatar | Criterios + supervisor humano | Dos hipótesis con valor semejante, incompletas o contradictorias | HOLD / HUMAN_REQUIRED; nunca elegir con hash u orden lexical |
| 6. Ratificar | Gerencia responsable de la regla y, si corresponde, Seguridad / Legal / Producto | Ficha de decisión + impacto + alternativa + prueba negativa | Decisión expresa y trazable de alcance; rechazo o aprobación condicionada |
| 7. Publicar alcance | Autoridad de gobernanza existente; no se implementa en este dev lote | Selector validado, dueño, procedencia, versión y vigencia | `applicability_v1.status=ACTIVE` **solo** tras autorización y proceso de integración |
| 8. Heredar dinámicamente | N-4 en cada consulta a pantalla/consumidor | Selector ACTIVE + contexto real canónico | Match automático para descendientes pertinentes; sin vínculos manuales ni % de pantallas |
| 9. Consumir | IG/contrato de pantalla | VIGENTE aplicable / CANDIDATO separado | Contrato operativo sin políticas de reglas candidatas |
| 10. Verificar/cambiar | Validator + auditoría | Nueva pantalla, contraejemplos, revisión de política | Evidencia, diff, currentness; reversión y readback |

**Nota:** las hipótesis que requieren características de autenticación/sesión exigen que el contexto canónico exponga esa capacidad con fuente verificable. No inferirla a partir de textos como "Login". Si la fuente no existe, esa clase de selector queda `UNRESOLVED`; no se inventan atributos.

## 3. Clasificación mínima (propuesta de calibración, no umbral de producción)

Cada hipótesis compite con las demás, en vez de emitir una nota absoluta de "transversalidad".

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Reutilización semántica | Solo caso local | Potencial condicionado / ambiguo | Propósito reutilizable respaldado |
| Condiciones y exclusiones | Alcance indeterminado | Condiciones parcialmente expresables | Condiciones positivas y negativas observables |
| Evidencia y autoridad | Falta fuente / contradicción | Fuente parcial | EKB, política y dueño verificables |

**Puntaje 0..6 no es probabilidad.** En el helper de referencia, 5..6 con ventaja de al menos dos puntos produce `PROPOSAL_READY_FOR_GOVERNANCE_REVIEW`; nunca `APPROVED`. Diferencia de 0 o 1 punto, evidencia faltante o nota débil => `HUMAN_REQUIRED`. Veto de seguridad/legal/autoridad => `BLOCKED_CONFLICT`. Estos números son hipótesis de calibración; validación humana con muestras etiquetadas antes de decidir umbrales reales. El uso del 25% se conserva únicamente como señal estadística de descubrimiento, no alcance.

**Veto determinístico siempre anterior a cualquier score:** `CANDIDATO` no operativa; `UNRESOLVED` no aplica; ausencia de fuente canónica => fail-closed; conflicto de política no se supera con score alto; empate no se decide con orden de consulta.

### Ejemplo (valores ilustrativos)

Una regla "Finalizar por inactividad" puede evaluarse como:
- **Hipótesis A — sesiones autenticadas**: semántica 2, condiciones 2, evidencia 2 = **6/6**, si existen capacidad y política de sesión verificables. El selector de destino debe exigir esa condición; una pantalla preautenticada no coincide.
- **Hipótesis B — cualquier pantalla web**: semántica 1, condiciones 0, evidencia 1 = **2/6**. Se desaconseja por sobreamplitud.
- Veredicto: **propuesta preparada**, sujeta a autorización; al aprobarse se aplica solo a las sesiones que cumplen el selector.
- Regla separada "Expiración de onboarding incompleto": aunque figure en más pantallas, su alcance corresponde al proceso de onboarding, **no** al Login B2B.

Ejemplo de empate: "aplica al módulo" 5 y "aplica al shell" 5. Ninguna se activa; gerente elige con evidencia nueva o limita el alcance. Un veredicto humano no debe eliminar una política superior de seguridad.

## 4. Ficha de decisión gerencial (sin construir una nueva plataforma)

Un caso para Gerencia debe contener **mínimamente**:
- ID/código de regla, versión y hash de la definición y evidencia vigente.
- Intención del cambio (alta, ampliación, excepción, restricción o sustitución), naturaleza funcional, criticidad y dueño.
- Hipótesis A/B, puntajes por criterio, fuentes con referencia, incertidumbres y ejemplos positivos/negativos.
- Selector propuesto, consumidores autorizados, impacto calculado sobre pantallas actuales y comportamiento esperado en pantallas futuras.
- Conflictos con reglas de mayor autoridad, controles de Seguridad/Legal y límites de aprobación.
- Decisión: `APPROVE_SCOPE`, `APPROVE_WITH_CONDITIONS`, `REJECT_SCOPE`, `REQUEST_EVIDENCE` o `ESCALATE_CONFLICT`; justificación, quién decidió, fecha, referencia verificable y cambios obligatorios.
- Recibo trazable y enlace al cambio versionado; **ningún score** es sustituto del recibo.

**Quién decide:** Gerencia/owner funcional sobre cobertura y excepciones de negocio; Seguridad/Compliance/Legal sobre materias de su competencia, con veto cuando proceda; autoridad de migración sobre ejecución técnica; el Curator prepara evidencias, no firma por los anteriores. Se debe **verificar** el binding de `programacion.human_decisions` antes de usarlo para este dominio; existe la tabla, pero no se probó su contrato con T-REMED.

**Cuándo va a humano:** empate, margen estrecho, evidencia ausente, nueva ampliación de alcance no ratificada, excepciones que rebajen una regla superior, o impacto alto. Una regla con selector autorizado puede heredarse luego en miles de pantallas pertinentes sin pedir aprobación en cada nueva pantalla; se reabre decisión si cambian intención, contexto o fuente.

## 5. Cambios técnicos versionados en esta rama

1. Candidato SQL transaccional **`ROLLBACK` por defecto**: quita del resolver de IG la herencia automática `DERIVED_GLOBAL` *sin selector*, mantiene herencia N-4 `DECLARATIVE_APPLICABILITY_V1` y mantiene candidatos explícitos para evaluación. Los tests no deben interpretar este cambio como borrar la posibilidad de heredar.
2. Alinea dos contratos consumidores (`fn_screen_contract_v1` y `fn_b2b_backoffice_login_contract`) con el resolver; sus referencias a políticas operativas excluyen `CANDIDATO` y `pendiente_decision`.
3. Herramienta de referencia *pure Python* de 3 criterios; no conectada a runtime, no escribe registros, no autoriza publicaciones, no crea perfil o motor nuevo.
4. Conserva intactos T-REMED para recomendación, reconciliación, promoción y reversión; todavía **no** se ratifica un selector nuevo de las 95 reglas sin selector ni las 18 `UNRESOLVED`.

## 6. Auditoría y gates pendientes antes de tocar producción

- Snapshot actual: 58 pantallas; 578 reglas; 8.852 vínculos `DERIVED_GLOBAL` que requieren revisión, **no** todas mal aplicadas; 488 candidatas para revisión. Login B2B: 283 actuales = 36 explícitas vigentes + 2 declarativas + 33 candidatas + 212 derivadas.
- Proyección de read-only (no certificación funcional): 5.688 vínculos vigentes sin `DERIVED_GLOBAL`, 488 candidatas; pairset físico completo coincide con N-4 sin las derivaciones (0 extras / 0 faltantes). No aceptar caída de cobertura como éxito funcional sin clasificación y decisión de los afectados.
- Corregir cualquier conflicto de contrato de salida y versionado (`v1.2` actual); no actualizar un contrato en silencio si se rompe la compatibilidad. Los dos contratos se incluyen como candidata de revisión, nunca como hotfix.
- Separar candidatos para consumo operativo vs análisis en todos los consumidores, no solo el Login.
- Probar rollback en PostgreSQL, preimagen de fuente (MD5), ACL, `SECURITY DEFINER`, `search_path`, currentness y readback.
- Regresión 58 pantallas y mínimo 13×47, casos negativos, pantallas inactivas, duplicadas y futuras, más pruebas Curator/Validator con selector de familias (no evaluar todas indiscriminadamente).
- Auditar `fn_t_remed_effective_rules_v1` y otros lectores antes del cutover: continúan mostrando globales **como asesoría**, no deben confundirse con autoridad.
- Entrega posterior: PR de migración por dueño autorizado / source parity / CI exact-head / merge train, **en fase distinta**. No ejecutar SQL en la base sin esa fase.

**Estado real de este artefacto:** versionado solo en rama dev; no integrado a Supabase, sin test SQL transaccional ejecutado, sin contrato gerencial de aprobación instalado. Es documentación + código candidato, no un PASS de producción.
