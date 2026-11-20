# SALY APP Visual Probe — skill candidato de transporte

- **Código propuesto:** \`SALY_APP_VISUAL_PROBE\`
- **Estado:** \`CANDIDATE_READ_ONLY / NOT_REGISTERED / NO_RUNTIME\`
- **Invocación:** solo prueba de contrato local explícita; NO habilitado en \`lf_skill_catalog_v1\`, \`lf_skill_selection_registry_v1\` ni políticas del perfil.
- **Propósito:** comprobar qué transporte llega al skill cuando el perfil UI lo recibe, sin modificar el Router, generar imágenes, consumir activos reales ni ejecutar efectos.

## Ruta objetivo, NO demostrada E2E

\`ACT-0001 → Stage1 V2 (SALY, PRODUCTO) → business gate → catálogo de perfiles → selección semántica UI → Gate2/handoff → perfil UI → catálogo/política de skills → elección semántica → SALY_APP_VISUAL_PROBE\`

**Bloqueo comprobado:** \`lf_router_business_catalog_v1.SALY\` = \`RECOGNIZED_NOT_ENABLED\`. El Router no debe continuar a perfil/skill aunque Stage1 valide SALY. Un fixture sintético NO equivale a un RUN real.

## Operación de prueba

\`python3 -m unittest discover -s skills/saly_app_visual_probe/tests -v\`

El handler local \`handler.py\` recibe un envelope \`pilot_mode=OFFLINE_CONTRACT_TEST\` con \`transport\` sintético e identificable como tal; devuelve:

- \`mensaje="Hola mundo, ya llegué."\`
- \`transporte_recibido\`: copia redactada de campos del envelope recibido (sin credenciales)
- \`transport_sha256\`: digest del payload original del fixture
- \`simulated=true\`, \`effect_authority=false\`, \`runtime_invoked=false\`

Si falta negocio SALY, perfil UI, elección de skill, existe contaminación LF, o el Router está bloqueado, devolver \`BLOCKED\` sin saludo. No modificar contenido ni inventar recibos de producción.

## Contrato de transporte mínimo del fixture

\`stage1_payload, route_result, semantic_result, gate2_derivation, router_profile_handoff, skill_selection\`, y bandera explícita \`fixture_only\`. En el futuro deberá validarse contra el transporte REAL del mismo request y sus hashes/receipts, no sustituir el handoff con este fixture.

## Pendientes para el siguiente lote (NO ejecutados)

1. Extender habilitación **de solo lectura y por ámbito** de SALY, sin abrir el canal general ni alterar rutas LF (exige aprobación de impacto de Router).
2. Verificar selector semántico sobre **todos los perfiles CURRENT elegibles** por canal; UI debe ganar por descriptor/evidencia, no por nombre literal o hardcode.
3. Registrar descriptor y handler READ_ONLY de este skill bajo selección semántica opcional del perfil UI, con revisión y pruebas oficiales de catálogo.
4. Probar el RUN real Router → UI → skill con recibo y readback; retirar el fixture como evidencia operativa.
