# SALY — piloto Router → UI → Skill Hola mundo v0.1

**Estado:** DRAFT / CANDIDATO AISLADO / SIN EJECUCIÓN E2E REAL.
**Fase:** únicamente trazado de clasificación, transporte y skill Hello world. No imágenes ni modificación de APP/MOCKUP.

## Flujo y responsables

| Paso | Componente real | Evidencia observada | Próxima prueba |
|---|---|---|---|
| 1. Interpretar negocio | Modelo nativo produce \`LF_ROUTER_STAGE1_V2\`; campo \`negocio_codigo=SALY\` con razón basada en solicitud | Fixture SALY validado por función \`public.lf_router_stage1_validate_v2\`: \`valid=true\`, \`codes=[]\` | Evaluar corpus de frases SALY/Sali/Sally y negativos con modelo nativo; no imponer SALY si el pedido no lo justifica |
| 2. Validar ámbito | \`public.lf_router_business_catalog_v1\` | \`SALY=RECOGNIZED_NOT_ENABLED\`, \`LF=ENABLED\`. Código \`lf_router_route_v1\` devuelve \`NEGOCIO_NO_HABILITADO\` cuando negocio no está ENABLED. | Preparar habilitación gobernada **solo** para piloto controlado (cambio posterior; no aplicado) |
| 3. Descubrir perfiles | \`lf_profile_selector_catalog_v1\` + policy \`lf_profile_selector_semantic_prepare_v2\` | \`PERFIL-UI-ARCHITECT\` \`CURRENT\` y \`DIRECT\`, canal PRODUCTO, candidato elegible; lectura directa al prepare requiere permiso adicional (DENIED para rol read-only) | Ejecutar selección real autorizada, entre todos los candidatos elegibles y sin hardcodear UI en Router |
| 4. Selección semántica | Decisión nativa \`SELECTED/AMBIGUOUS/NO_MATCH\` → validador/consumer | Contrato inspeccionado en fuente; **no** se ha ejecutado para SALY | Debe seleccionar UI con fuente y justificación, nunca por el nombre "UI" pedido solamente |
| 5. Gate2 y handoff | \`lf_router_pipeline_context_profile_semantic_submit_v2\` → \`lf_router_pipeline_context_profile_admit_v2\` → \`HANDOFF_CONTEXT_TO_SELECTED_PROFILE\` | Funciones leídas, transporte con \`stage1_payload\`, \`route_result\`, \`transition\`, \`semantic_result\`, \`semantic_validation\`, \`after_selection_result\`, \`gate2_derivation\`; admisión emite \`router_profile_handoff\`. | Verificar el paquete exacto del mismo request/ejecución/versión, no reconstruir en el perfil |
| 6. Skills del UI | \`lf_skill_catalog_v1\` + \`lf_skill_selection_registry_v1\` + \`lf_skill_selector_policy_v1\` | UI tiene 2 skills opcionales habilitadas: \`INPUT_GOVERNANCE_CONTEXT_PACK\`, \`SCREEN_RULES_SNAPSHOT\`. Nueva skill **no existe aún en esos catálogos**. | Registrar descriptor y handler con efecto READ_ONLY y política semántica opcional, solo mediante migración y aprobación del cambio |
| 7. Skill Hola mundo | \`skills/saly_app_visual_probe/handler.py\` | Prueba **local sintética** únicamente, sin RUN Router real, salida \`Hola mundo, ya llegué.\` + transporte redactado | Prueba nativa tras activar catálogo y resolver ruta SALY con scope autorizado |

## Regla para no simular éxito

Hoy un pedido SALY llega **hasta el gate de negocio** en el Router. Un \`HELLO_WORLD_OFFLINE\` muestra el formato y el contrato del handler, pero **no** demuestra \`Router→UI→skill\` operativo. No se usa el fixture como receipt productivo ni se modifica la base para llegar a PASS.

## Contrato candidato de payload

Se espera la transferencia por referencias a un único RUN: \`stage1_payload\`, \`route_result\`, \`semantic_result\`, \`gate2_derivation\`, \`router_profile_handoff\`, \`skill_selection\`, y posteriores receipts. Salida final con:

\`\`\`json
{"status":"HELLO_WORLD_OFFLINE","mensaje":"Hola mundo, ya llegué.","simulated":true,"runtime_invoked":false,"effect_authority":false,"transporte_recibido":{},"transport_sha256":"<digest>"}
\`\`\`

No echo de credenciales; no afirmar que la skill fue seleccionada por UI si la decisión es fixture.

## Criterios para declarar E2E real

1. Negocio SALY resuelto por Stage1 y permitido por scope; negativo LF/OTRO se bloquea si corresponde.
2. Perfiles son filtrados determinísticamente desde inventario vigente; una decisión semántica válida selecciona UI sin preselección oculta.
3. Misma solicitud con hash y business=Saly preservados en Gate2/admisión/handoff/RUN.
4. UI recibe y confirma la totalidad del transporte gobernado antes de preparar skills.
5. Skill de prueba existe en catálogo con descriptor CURRENT, policy habilitada exclusivamente en el ámbito adecuado, handler read-only verificado.
6. Selección skill es gobernada por perfil y validada por servidor; no ejecuta un skill sin recepción genuina.
7. Salida hello world con RUN/skill_run_id reales; readback independiente y ausencia de cualquier mutación fuera del ledger autorizado.
8. Reversibilidad de habilitación, regressions LF/Overall y ningún bypass de autorización.

**NO-GO:** ninguno de los puntos 2–7 se acredita por el fixture aislado. La fase de habilitación del negocio/profiling requiere un PR de impacto posterior, separado de este candidato.
