# P02 — Pruebas reales de contexto por regla (28-10-2026)

Estado: EVIDENCIA PARCIAL; no ejecución de cambios. EKB consultado: IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.

## Hechos verificados en Supabase

1. N-4 produce un objeto base con `target.screen`, `target.module` y `target.app_shell`, además de `consumer_role`. No exige una lista de capacidades funcionales a cada pantalla.
2. Los 14 selectores ACTIVE consultados utilizan 17 cláusulas: `target.screen.id` (14), `target.module.module_code` (2) y `target.app_shell.app_shell_code` (1). Ninguna condición ACTIVE observada requiere un atributo dinámico de sesión.
3. Hay **16 pantallas sin módulo asociado**, no necesariamente defectuosas: en ellas `target.module` y `target.app_shell` contienen JSON null. Se deben evaluar reglas con información disponible; no imponerles módulos como prerrequisito general.
4. Prueba de matcher: `B2B-RULE-DESIGN-001` devuelve TRUE para `B2B-AUTH-001` y `B2B-AUTH-002`, FALSE para `HOME_FAQ` y `ONB_004`. `B2B-RULE-STORY-READINESS-001` devuelve TRUE solamente para `B2B-AUTH-001` dentro de esos cuatro casos.
5. La cláusula `EXISTS` sobre `target.screen.objective` de Login devuelve TRUE; sobre una capacidad inventada devuelve FALSE; operador `NE` no soportado devuelve FALSE; `EQ module_code` para pantalla sin módulo devuelve FALSE. Es comportamiento de seguridad fail-closed para MATCH, pero **el booleano FALSE no distingue NO_MATCH de UNKNOWN**. Si una evolución requiere esa distinción, debe justificarla con un fallo observado y preservar compatibilidad.
6. Ya existe `programacion.fn_input_security_capability_profile`, que lee `fn_input_effective_rule_links_v1` y compara códigos específicos de reglas. No debe convertirse en fuente universal de capacidades sin auditoría: comparte las herencias con problemas de autoridad. Su invocación directa fue rechazada con `permission denied for function`; **NO hay prueba de ejecución de sus resultados**.

## Contrato propuesto, no implementado

- Cada selector define su lista concreta de datos necesarios; el contexto inicial es únicamente el existente.
- Primero buscar campos ya presentes en fuentes autoritativas; no agregar columnas universales por conveniencia.
- Consultar fuentes adicionales solo para reglas elegibles que requieran esa capacidad.
- Resultado de investigación de atributo: VERIFIED_TRUE, VERIFIED_FALSE o UNKNOWN (etiquetas de revisión, no nuevos enums persistentes autorizados).
- UNKNOWN deja la regla pendiente; no convierte un NOT sobre NULL en una condición satisfecha; las reglas independientes se siguen evaluando.
- Separar el proceso semántico de autoría del matcher determinista en consumo; ninguna llamada LLM en cada renderizado.
- Medir costo y latencia antes de extender contexto dinámico.

## Pruebas de regresión requeridas para cierre

| Caso | Resultado esperado |
|---|---|
| Regla con condición de screen.id y screen conocido | Evalúa según selector ACTIVE |
| Regla de módulo en pantalla sin módulo | No se aplica; no bloquea otras reglas |
| Regla con capacidad funcional no presente | No se aplica; marca necesidad de evidencia |
| Regla sin dependencia de sesión | No consulta política de sesión |
| Regla con código semánticamente parecido a otra | No hereda por similitud lexical |
| Regla cuyo selector está UNRESOLVED | Fail-closed |
| Fuente especial con función no ejecutable por permisos | No se inventa respuesta; se retiene el bloqueo local |

**Cierre:** P02 parcial: condiciones de los 14 selectores ACTIVE examinadas; fuentes de capacidades adicionales, autorización y pruebas de integración todavía pendientes. No se modificó N-4 ni Supabase.
