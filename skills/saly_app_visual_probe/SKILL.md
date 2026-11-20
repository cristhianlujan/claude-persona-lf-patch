# SALY_APP_VISUAL_PROBE — skill mínimo v0.1

**Estado previsto tras el Merge Train:** `READY / READ_ONLY` para el contexto gobernado **SALY + PRODUCTO + PERFIL-UI-ARCHITECT**, sin habilitación para LF u otros canales. Hasta aplicar y verificar la migración, sigue siendo candidato en el PR.

## Propósito
Prueba de humo del transporte real Router → perfil UI → selección de skill → handler, sin generar imágenes ni modificar elementos de diseño. El objetivo no es certificar una fábrica gráfica ni un perfil completo.

## Activación
Seleccionable de manera **semántica opcional** cuando el usuario solicita comprobar el transporte de SALY al perfil UI y el saludo de prueba. El selector determinístico solo debe ofrecerlo si `execution_id` identifica un RUN activo, oficial y gobernado cuyo handoff fija `business=SALY`, `channel=PRODUCTO`, `profile_code=PERFIL-UI-ARCHITECT` y coincide con el texto transportado.

## Resultado
`mensaje = "Hola mundo, ya llegué."`

`transporte_recibido`: evidencia extraída **de la manifestación persistida del RUN padre**, no datos reconstruidos por el modelo: `execution_id`, `request_sha256`, `negocio`, `canal`, `perfil`, `literal_request`, `scope`, `router_profile_handoff_fingerprint_sha256`, `selected_skill_codes`. Acompaña `handler_version`, `effect_authority=false`, `runtime_invoked=true`.

## Control de seguridad
- El handler comprueba RUN padre `IN_PROGRESS`, operación `EJECUCION_PERFIL_LF`, negocio `SALY`, canal `PRODUCTO`, perfil `PERFIL-UI-ARCHITECT` y selección persistida de **este skill**.
- Un cliente que declare `business=SALY` en un JSON no adquiere selección ni autoridad.
- No lee fondos, logos ni pantallas, no invoca imagen, no abre segundo RUN, no escribe salvo el recibo estándar de invocación que gestiona el invoker.
- El selector sigue evaluando todos los skills elegibles, no fija el skill por defecto.
- Si falla el binding, responde `BLOCKED`; no debe emitir el saludo.
- No se reescribe ni reactiva una ejecución histórica. El owner del RUN sigue siendo UI Architect.
- La salida contiene solo transporte explícitamente seleccionado; no incluye credenciales ni tokens del Router.

**Contrato vigente:** `LF_SKILL_SELECTION_DESCRIPTOR_V1` / invocador `public.lf_profile_skill_invoke_selected_v1` / handler propuesto `public.lf_skill_h_saly_app_visual_probe_v1`.

**Verificación obligatoria:** negativo LF PRODUCTO, negativo SALY PROGRAMACION, negativo sin RUN, positivo SALY PRODUCTO, selección oficial bind al mismo RUN, skill_run_id real, readback del mensaje y recibo. No declarar E2E completo hasta constatar todo.
