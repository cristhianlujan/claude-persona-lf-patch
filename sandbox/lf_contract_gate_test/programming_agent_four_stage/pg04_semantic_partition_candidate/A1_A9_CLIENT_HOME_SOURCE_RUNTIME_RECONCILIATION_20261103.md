# A1–A9 — Solicitud focalizada CLIENT_APP_SHELL / CLIENT_HOME (2026-11-03)

**Estado:** `SOURCE_IDENTIFIED / POTENTIAL_ROUTE_CONTRADICTION / NO_AUTHORITY_TO_CHANGE_PRODUCT / ANALYSIS_NOT_EXECUTED`

## Hallazgo de fuente, no fallo certificado

La petición anterior sobre `B2B_APP_SHELL` se detuvo en A3: shell `CANDIDATO`, 0/9 scopes READY en snapshot v1.0, no currentness operativo ni A6 tipado completo. Se investigó una alternativa definida como `VIGENTE`: `CLIENT_APP_SHELL` v1.1 y módulo `CLIENT_HOME`, también `VIGENTE`. La **pantalla** vinculada sigue `CANDIDATO`, lo cual impide inferir vigencia de la experiencia entera.

Readback de Supabase **solo lectura**:
- `lf_ops.app_shells`: `CLIENT_APP_SHELL` v1.1, `status=VIGENTE`, `source_decision_id=DEC-CLIENT-AUTH-NAV-IA-001`, #117, navegación de sesión autenticada.
- `lf_ops.modulos`: `CLIENT_HOME` `VIGENTE`, activo, fuente `DEC-CLIENT-AUTH-SESSION-RUNTIME-001`, #105.
- `lf_ops.pantallas`: `HOME_001` (id 4, «Home anónimo»), `HOME_002` (id 5, «Home con oferta»), `HOME_003` (id 6, «Home sin oferta») tienen `estado=CANDIDATO`, `activa=true`. El estado `activa` no convierte el modelo de pantalla en `VIGENTE`.
- `lf_ops.rutas`: `CLIENT_HOME_ENTRY` resuelve patrón `/`, `authentication_required=false`, `status=VIGENTE`, fuente `DEC-CLIENT-AUTH-SESSION-RUNTIME-001` #105; vinculada a `HOME_001` cuyo estado es `CANDIDATO`.
- `private.lf_decision_context_asof_v1`: no hay contexto A9 para `CLIENT_APP_SHELL`.

Readback GitHub **app real** `cristhianlujan/libertad-financiera` rama `main`:
- `package.json` Git blob `1b22a4b21c5966e4ff1fdb1c3c0b1dbfecbeff2f`: Next.js 16, React 19; tests `test:auth-runtime` y `test:b2b-shell`.
- `src/app/page.tsx` Git blob `d666bb7ee8252aad7cde3beafa7c826d1491be8c`: la página raíz llama `getClientSessionContext`, lanza `AUTHENTICATED_CLIENT_ACCOUNT_REQUIRED` cuando no es cuenta cliente autenticada; RPC `fn_lf_my_active_offers`; render `MultiOfferHome`.
- `src/lib/auth/client-session.ts` Git blob `6355987289a826b1e2a432bae620511321bb7926`: sin usuario Supabase Auth devuelve contexto anónimo (no error inmediato); consulta RPC `fn_lf_client_session_context` para usuarios autenticados.
- `src/app/multi-offer-home.tsx` Git blob `55ada6a4c2a2d0ac5304c830a27e5f104aa23147`: UI real de ofertas, resumen y selección; no equivale por sí misma a autorización de pantalla `HOME_001`.
- `tests/auth-runtime.contract.test.mjs` Git blob `e1803b4e7c13685ab80480fb88c8fd6857561b62`: exige que la raíz consulte la sesión y mantenga la identidad privada.

**Posible contradicción a resolver:** ruta canónica `/` `authentication_required=false` para «Home anónimo», pero la página raíz de Next.js exige cuenta autenticada y muestra ofertas. **No concluir que la ruta de BD realmente gobierna `src/app/page.tsx` ni que el despliegue apunta a ese commit sin probar bindings y runtime.** No modificar rutas, autenticación ni pruebas hasta autorización de Producto.

## Petición exacta al Agente de Análisis (sin editar código)

> Ejecuta A1–A9 para determinar la correspondencia funcional autorizada y vigente entre `CLIENT_APP_SHELL` v1.1, `CLIENT_HOME`, `HOME_001/HOME_002/HOME_003`, la ruta `CLIENT_HOME_ENTRY` y el AS-IS del repositorio `cristhianlujan/libertad-financiera`. Resuelve el vínculo *source-to-runtime* y si la divergencia de autenticación y tipo de Home es real o aparente (rewrite, host distinto, Router, middleware, despliegue, versión o decisión posterior). Mantén separadas definición PRODUCTO, implementación PROGRAMACIÓN y permisos de sesión.
>
> Si la definición canónica actual ordena una landing anónima en `/`, determina su resultado observable, condición de sesión, transición a Login y sus obligaciones de seguridad; nunca abras acceso a ofertas privadas. Si la definición vigente exige Home autenticado, documenta la discrepancia con `CLIENT_HOME_ENTRY`, su autoridad y solicita decisión de Producto antes de alterar la ruta. No elijas una de las opciones sin evidencia.
>
> Para un scope que se acredite READY, entrega `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` y snapshot `PROGRAMMING_CONTEXT_SNAPSHOT_V1` completos, con `IMPLEMENTABILITY_SCHEMA_V1`, `MATERIAL_FRONT_COVERAGE_V1`, estados `AUTHORITY_STATE`/`IMPLEMENTATION_STATE` separados, AS-IS+DELTA si existente, requisitos y señales de aceptación tipadas, matrices frentes/scopes, currentness, dependencias y recibos reales. Si algo es desconocido, `NEED_MORE_EVIDENCE` o `REQUIRES_DECISION`, preservando el blocker exacto y sin marcar READY por conveniencia. No escribas producto, no implementes código y no ejecutes PG-01 sin habilitación gobernada.

## Criterios de ensayo y fronteras

1. A3 deberá confirmar `VIGENTE` para el activo exacto, incluida pantalla/ruta y referencia temporal. La vigencia del shell **no** prueba la de la pantalla.
2. Comprobar el binding del `/` canónico con el servidor realmente operativo y HEAD ejecutado. Un match de texto no equivale a prueba de ruta desplegada.
3. Resolver reglas de autenticación y privacidad **sin** cambiar comportamiento productivo.
4. A4 deberá usar `SHARED_CHANGE_IMPACT_ANALYSIS` existente para consumidores/cambios indirectos, no motor paralelo.
5. A6/A7/A8 deberán producir obligaciones/frentes/STOP explícitos; el bloqueante de Producto no se convierte en Programación READY.
6. A9 requiere juez independiente, contexto persistido CURRENT y recibos reales antes de PG01_C6. El perfil `programming_analysis_lf` continúa documentado como `CANDIDATE_NOT_RELEASED` y no tiene Router binding demostrado.
7. Mantener este caso en un PR draft de análisis/diagnóstico, no como cambio automático de auth. Reutilizar validators existentes.

**Resultado:** candidato de solicitud **más concreto que el caso B2B**, pero aún **sin autorización para liberar una partición PG04 operativa**.

## Evidencia de pruebas que faltan

- Resolver decisión #105/#117 y regla vigente de sesión para las pantallas (no solo filas de shell).
- Verificar despliegue real / si `CLIENT_HOME_ENTRY` se proyecta al Next.js root.
- Confirmar que el nuevo análisis se ejecute por Router con fuentes/receipts.
- En caso de aprobación, ejecutar A1–A9 y PG01 de verdad, dejando el primer blocker real o un scope READY autenticado.

Sin merge, sin cambios en `libertad-financiera`, sin escrituras a Supabase.
