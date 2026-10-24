# ACT-0001 — Politica candidata de canales (lote 1, source-only)

**Estado:** SOURCE_ONLY_CANDIDATE. No altera funciones SQL, reglas vigentes, operadores, capacidades, perfiles, ni permisos. No activa Programacion ni realiza despliegue.

**Contrato machine-readable:** `sandbox/lf_contract_gate_test/router_stage1/channel_policy_candidate_v1.json`.

## Objetivo y autoridad

Stage 1 (GPT/Claude nativo, dentro del flujo logico del Router) interpreta **intencion, activo, efecto solicitado, restricciones y necesidad de cambiar la definicion**. Stage 2 (`public.lf_router_route_v1`) contrasta el candidato con el catalogo registrado y la autoridad vigente. El orquestador activa el ejecutor solo con un recibo/admisión independiente, nunca por una palabra clave o `capability_hint`.

La seleccion de canal **no es seleccion de perfil**, no es permiso de escritura y no es prueba de implementacion.

## Canales y límites

| Canal | Es responsable de | No debe hacer |
|---|---|---|
| PRODUCTO | Definir, verificar y actualizar reglas y definiciones canónicas del producto, incluidas pantallas y elementos | Programar o desplegar |
| PROGRAMACION | Analizar trabajos admitidos, diseñar técnicamente, programar, probar, desplegar y mantener software/plataforma mediante fases y operaciones gobernadas | Inventar el QUÉ, cambiar la definición canónica ni ejecutar consultas cotidianas como si fueran programación |
| OPERACIONES (nombre candidato: Operaciones del Producto) | Consultar estados y usar transacciones ya disponibles en el producto vigente, conforme a identidad, permisos y alcance de datos | Desarrollar nuevas funciones, ejecutar SQL libre, alterar reglas o desplegar |

### Perfiles/Skills no es canal

Los perfiles y skills son **recursos compartidos** que puede utilizar cualquiera de los canales, siempre a traves del Router ACT-0001. La ejecucion `EJECUCION_PERFIL_LF` o `EJECUCION_SKILL_LF` **no cambia el canal responsable**. Ejemplo: Producto puede solicitar UI Architect sin que exista una derivacion al «canal perfiles».

La solicitud **de crear o actualizar el propio perfil o skill** toma la ruta de operacion gobernada `GESTION_ACTIVOS_IA` (familia logica, no es un codigo operativo nuevo) que resuelve `CREACION_PERFIL_LF`, `ACTUALIZACION_PERFIL_LF`, `CREACION_SKILL_LF` o `ACTUALIZACION_SKILL_LF`. No crear un quinto canal ni alterar los contratos de esas operaciones. El Router selecciona y autoriza el recurso; el perfil no llama directamente a otro perfil.

No se debe confundir una **regla transversal** con un quinto canal: una regla puede ser consumida por multiples frentes; primero se identifica la definicion y su responsable.

## Contrato de seleccion que debe consumir el Router

**Distinguir el sistema destino del canal responsable:** `sistema=LF` no equivale a `canal=OPERACIONES`; `sistema` conserva `LF|SALY|OTRO|DESCONOCIDO`. Los nombres de canal son exclusivamente `PRODUCTO`, `PROGRAMACION` y `OPERACIONES`. El cuarto caso es una **ruta transversal de operación gobernada**, no un cuarto canal: gestion del perfil/skill que sea sujeto de la peticion.

La propuesta de Stage 1 debe producir `canal_candidato`, `intencion_tipificada`, `route_kind`, `razon_seleccion` y `precondiciones_no_satisfechas`. Es un **contrato candidato**, no un campo disponible hoy en `LF_ROUTER_STAGE1_V1`. Stage 2 debe validar semantica, activo, existencia de capacidad, version, scope/tenant y permisos antes de iniciar ningun efecto.

| Regla | Entrada material | Ruta inicial | No hacer |
|---|---|---|---|
| R00 Gestion de activos IA | Crear/actualizar la definicion de un perfil o skill | Operacion gobernada exacta del activo, **sin canal** | No confundir ejecutar UI Architect con actualizar sus instrucciones |
| R10 Consulta/accion existente | Consultar oferta/pago/liquidacion o actuar mediante transaccion existente | OPERACIONES | No ejecutar SQL arbitrario ni exponer datos de otros clientes |
| R20 Nueva o distinta definicion | Definir/cambiar regla, conducta, flujo o elemento de pantalla | PRODUCTO | No programar antes de validar la fuente canónica |
| R30 Ciclo tecnico | Analizar implementacion, programar, probar, desplegar, mantener software ya definido | PROGRAMACION | No modificar definiciones funcionales por inferencia |
| R40 Incidencia indeterminada | El usuario reporta fallo en consulta/transaccion, sin causa probada | OPERACIONES (diagnostico de lectura) | No concluir bug y programar sin evidencia |
| R50 Solicitud mixta | «Define la regla y prográmala» | PRODUCTO primero; dependencia ordenada a PROGRAMACION | No despachar los dos en paralelo |
| R60 Ambiguedad material | «Arregla lo de ofertas» sin objeto preciso | Aclarar tras inspeccion acotada | No despachar al azar |

**Orden logico:** primero discriminar si el usuario solicita gestionar el propio recurso IA; después si pide informarse/operar algo existente; después si pretende definir/cambiar reglas y requisitos; después si solicita el ciclo tecnico sobre definicion lista; ante incidencia incierta, diagnostico de solo lectura. La solicitud mixta antepone la dependencia PRODUCTO a PROGRAMACION. Este procedimiento no se basa en porcentajes fijos o keywords aisladas. Empates materiales requieren evidencia discriminante y, si persisten, una pregunta.

**Comprobacion del Stage 2:** la ruta propuesta no sustituye los contratos del `lf_router_action_registry`, `CAPABILITY_SELECTOR` ni la admision gobernada. Operaciones necesita una capacidad **realmente liberada y autorizada**, no la mera existencia de tabla. Programacion necesita definicion vigente y, cuando corresponde implementar, paquete A9 y admision PG-01; despliegues e infraestructura siguen en Programacion y sujetos a sus operaciones y controles actuales. Las operaciones de gestion de perfiles y skills continuan utilizando sus codigos canónicos y ACT-0001.

### Casos limite que deben probarse

- «¿Que oferta vigente tengo?» -> OPERACIONES, solo con identidad/alcance verificado y handler existente.
- «¿Cual es la regla de vigencia?» -> PRODUCTO (consulta de definicion), aunque pueda consultarse sin modificar.
- «Cambia la vigencia de ofertas» -> PRODUCTO y actualizacion de definicion; implementacion eventual despues.
- «Corrige el codigo que calcula la vigencia ya aprobada» -> PROGRAMACION con admision tecnica.
- «Una oferta no aparece» -> OPERACIONES para diagnostico; escalamiento a PROGRAMACION solo ante defecto confirmado.
- «Despliega la nueva version» -> PROGRAMACION bajo operacion/autoridad de despliegue, nunca bypass.
- «Usa UI Architect para revisar la pantalla» -> canal del trabajo PRODUCTO y recurso PERFIL-UI-ARCHITECT.
- «Actualiza el propio perfil UI Architect» -> `ACTUALIZACION_PERFIL_LF` por ruta de gestion de activos, sin canal Perfiles/Skills.

**Activacion pendiente:** la documentación y el JSON del PR especifican el comportamiento, pero la funcion SQL `lf_router_route_v1` todavia no consume `canal_candidato`; requiere integracion y pruebas propias posteriores por Merge Train. No declarar la politica desplegada desde este PR.

## Contexto de producto y alcance (separado del canal)

**Tres dimensiones independientes:** `canal_candidato` indica qué trabajo; `producto_codigo` indica en qué producto (`LF`, `SALY` u otro registrado); `alcance` indica dónde aplica (producto, grupo corporativo, empresa, registro, conjunto explícito de productos). No crear combinaciones fijas como `OPERACIONES_LF` o `PROGRAMACION_SALY`.

**Compatibilidad:** en `LF_ROUTER_STAGE1_V1` ya existe `sistema` con valores `LF|SALY|OTRO|DESCONOCIDO`; representa **producto destino** y nunca el canal. Se propone `producto_codigo` como nombre canónico en el contrato futuro y un normalizador explícito que proyecte la versión anterior sin romper consumidores existentes. **La función SQL actual sigue aceptando exclusivamente LF para continuar**; reconocer SALY no implica poder despachar a sus operaciones.

**Ámbito organizacional:** `lf_ops.b2b_corporate_groups` (`group_id`) -> `lf_ops.b2b_corporate_group_companies` -> `lf_ops.empresas` (`company_id`) es la jerarquia existente verificada de LF. Una empresa cliente/tenant no es sinónimo de producto LF ni de la organización dueña del producto. El usuario puede indicar el nombre de una empresa, pero el identificador real, la pertenencia al grupo y permisos deben venir de la sesión/resolvedores autorizados del servidor. La unidad operativa u otras jerarquías futuras no se inventan hasta registrarlas.

**Selección:** señales explícitas del producto, producto activo en sesión confiable y binding canónico del activo permiten proponer `producto_codigo`. La conversación previa es solo indicio; no autoriza seleccionar ni entrar a una empresa distinta. Si es materialmente ambiguo, una pregunta. Para trabajos verdaderamente transversales a más de un producto se utiliza lista explícita `productos_afectados` y se verifica cada autoridad; nunca `ALL` implícito.

| Solicitud | Canal | Producto | Alcance |
|---|---|---|---|
| «Estado de mi oferta en LF» | OPERACIONES | LF | Registro autorizado |
| «Estado de mi adelanto en SALY» | OPERACIONES | SALY | Registro autorizado; ruta SALY aún no habilitada por Router LF |
| «Pagos de mi empresa en LF» | OPERACIONES | LF | Empresa verificada de sesión |
| «Consolidado de un grupo corporativo en LF» | OPERACIONES | LF | Grupo y empresas con acceso verificado |
| «Definir expiración de sesión para LF y SALY» | PRODUCTO | LF + SALY explícitos | Multiproducto, decisiones/aprobaciones separadas |
| «Estado de mi solicitud», sin otro contexto | Candidato OPERACIONES | No resuelto | Solicitar desambiguación antes de despachar |

**No confundir dimensiones:** `canal` no es identidad de producto, `producto` no es empresa, el `alcance` no es un permiso. El Router clasifica el pedido y Stage 2 valida producto exacto, capacidad de ese producto y scope autorizado, todo previo a datos/efectos.

## Precedencia y dependencias (no ejecuta acciones)

1. Determinar si el pedido **modifica una definicion del producto**; si es asi, el primer canal es PRODUCTO.
2. Buscar la fuente canónica exacta y su estado. Si no existe o difiere, preparar su modificacion gobernada. Si ya coincide, **no duplicar la escritura**. `CANDIDATO` no equivale a version autorizada para la etapa posterior.
3. Cuando el objetivo es implementar una definicion **sin modificar el QUÉ**, Stage 1 puede proponer PROGRAMACION, **pero no ejecutar**.
4. Para entregar a Programacion, reutilizar `PROGRAMMING_ENTRY_CONTRACT_V1`: paquete `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`, snapshot `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, evidencia de currentness, scope `READY` (o subconjunto aislado READY de PARTIAL_READY), recibo persistido y admision PG-01. Sin todo ello: no programar.
5. Si falta definicion funcional, devolver a PRODUCTO. Si falta analisis/evidencia, devolver a ANALISIS. Si falta permiso de runtime u operacion, bloquear. Un perfil no deriva por si mismo a otro perfil: devuelve al Router.
6. En solicitudes mixtas, planificar pasos secuenciales y dependencias; no despachar a todos los canales. Empates materiales: evidencia discriminante acotada y, si persisten, decision humana.
7. Los permisos y versiones se leen de autoridad vigente: `public.lf_router_action_registry`, `public.lf_router_capability_v1`, `public.lf_capability_registry` y la capacidad transversal `CAPABILITY_SELECTOR` (solo propuesta, no permiso). **No copiar** a esta politica la lista viva de operaciones ni sus estados.

## Frontera: desarrollo y operacion cotidiana

**Nombre candidato del tercer canal:** `OPERACIONES` / «Operaciones del Producto». No se crea `SISTEMA` como canal. «Soporte» es un subtipo posible de Operaciones, pero no su unico objetivo.

**PROGRAMACION**, una vez admitido el alcance aplicable, cubre el ciclo tecnico completo: Analisis, diseño técnico, implementacion, pruebas, despliegue y mantenimiento tecnico. Los controles de cada fase y de cualquier efecto permanecen independientes y vigentes; esta politica no concede permisos de despliegue. Una incidencia por codigo defectuoso corresponde a Programacion; consultar un registro comercial o usar una transaccion ya expuesta no equivale a programar.

**OPERACIONES** atiende actividades cotidianas sobre un producto ya implementado: consultar una oferta, estado de un pago, resultado de una liquidacion, o invocar una accion de negocio existente. No requiere un paquete A9/PG-01 para una **lectura** autorizada; requiere que exista un handler o servicio vigente, identidad/empresa/tenant y permisos exactos, minimizacion de datos y evidencia del resultado. La existencia de una fila SQL no autoriza su lectura por un cliente. No otorgar SQL libre al modelo.

**Dependencia nueva**: si Operaciones encuentra una capacidad inexistente, debe informar brecha al Router. Una nueva regla funcional regresa a PRODUCTO, mientras que implementar un servicio sobre una definicion ya vigente entra al analisis/admisión de PROGRAMACION. No convertir una consulta normal en un desarrollo por defecto.

**Ejemplo** «¿Cual es el estado de mi oferta?» -> OPERACIONES -> servicio de consulta autorizado (si existe) -> respuesta. Las tablas `public.lf_user_offer_access` y `public.lf_user_offer_selections` se observaron en la base, pero `public.lf_router_capability_v1` no acredita una capacidad de estado de oferta: **no declarar operacion habilitada**.

**Ejemplo** «Corregir un fallo en el servicio de ofertas y desplegar la correccion» -> PROGRAMACION, con entrada, pruebas y despliegue gobernados. «Definir las condiciones comerciales de la oferta» -> PRODUCTO.

**No se altera el registro de operaciones** `public.lf_router_action_registry`: los nombres de canal clasifican solicitudes, no sustituyen `operation_code` ni cambian el permiso efectivo.

## Caso de regresion — Login B2B

Solicitud: «Cambiar unicamente el texto del boton principal de Iniciar sesion B2B a Acceder, sin modificar autenticacion ni validaciones».

- Interpretacion: cambio de definicion visual especifica, no cambio automatico de perfil.
- Primera accion: PRODUCTO verifica `B2B-AUTH-001` / `B2B_AUTH001_SUBMIT` contra `lf_ops.pantalla_elementos.label_visible`.
- Readback observado 23-oct-2026: `Acceder`, pantalla version `v0.5` con estado `CANDIDATO`. **No se vuelve a actualizar la misma celda**; se comprueba autoridad de la definicion e implementacion, sin suponer que el frontend ya muestra ese valor.
- Si ya existe implementacion coincidente y autoridad suficiente, cierre con evidencia. Si existe una discrepancia de implementacion, iniciar Análisis / admision antes de Programacion.
- No se cambia `lf_ops.reglas` por costumbre: cada tipo de definicion tiene su propio almacén canónico.

## Estado y siguientes lotes

**Este lote** congela solo politica candidata + pruebas estructurales. No modifica `LF_ROUTER_STAGE1_V1` ni su validador productivo.

**Lote 2:** ampliar formalmente Stage 1, definir entrada/salida tipadas, adaptar el validador Python y SQL conservando compatibilidad; no interpretar confidence como permiso.

**Lote 3:** integrar `lf_router_route_v1` con selección de canal + autoridad exacta; validar el `capability_hint` contra la intención, cubrir empates y bloqueos; pruebas con rollback; PR/PASE/Train.

**Lote 4:** integrar recibos, retorno del especialista y habilitación gradual por canal después de sus propios gates.

**No cerrado todavía:** validacion final del nombre OPERACIONES, operaciones de negocio expuestas por un handler autorizado y su enlace gobernado; mapeo completo de las 28 operaciones existentes a responsable/consumidor; criterios de scoring y empates; validación de permisos y status por operación; invocador del Stage 1. Estos faltantes no autorizan a suponer disponibilidad.
