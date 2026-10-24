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

**Distinguir Negocio del Canal:** `negocio_codigo=LF` identifica el negocio y no equivale a `canal_candidato=OPERACIONES`. Los nombres de canal son exclusivamente `PRODUCTO`, `PROGRAMACION` y `OPERACIONES`. El cuarto caso es una **ruta transversal de operación gobernada**, no un cuarto canal: gestion del perfil/skill que sea sujeto de la peticion.

La propuesta de Stage 1 V2 debe producir `canal_candidato`, `negocio_codigo`, `alcance` cuando corresponda, `intencion_tipificada`, `route_kind`, `razon_seleccion` y `precondiciones_no_satisfechas`. Son campos de **interpretacion**, no de autoridad. Stage 2 debe validar semantica, activo, existencia de capacidad, version, scope/tenant y permisos antes de iniciar ningun efecto.

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

## Canal, Negocio y Alcance dinámico

**Dimensiones acordadas:**

- **Canal** (solo tres): `PRODUCTO`, `PROGRAMACION`, `OPERACIONES`. El canal Producto mantiene su nombre y responde a DEFINICIONES del negocio, no identifica a cuál negocio corresponde el pedido.
- **Negocio**: `negocio_codigo` es el campo canónico que responde «¿de qué negocio hablamos?». En esta fase operativa el único negocio aceptado para cierre es `LF`; SALY queda para una fase posterior. Un negocio no equivale a una empresa cliente de dicho negocio.
- **Alcance**: **opcional, determinado a demanda** por el objeto mencionado en la solicitud y los datos canónicos específicos del negocio. NO es una lista fija de tipos ni se resuelve enteramente en Stage 1.

**Compatibilidad:** `LF_ROUTER_STAGE1_V2` **no expone ni acepta** el campo legado `sistema`. El endpoint desplegado `LF_ROUTER_STAGE1_V1` todavía lo requiere internamente; mientras exista esa frontera V1, el adaptador deriva ese valor desde `negocio_codigo` únicamente dentro del payload de compatibilidad. El modelo y los consumidores V2 no deben producir, leer ni decidir usando `sistema`.

### ¿Cómo se determina el alcance sin construir un catálogo gigante?

1. **Extraer el objeto mencionado**: «login B2B» sugiere una pantalla; «oferta» sugiere un registro comercial; «empresa ABC» sugiere ámbito de empresa. Son **pistas**, no referencias canónicas ni permisos.
2. **Determinar si la operación realmente necesita alcance**. Una definición general o consulta conceptual puede tener `alcance=null` / `NOT_REQUIRED`; un cambio de pantalla o consulta de información privada sí necesita objeto concreto.
3. **Reutilizar el resolvedor/catálogo de activos del negocio** y metadatos de la operación. Buscar la pantalla en definiciones de LF, la oferta en el servicio aprobado de LF o la empresa en el contexto de sesión. No consultar tablas arbitrarias ni inventar IDs.
4. **Validar el binding** (`target_type`, `target_hint`, `target_ref`, `resolution_status`) y los permisos **solo cuando el trabajo lo requiera**. El acceso a datos de empresa se valida mediante el actor/tenant del servidor y las autorizaciones reales.
5. Si hay varios objetos posibles, solicitar **una aclaración material**. Si falta un resolvedor/capacidad para ese negocio, devolver una brecha, no fabricar una ruta o activar Programación automáticamente.

El vocabulario de objetos puede crecer al registrar capacidades o nuevos activos de cada negocio (pantalla, regla, cliente, oferta, solicitud, liquidación, lote, integración, etc.). El Router conserva el contrato genérico y consulta las definiciones canónicas. No debe añadirse cada nuevo tipo a un `ENUM` central ni crear una tabla auxiliar para una mera clasificación.

**Fuente ya verificada en LF, pero solo para esa parte del negocio:** `lf_ops.b2b_corporate_groups` (`group_id`) + `lf_ops.b2b_corporate_group_companies` + `lf_ops.empresas` (`company_id`). No representan por sí mismas todos los alcances posibles ni autorizan consultar datos del cliente. No se traslada esa jerarquía automáticamente a SALY u otros negocios.

| Solicitud | Canal | Negocio | Alcance necesario |
|---|---|---|---|
| «Cambia el texto del Login B2B de LF» | PRODUCTO | LF | Pantalla canónica concreta |
| «Estado de mi oferta en LF» | OPERACIONES | LF | Oferta/cliente autorizados si existe handler |
| «Consulta mis adelantos de SALY» | OPERACIONES | SALY | Solicitud/empleado autorizado; no habilitado aún por Router LF |
| «Pagos de mi empresa en LF» | OPERACIONES | LF | Empresa vinculada en sesión |
| «Explica qué hace el canal Programación» | Respuesta directa | No requerido | No requerido |
| «Revisa una regla que aplique a LF y SALY» | PRODUCTO | LF y SALY explícitos | Regla, con autoridad por cada negocio |

En trabajos verdaderamente transversales se usa `negocios_afectados` explícito, nunca `ALL` implícito. La petición en texto no confiere permiso de acceso a grupo, empresa o cliente. El alcance no sustituye autorización.

**Implementación V2:** `negocio_codigo` es canónico y `alcance` es opcional/dinámico. Las referencias exactas y derechos se resuelven en Stage 2 o en el handler autorizado de LF. El contrato y ejemplos de este PR son **SOURCE_ONLY_CANDIDATE**, no una capacidad operativa conectada.

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

## Entrega técnica para pasar al segundo nivel (sin promover SQL)

Se preparó **LF_ROUTER_STAGE1_V2** como adaptación opt-in compatible, sin tocar la función `public.lf_router_stage1_validate_v1` ni el comportamiento `public.lf_router_route_v1` desplegados:

**Fase actual LF:** el contrato usa `negocio_codigo` y el cierre de este PR se valida únicamente para `LF`. El validador conserva una extensión opcional `registered_businesses` para evolución futura, pero SALY y otros negocios no forman parte de la aceptación actual y no deben bloquear el cierre de LF. El catálogo nunca se toma del texto no confiable del usuario.

- `sandbox/lf_contract_gate_test/router_stage1/stage1_context_validator_v2.py`: validador estructural de la clasificación generada por GPT/Claude nativo. Admite exactamente `PRODUCTO|PROGRAMACION|OPERACIONES`; `negocio_codigo` es el campo canónico de negocio y el validador rechaza el campo legado `sistema`; `alcance` es objeto **opcional**, sin enumeración central fija y sin identificadores canónicos certificados desde el modelo. Gestión del perfil/skill mismo usa `ruta_transversal=GESTION_ACTIVOS_IA` con `canal_candidato=null`.
- `sandbox/lf_contract_gate_test/router_stage1/test_stage1_context_validator_v2.py`: casos estructurales positivos y negativos, incluyendo SALY conocido/no habilitado, multinegocio, ambigüedad, referencia inventada, operación no autorizada, pantalla y scope opcional.
- `sandbox/lf_contract_gate_test/router_stage1/stage2_handoff_v2.py`: mantiene una frontera temporal de compatibilidad con `public.lf_router_route_v1` **solamente para LF**. Si el endpoint V1 necesita el nombre legado, se sintetiza dentro de `legacy_stage1_v1_payload`; ese detalle no pertenece al contrato V2. Descarta `capability_hint` de origen modelo para evitar despacho directo sin autoridad semántica. La referencia de alcance sigue `UNRESOLVED`; el contrato no concede acceso ni invoca SQL.
- `sandbox/lf_contract_gate_test/router_stage1/test_stage2_handoff_v2.py`: comprueba el payload de handoff, la contención de SALY y multinegocio, el bypass del hint no certificado, los límites de permisos y la respuesta directa sin scope.

El modelo debe emitir V2 solo cuando el invocador adopte este contrato. La salida nueva conserva campos obligatorios V1 y añade estos campos de **interpretación**, no autorización:

```json
{
  "schema_version": "LF_ROUTER_STAGE1_V2",
  "canal_candidato": "OPERACIONES",
  "negocio_codigo": "LF",
  "negocios_afectados": [],
  "ruta_transversal": null,
  "razon_seleccion": "Consulta de una capacidad existente",
  "alcance": {
    "target_type": "OFERTA",
    "target_hint": "mi oferta",
    "resolution_status": "UNRESOLVED"
  },
  "downstream_execution_allowed": false
}
```

Los campos comunes (`texto_original`, `es_operacion`, `respuesta_directa`, `accion`, `sujeto`, `correcciones`, `formas_busqueda`, `ambiguo`, `alternativas`, `pregunta_usuario`, `capability_hint`) se siguen exigiendo según corresponda. `sistema` está prohibido en V2. `target_ref` y `verified=true` quedan prohibidos en Stage1.

**Importante:** el intento de resolver la actualización de ACT-0001 vía `public.lf_router_resolve_v1` reportó `BLOCK_SCOPE_SEMANTICS_UNATTESTED`, `semantic_gap_code=POSITIVE_NEGATIVE_SCOPE_NOT_BOUND` y `downstream_execution_allowed=false`. Por tanto, este lote está limitado a **código fuente y pruebas candidatas**. No se creó ni aplicó una migración ni se activó Stage1/Stage2 en Supabase. Para activar el siguiente nivel, la operación deberá acreditar alcance semántico positivo/negativo, origen y destinatario exactos, pasar PASE y los controles del LF Migration Merge Train. No fabricar recibos para suplir ese bloqueo.

## Estado y siguientes lotes

**Este lote** congela solo politica candidata + pruebas estructurales. No modifica `LF_ROUTER_STAGE1_V1` ni su validador productivo.

**Lote 2:** ampliar formalmente Stage 1, definir entrada/salida tipadas, adaptar el validador Python y SQL conservando compatibilidad; no interpretar confidence como permiso.

**Lote 3:** integrar `lf_router_route_v1` con selección de canal + autoridad exacta; validar el `capability_hint` contra la intención, cubrir empates y bloqueos; pruebas con rollback; PR/PASE/Train.

**Lote 4:** integrar recibos, retorno del especialista y habilitación gradual por canal después de sus propios gates.

**No cerrado todavía:** validacion final del nombre OPERACIONES, operaciones de negocio expuestas por un handler autorizado y su enlace gobernado; mapeo completo de las 28 operaciones existentes a responsable/consumidor; criterios de scoring y empates; validación de permisos y status por operación; invocador del Stage 1. Estos faltantes no autorizan a suponer disponibilidad.
