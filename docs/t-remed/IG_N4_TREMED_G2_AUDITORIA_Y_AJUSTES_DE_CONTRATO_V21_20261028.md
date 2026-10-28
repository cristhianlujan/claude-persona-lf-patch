# LF / Input Governance — G2, auditoría de estrategia y ajuste del contrato v2.1
**28-10-2026 | DISEÑO PROPUESTO / NO RATIFICADO / NO_RECLASSIFY**  
Base: contrato director v2 de PR #3269, EKB `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`; funciones N-4 leídas del catálogo vivo sin ejecutar cambios.

## 1. Qué se revisó y qué se conserva

Se preservan: T-REMED para descubrir/corregir, N-4 para matching, Curator para investigación, Validator para contraste independiente, gerencia/owner para alcance y autoridades especializadas para veto. Nada de nuevo motor, nuevos niveles universales de cascade ni clasificar por volumen. Antes de usar las reglas existentes: **estrategia → definiciones → reglas → pruebas sintéticas → ratificación → reclasificación**.

El contrato v2 **no se aprueba tal cual**. Requiere las correcciones de semántica y autoridad F01–F06. Se registran separadamente para no modificar silenciosamente una versión ya revisada.

## 2. Resultados de pruebas de N-4 y correcciones normativas

Prueba SELECT real, función `fn_input_rule_selector_matches_v1(jsonb,jsonb)` + `fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)`. Fixture `ig_n4_preclass_synthetic_matcher_v2_20261028.sql`: **23 casos; 18 PASS, 5 FAIL contra el contrato objetivo**. PASS es solo de su comportamiento de coincidencia, NO de autorización, evaluación semántica o el sistema completo.

| Hallazgo | Comportamiento actual probado | Riesgo y clasificación | Corrección de contrato (fase de diseño) | Test/gate |
|---|---|---|---|---|
| **F01 — EXISTS/JSON null** | `EXISTS(target.module)` devuelve TRUE cuando `target.module` es **JSON null**; comprobado además en pantalla real `HOME_FAQ` | Un dato no válido puede fingir precondición presente. Brecha de semántica del matcher | `EXISTS` significa atributo presente **y valor distinto de JSON null**, con origen confiable. Ausencia/JSON null → UNKNOWN en diagnóstico, **no MATCH** para autorización | T07 FAIL, comparar con T06 PASS. Test nuevo con fuente real nula y campo omitido |
| **F02 — comparación literal a JSON null** | `EQ(module,null)` y `IN(module,[null])` devuelven TRUE; dentro de v1 es igualdad JSON | Puede habilitar regla por “ausencia”, aunque no exista prueba de que la ausencia sea una condición permitida | No interpretar `null` como negación válida. Default fail-closed para condición de autorización; si negocio necesita prueba positiva de “no tiene módulo”, definir semántica explícita, fuente y autorización mediante evolución versionada. **No prohibir casos legítimos sin analizar uso real** | T08/T09 FAIL; demostrar compatibilidad y efecto antes de cambiar |
| **F03 — selector tautológico** | `EXISTS(target)` da TRUE en todo contexto normal, pese a que v1 rechaza selector sin cláusulas | Implica cobertura general sin condición restrictiva | En el **gate de publicación**, detectar selectores que no restringen el universo. Rechazar expansión implícita; una norma verdaderamente universal es posible **solo con autorización explícita de alcance total**, procedencia y pruebas de consumidores. No declarar inválidas por defecto las políticas universales legítimas | T22 FAIL respecto de “sin autorización”. **No atribuir el fallo únicamente al matcher**: falta gate de publicación |
| **F04 — atributos extra ignorados** | Un clause `EQ` con propiedad desconocida `extra_guard` devuelve TRUE si su `value` coincide; la validación de claves desconocidas existe solo a nivel de selector root | El autor podría creer que el `extra_guard` fue comprobado | Cláusulas deben tener esquema de claves permitido por operador; cualquier clave no registrada → FAIL CLOSED o error validado al publicar. No ignorar requisitos silenciosamente | T23 FAIL. Pruebas adversariales de unknown keys/typing |
| **F05 — selectores ligados a IDs** | Los 14 ACTIVE usan `target.screen.id`; **12 tienen solo esa condición** (los otros dos incorporan módulo/shell) | El matcher es genérico, pero algunos datos de selector obligan a editar la enumeración cuando entra pantalla nueva | Regla **verdaderamente local** puede necesitar screen ID; para reutilización semántica evaluar atributos de capacidad/contexto documentados. **No sustituir IDs sin prueba** de que el alcance debía ser dinámico. El id es dato de selector, no hardcode SQL | G2 diseño de expresabilidad; S04/S05 prueba nueva pantalla y compatibilidad semántica. Sin “forced global” |
| **F06 — autoridad no es scoring** | Matcher comprueba `status=ACTIVE`, schema, consumers y cláusulas; no valida recibo/autoridad en `provenance`. `fn_input_declared_rule_links_v1` filtra además `VIGENTE` | `ACTIVE` declarado en JSON no prueba por sí solo competencia para publicar | Reutilizar dueño/registry/gate de publicación existente: validar origen, versión, consumer, derechos del owner, ámbito aprobado y recibo. N-4 evalúa el selector **ya publicado**, no reemplaza la autorización. No implementar tabla paralela por defecto | Test publishing/admission, NO cubierto por T01–T23 ni por el mero SQL matcher |

**No existen evidencias de incidencia en producción por F01–F04 con los 14 selectores ACTIVE actuales:** sus cláusulas son `IN` sobre IDs, códigos de módulo o shell, ninguna usa `EXISTS` o compara contra null. Los fallos son de **robustez general del lenguaje para futuras reglas** y deben cerrarse antes de expandir su uso. No minimizar la exposición eventual ni alegar explotación.

## 3. Reglas v2.1 adicionales para ratificar (complementan H01–H15)

| ID | Regla | Test exigido |
|---|---|---|
| **H16** | Un dato desconocido, ausente o JSON null nunca concede aplicabilidad, salvo representación explícita de un hecho negativo verificado y autorizado | F01/F02 y versiones futuras; `UNKNOWN≠FALSE` |
| **H17** | Validación cerrada de la gramática de cláusulas: path, operator, value/values, tipos y atributos adicionales; rechazo de propiedades no soportadas | F04: guard desconocido no se omite |
| **H18** | La amplitud de un selector debe justificarse frente al dominio autorizado. Las tautologías u operadores equivalentes requieren decisión explícita, nunca inferencia por la forma de JSON | F03 + norma legítimamente universal con recibo |
| **H19** | El id de pantalla puede existir para una excepción verdaderamente puntual; toda regla propuesta como reutilizable debe demostrar que acepta destinos futuros compatibles sin modificar la lista de IDs | F05: nueva pantalla positiva y negativa |
| **H20** | Una aprobación de alcance es distinta de un JSON con `ACTIVE`; el permiso nace de fuente de autoridad/version/recibo comprobable, no de completar un campo | F06: fixture `ACTIVE` sin provenance no puede publicarse |
| **H21** | El output de un mismo matcher no reemplaza el gate de contexto, lifecycle ni jerarquía. Una norma superior no se debilita por selector local; conflictos sin fuente quedan HOLD | Casos S09/S10, parte de G3 pendiente |

## 4. Precedencia por autoridad: estructura parcial, no jerarquía universal hardcodeada

La frase v2 “normativa > legal/seguridad > gerencia > especificidad” se considera **heurística demasiado amplia**. La regla adecuada es:
- Obtener `authority_ref`, `scope`, `competence`, `effect` y versión de las fuentes para cada política involucrada.
- Si A declara expresamente prohibición/obligación que B intenta violar, **no** usar B como excepción si no posee competencia delegada para ello.
- Si dos ámbitos de autoridad son incomparables o la delegación no consta, **HOLD** y revisión de ambas partes; nunca última escritura/orden de query.
- Reglas compatibles **se acumulan**, incluso de distintos niveles. Exclusiones vigentes solo con fuente, vigencia y autorización explícita.
- Jerarquía de localización (pantalla, módulo, shell) ayuda a encontrar datos, no crea potestad normativa.

## 5. Reglas de gobierno y frontera de responsabilidad

| Componente | Puede | No puede |
|---|---|---|
| T-REMED | Sugerir candidatos, detectar brechas, recomendar reutilización y reparar vínculos bajo procedimiento | Definir universalidad por frecuencia o aprobar scope |
| Curator | Crear ficha, hipótesis A/B, pruebas negativas y fuentes con SHA | Firmar autorización por gerencia |
| Validator | Contrastar independientemente con casos falsadores; auditar cumplimiento del método | Usar la nota del productor como su propia evidencia |
| Owner/gerencia competente | Aprobar/restringir alcance y excepciones en su dominio y recibo verificable | Anular un veto de seguridad/legal fuera de sus competencias |
| N-4 | Evaluar atributos/condiciones de selector **legítimamente publicado** | Investigar semánticamente cada pantalla o emitir recibos de gerencia |
| Consumidor | Consumir conjunto aplicable según contrato/estado | Usar CANDIDATO como política ejecutable ni omitir vetos |

Asegurar que la identidad `consumer_role` interna de N-4 no se confunda con `consumer_id` del contrato externo `INPUT_GOVERNANCE_EXECUTION_CONTRACT`. Validar ambos en sus respectivas fronteras.

## 6. Condiciones de cierre

- **G0–G2:** documentos preparados/revisados técnicamente, pero **pendientes de ratificación** por authority owner del método; no transformarlos en reglas de Supabase.
- **G3:** los 23 casos SQL solo prueban un subconjunto de S01–S14. Se requieren pruebas de colisiones, gerencia, lifecycle, autorización/provenance y falsación independiente en el carril adecuado; actual 18 PASS/5 FAIL. **G3 NO PASS**.
- **G4:** no existe decisión autenticada de adopción del método. **G4 PENDING**.
- **G5:** reclasificación de catálogo **NO AUTORIZADA**; inventario 241 solo baseline.
- El SQL candidato que elimina `DERIVED_GLOBAL` en bloque permanece **NO-GO** y no debe confundirse con la solución v2.1.

**La primera corrección no es cambiar el catálogo: es cerrar F01–F06 sobre contrato, tests y dueño, antes de proponer cualquier migración.**
