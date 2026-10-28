# LF / IG — G3: evidencia de pruebas sintéticas del matcher N-4
**28-10-2026 · SELECT-only · PR #3269 · G3 NO PASA · NO RECLASIFICAR**

## 1. Ejecución realmente realizada

Se recuperó la definición vigente de:
- `programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)`, MD5 de `pg_get_functiondef`: `3b912c7872aceff83de24e9e8d1ad934`.
- `programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)`, MD5: `1123257c0c6c7eb1e2aa26783f3ccc0a`.

Se ejecutaron **23 vectores sintéticos de SELECT** desde el archivo versionado:
`sandbox/lf_contract_gate_test/input_governance/ig_n4_preclass_synthetic_matcher_v2_20261028.sql`.

**18 PASS y 5 FAIL contra las expectativas propuestas en el contrato director**, no contra un contrato productivo ya ratificado. Todos los tests son evaluaciones directas del matcher; no se alteró ningún selector, regla, pantalla, permiso, fuente ni workflow. **No se ejecutó el pipeline de clasificación ni se obtuvieron recibos gerenciales**.

| Caso | Resultado actual | Resultado de diseño | Problema |
|---|---|---|---|
| **T07** `EXISTS` sobre JSON `null` | TRUE | FALSE/no-match | JSON null no constituye atributo presente y válido |
| **T08** `EQ(value=null)` sobre JSON `null` | TRUE | FALSE/no-match por defecto | Igualdad literal no equivale a hecho negativo autorizado |
| **T09** `IN(values=[null])` sobre JSON `null` | TRUE | FALSE/no-match por defecto | Inclusión literal no equivale a fuente confiable |
| **T22** `EXISTS(target)` | TRUE | No autorizar alcance universal implícito | **Falla de política de publicación**, no necesariamente error del comparador booleano. Una política realmente universal exige autorización expresa |
| **T23** cláusula con `extra_guard` desconocido | TRUE | FALSE/no-match | El matcher ignora silenciosamente atributos de cláusula no reconocidos |

Los otros 18 casos sí produjeron el booleano previsto para `EQ`, `IN`, `EXISTS`, `all/any`, schema inválido, cambio de consumer, estado UNRESOLVED, operador desconocido, ausencia real de campo y targets sintéticos compatibles/incompatibles.

**Precaución de interpretación:** T08/T09 son incompatibilidades con la política propuesta de fail-closed. El motor actual compara valores JSON de forma consistente con su implementación; debe determinarse si se necesita semántica intencional `null` para algún futuro contrato antes de modificarlo. La prueba no prueba un incidente real con los selectores desplegados.

## 2. Hallazgo complementario de diseño sin mutación

En los 14 selectores ACTIVE vigentes, todos incluyen una cláusula `target.screen.id IN (...)`; **12 solo usan el ID de pantalla** y dos incorporan criterios de módulo o shell. Ninguno emplea `EXISTS` ni JSON null en los valores de las cláusulas observadas. Por tanto:
- El lenguaje del matcher es genérico, pero la configuración de muchos selectores actuales no está orientada a herencia dinámica por capacidades.
- El ID de pantalla es correcto cuando la política es realmente local. No reemplazarlo por ámbito más amplio sin autoridad.
- Los casos sintéticos de pantalla nueva muestran que un selector que usa un atributo compartible puede funcionar sin ID, **no** que las 12 reglas actuales deban extenderse ni que ya existan tales capacidades en la fuente canónica.

## 3. Cobertura G3 frente al protocolo S01–S14

| Caso de protocolo | Qué se probó | Qué falta antes de PASS |
|---|---|---|
| S01 norma con cobertura A/B autorizada | Matching por `IN` T03–T04 | Procedencia/ratificación real de alcance |
| S02 secuencia onboarding vs login | Exclusión por `EQ` T02 | Prueba semántica y evidencia de procesos |
| S03 sesión y preauth | Capacidad conocida/missing T18–T19 | Trivalencia SOURCE/UNKNOWN real |
| S04 pantalla nueva compatible | T17 (contexto sintético con nuevo ID) | Fuente real y publicación gobernada |
| S05 pantalla nueva del mismo módulo no compatible | T18 | Test de integración de pantalla registrada |
| S06 sin módulo, regla independiente | T05–T09 y caso real null | F01–F02 deben corregirse o refinar contrato |
| S07 ausencia de sesión no bloquea regla visual | Probes sintéticos separados, no ejecución de pipeline | Orquestación por regla y fuente bajo demanda |
| S08 reglas compatibles | No ensayado por matcher | Composición verificada por Validator |
| S09 efectos contradictorios | No ensayado por matcher | Política de conflicto/precedencia |
| S10 regla local intenta degradar superior | No ensayado por matcher | Competencias y veto con recibo |
| S11 CANDIDATO + policy_id | Matcher no recibe lifecycle | Verificación de consumidor operativo |
| S12 UNRESOLVED/NOT/UNKNOWN | T11/T14 y T07–T09 FAIL | Prueba trivalente, no activar NOT sobre NULL |
| S13 score empate o veto | No ensayado por matcher | Evidencia auxiliar + arbitraje real |
| S14 nueva naturaleza `MODEL_GAP` | No ensayado por matcher | Control de versionado de taxonomía y revalidación |

**Dictamen: G3 parcialmente probado, NO PASS integral.** La siguiente tarea NO es reclasificar; es ratificar los ajustes G2 v2.1 y preparar pruebas de integración de los puntos no cubiertos, sin construir un runtime alternativo por comodidad.

## 4. Trazabilidad y reglas de cierre

Referencias:
- Contrato director v2: `IG_N4_TREMED_CONTRATO_ESTRATEGIA_DEFINICIONES_REGLAS_V2_20261028.md`.
- Adenda G2 v2.1 F01–F06, H16–H21: `IG_N4_TREMED_G2_AUDITORIA_Y_AJUSTES_DE_CONTRATO_V21_20261028.md`.
- SQL ejecutado: `sandbox/lf_contract_gate_test/input_governance/ig_n4_preclass_synthetic_matcher_v2_20261028.sql`.
- EKB activo: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001` y `INPUT-GOV-CONSUMER-BINDING-001`.

Se exigen: caso negativo por nueva primitiva, prueba de publish/admission, source hashes, integridad de autorizaciones, schema actual y comparación exacta de selectores; validación independiente; G4 de autoridad. Si no existe evidencia de alguno, resultado **NO_VERIFICADO**. Los cinco FAIL no deben mutarse a “éxito” cambiando los valores esperados sin una decisión de diseño documentada.
