# LF / WEB-001 — Mapa de controles a destinos del perfil (propuesta, no autoridad)

**Estado:** PROPUESTA_SOLO_LECTURA · **No incorporar automáticamente al caso oficial**.
**Perfil**: `systemic_root_cause_repair_lf`.
**Fuente de pasos**: `profiles/systemic_root_cause_repair_lf/SKILL.md` en `main`, Git blob `39fe66baf7608eef5117edd5a5f40578c594a115` (2026-10-31).
**Caso oficial leído**: `skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/WEB-001.case.json`, Git blob `f8de1e08c65f69099f7fdfde5b617e81e30f58d3`.
**Readback del comparador existente**: [CI Edge R17 #41214802660](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41214802660), salida `WEB001_TRUSTED_GROUP2_READBACK`, suite de pruebas usando `operational_coverage_v1.measure`.

## Comparación REAL de registros conservados, sin inferencia de mejora

- BASE `RUN-WEB001-BASE-20261029`, árbol `db152f0aa2c72a4476e4e428a28a619a7b402d70f866cbe294de60ef230cb701`, output SHA-256 `dfb794906b7bd076bc1ac0c6c77417e1b885d4d7a2a7baac3c263d5028dfd0d7`.
- CANDIDATO `RUN-WEB001-CANDIDATE-20261029`, árbol `2f4ac419ee3a49b2366a684daf4df2613a28426e77f0a880851fe07841105381`, output SHA-256 `64711b7782349090c0f72719d1fd84ea84d49aa65154518ce9bc9521d9527e9e`.
- Las condiciones de las dos corridas son **idénticas según el registro**, pero ambas tienen `attestation=NONE`: no existe atestación de ejecución independiente, prueba holdout nueva o veredicto semántico suficiente.
- Resultado: **1 mejorado, 8 conservados, 4 sin mejora y 1 regresado**. No declarar evolución.

## Matriz con destino sugerido (NO_VERIFICADO_CANONICO)

| ID de control | Original | Evolucionado | Destino textual existente (Git SKILL.md) | Cambio sugerido | Condición del destino |
|---|---|---|---|---|---|
| OP01 | PASS | PASS | `Runtime method capsule`, ítem 10 (L27) | CONSERVAR | Ancla textual presente |
| OP02 | FAIL | PASS | `Working method`, ítem 3 «Validate the typed candidate before freeze» (L92); requiere validador `validators/runtime_validate.py` | VERIFICAR / CONSERVAR | Comprobar consumidor del esquema; no atribuir mejora al paso sin prueba causal |
| OP03 | PASS | PASS | `Runtime method capsule`, ítem 9 (L26) | CONSERVAR | Ancla textual presente |
| OP04 | PASS | PASS | `Output trajectory`, ítem 33 (L243) | CONSERVAR | Ancla textual presente |
| OP05 | PASS | PASS | `Gap-resolution cascade`, ítem 5 (L109–L111) | CONSERVAR | Ancla textual presente |
| OP06 | PASS | PASS | `Output trajectory`, ítem 21 (L216) | CONSERVAR | Ancla textual presente |
| OP07 | PASS | PASS | `Output trajectory`, ítem 31 (L241) | CONSERVAR | Ancla textual presente |
| OP08 | PASS | PASS | `Output trajectory`, ítem 27 (L233–L237) | CONSERVAR | Ancla textual presente |
| OP09 | PASS | PASS | `Output trajectory`, ítem 24 (L222) | CONSERVAR | Ancla textual presente |
| OP10 | FAIL | FAIL | `Gap-resolution cascade`, ítem 3 (L107) | MODIFICAR — explicitar política de consulta de reglas y salida `policy_resolution` | El ítem actual no cubre el contrato completo |
| OP11 | FAIL | FAIL | `Gap-resolution cascade`, ítems 2–3 (L106–L107) | AGREGAR comportamiento condicionado de dos búsquedas N1/N2 cuando el caso lo exige | No asignar subnumeración sin revisar método/contrato |
| OP12 | FAIL | FAIL | `Gap-resolution cascade`, ítem 3 (L107) | MODIFICAR — N1 como primera consulta condicionada por autoridad del caso | No universalizar N1 a todos los perfiles |
| OP13 | FAIL | FAIL | `Gap-resolution cascade`, ítem 3 (L107) | MODIFICAR — N2 después de N1 en este caso | No universalizar N2 a todos los perfiles |
| OP14 | PASS | **FAIL** | `Gap-resolution cascade`, ítem 5 (L109–L111) | **REPARAR REGRESIÓN** — registro explícito de intentos y evidencia en `owner.derivation.authority_research.attempts` | Bloqueante para aceptar evolución |

**Importante:** el perfil usa un `SKILL.md` con varias secciones e ítems enumerados. Estos números **son los de las secciones del Reparador, no los del Profile Updater**. Esta tabla indica localizadores textuales candidatos, no identificadores de pasos canónicos o rutas autorizadas.

## Dictamen por categorías

- **8 conservar:** no cambiar los controles preservados por el caso.
- **1 mejora (OP02):** la validez del output mejoró; investigar si el cambio se explica por comportamiento del perfil, configuración del validador o ambos. No inventar causalidad.
- **4 sin mejora (OP10–OP13):** falta incorporar la consulta de reglas N1/N2 al método del Reparador y demostrarla con un nuevo RAW. Es un requisito de este caso, **no una obligación universal de todas las operaciones o perfiles**.
- **1 regresión (OP14):** bloquear evolución y reintroducir la evidencia de intentos al derivar responsable; volver a ejecutar caso y regresiones.

## Próximo trabajo autorizado / no autorizado

1. Contrastar la vinculación de cada control con el contrato de runtime y método dinámico real, antes de convertirla en `destination_bindings` del caso.
2. Verificar que el caso de prueba y los metadatos del destino tienen la versión exacta aprobada. **No** modificar `WEB-001.case.json` ni `SKILL.md` desde esta PR de matriz; editar esa fuente oficial requiere ruta gobernada específica.
3. Probar ORIGINAL vs EVOLUCIONADO con mismo caso literal, ambas salidas RAW y nuevo juicio semántico independiente; comparar todas las filas, bloquear cualquier `PASS→FAIL`.
4. Solicitar revisión verdaderamente independiente de la PR #3420. Los presentes hallazgos son autoauditoría, no dictamen externo.

**Estado:** las 14 propuestas están documentadas, pero **0/14 se promueven a destino canónico gobernado**. No confundir referencias a líneas con aceptación de nuevos pasos.
