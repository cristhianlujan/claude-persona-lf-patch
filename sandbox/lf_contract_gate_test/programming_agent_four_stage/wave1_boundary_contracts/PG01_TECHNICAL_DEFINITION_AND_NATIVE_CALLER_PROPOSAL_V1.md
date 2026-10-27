# PG-01 · Contrato técnico y llamador operacional (propuesta, 27-oct-2026)

Estado: SOURCE_ONLY_DESIGN_CANDIDATE. No crea autoridad, operación, proveedor, rol, grant, tabla ni hook.
Continúa el diseño de #3194 (`TECHNICAL_REPAIR_AND_NATIVE_OBSERVATION_DESIGN_V1.md`) sin modificarlo.
No acredita P1, PR2, I0 ni I1.

## Hechos leídos en vivo (solo lectura, 27-oct)

| Hecho | Consecuencia |
|---|---|
| `fn_lf_decision_context_asof_record_v1` es ejecutable por `anon` y `authenticated`; los 3 actores registrados no son ejecuciones | La procedencia del snapshot no está probada hoy. Corrección de permisos en #3197 |
| No existe ninguna `EJECUCION_PERFIL_LF` con canal `PROGRAMACION`, Native ni runtime. Las Native con canal son de `PRODUCTO` | El llamador no tiene todavía un caso real que observar |
| `lf_profile_native_bridge_*`, `lf_profile_result_router_return_{classify,prepare}_v1` y `lf_router_profile_after_selection_v1`: `SECURITY DEFINER`, solo `service_role` | El llamador necesita identidad de servicio |
| `lf_profile_execution_terminal_authority_receipt_v1(text)`: `STABLE SECURITY DEFINER`, solo `service_role`; exige `COMPLETED`, juez `PASS` y 11/11 pasos limpios | Es el readback autorizado de cierre que el llamador debe usar, en vez de leer pasos sueltos |
| `#3148` agrega `CompletionObservation` a `profile_runtime_api`: aviso con proyección escalar, 2 hilos, sin reintentos ni acceso al resultado | Sirve para ejecuciones del runtime; no ve las Native, que cierran en la BD |
| Cuerpo hospedado del escritor as-of ≠ bytes de su migración Git (iguales salvo espacios) | La paridad fuente/vivo debe reportarse aparte de la vigencia |

## B. Contrato para reparaciones técnicas

Contrato: `technical_definition_contract_v1.json`. Prototipo probado: `test_technical_definition_provider_prototype_v1.sql`.

### Identidad del activo

`lf-technical-definition://<proyecto>/FUNCTION/<esquema>.<nombre>(<tipos de entrada>)`, con la forma canónica `format('%I.%I(%s)', esquema, nombre, oidvectortypes(proargtypes))`.
Ejemplo real: `lf-technical-definition://mhwmirqcgxxukpctffuv/FUNCTION/public.fn_lf_decision_context_asof_record_v1(jsonb, text)`.

- Cada sobrecarga es un sujeto distinto. Un nombre sin firma se rechaza.
- Una grafía distinta de la canónica (por ejemplo `(jsonb,text)`) se rechaza: el recibo debe atarse a una sola cadena.
- V1 cubre solo `FUNCTION`. Tablas, vistas, políticas y triggers quedan para después.

### Fuente autorizada y estado observado

- **Estado observado** (lector `SECURITY INVOKER`, solo catálogo): `body_sha256` de `prosrc`; `attrs_sha256` de propietario, lenguaje, `SECURITY DEFINER`, volatilidad, `config` y tipo de retorno; ACL normalizada (`aclexplode` sobre `coalesce(proacl, acldefault(...))`, ordenada, `PUBLIC` explícito) y su `acl_sha256`.
- **Pin de fuente:** repo, commit, ruta de migración y blob. Git se resuelve fuera de la BD (CI o llamador).
- **Paridad fuente/vivo:** se reporta aparte. Caso real: el escritor as-of vivo (`body_sha256 8d2dc448…`) es igual a su migración solo ignorando espacios. Bloquear por bytes exactos hoy rechazaría activos sanos; no exigirla deja pasar deriva real. Decisión pendiente (D-B2).

Valores vivos del caso real (27-oct): `body_sha256 8d2dc448d08fdb4ad1d227548d2a3ba0dd96f8b72fc4b54ca5636ca5b967ed76`, `attrs_sha256 1b737d35882c88c8eb0b2f984e4a7067e3e477d51e3c4fbbea5e7653261d6bd4`, ACL `PUBLIC, anon, authenticated, postgres, service_role` con `EXECUTE`.

### Definición, alcance y criterio de éxito

Una definición técnica declara: pin observado, pin de fuente, `allowed_refs`, `allowed_dimensions` (`ACL`, `BODY`, `ATTRS`), los cambios (antes y después), criterios verificables y rollback.
Para #3197 sería: un solo sujeto, solo `ACL`, ACL destino `postgres` + `service_role`, `body_sha256` sin cambio y privilegio efectivo falso para `anon` y `authenticated`.

### Vigencia

Se relee el estado observado en cuatro momentos: snapshot A9, escritura del recibo, admisión y justo antes de etiquetar el PR para el Train.
Respuestas: `DEFINITION_NOT_FOUND`, `DEFINITION_CHANGED_BODY|ATTRS|ACL`, `SOURCE_PIN_MISSING`. Toda deriva vuelve a Análisis (`RETURN_TO_ANALYSIS_NO_CODE`). Reutiliza el vocabulario de `CURRENTNESS_AUTHORITY`; no crea otra tabla de snapshots.

### Evolución de la admisión

V2 no cambia: sigue siendo solo `SCREEN`. La propuesta es una versión siguiente discriminada por `definition_kind ∈ {SCREEN, TECHNICAL_ASSET}`, un solo tipo por sobre, con proveedor y selección propios para cada tipo. Prohibido fabricar una pantalla o pasar un activo técnico por el selector de pantallas.

### Prueba del prototipo (PostgreSQL 17.6, ROLLBACK): 63/63

| Grupo | Casos |
|---|---|
| Identidad | Firma exacta; grafía no canónica; sobrecarga equivocada no es el sujeto; firma inexistente; nombre sin firma; referencia de pantalla; tipo no soportado; otro proyecto |
| Vigencia | Pin vigente; pin de fuente ausente; deriva de ACL; de cuerpo; de atributos; sujeto eliminado |
| Delta | En alcance; sujeto ajeno; cambio de cuerpo en una reparación solo de ACL; destino aún no cumplido; cumplido tras el delta; cuerpo intacto |

Se añaden 43 negativos estructurales: objeto raíz, arrays obligatorios y no vacíos, cada cambio como objeto, sujetos y dimensiones obligatorios/no nulos, referencias no vacías y dimensiones ACL/BODY/ATTRS. `DELTA_INVALID` se resuelve antes de cualquier predicado de pertenencia; `DELTA_EMPTY` conserva su significado. Esto corrige los deltas incompletos que antes daban `DELTA_IN_SCOPE`.

El prototipo vive en un esquema creado dentro de la transacción. No es un proveedor admitido ni un objeto propuesto para hosted.

## C. Llamador operacional

### Componente e identidad

Un único **llamador de admisión de Programación**, determinista y sin modelo (cumple `ZERO_COST_ONLY`). Dos fuentes de observación, un solo camino:

1. Ejecuciones del runtime: el aviso de `CompletionObservation` (#3148), tratado solo como pista.
2. Ejecuciones Native: sondeo de `lf_operation_execution` con `operation_code=EJECUCION_PERFIL_LF`, canal `PROGRAMACION` y `status=COMPLETED`, porque Native cierra en la BD y no pasa por el runtime.

Identidad propuesta: un rol de servicio dedicado con `EXECUTE` solo sobre las funciones de la secuencia. Hoy solo existe `service_role`; usarlo amplía la superficie (decisión D-C1).

### Secuencia

| Paso | Qué hace | Fuente de verdad | Si falla |
|---|---|---|---|
| 1 | Detectar candidata (`COMPLETED`, canal `PROGRAMACION`) | `lf_operation_execution` | Nada que hacer |
| 2 | Readback de cierre | `lf_profile_execution_terminal_authority_receipt_v1` = `PASS` | `NOT_TERMINAL`: reintentar más tarde |
| 3 | Clasificar el retorno | `classify_v1` y `prepare_v1` (#3180) devuelven `programming_admission_request` | Otra continuación: no es de Programación |
| 4 | Contexto | `context_id` y `context_sha256` salen de la fila as-of cuyo actor es esta ejecución, leída en la BD y comparada con el handoff; nunca del texto del modelo | `PG01_RUNTIME_SNAPSHOT_NOT_FROM_SOURCE`: volver a Análisis |
| 5 | Juez | Buscar una `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` `COMPLETED` cuyo `subject_sha256` sea el del contexto. El llamador no la crea ni la emite | `WAITING_INDEPENDENT_JUDGE`: estado tipado, sin bucle |
| 6 | Escribir el recibo | `fn_lf_programming_receipt_record_runtime_v1` (#3193), idempotente por la clave D7 | Error tipado del escritor |
| 7 | Releer el recibo | `resolve_v2` (#3181) | `PG01_V2_RECEIPT_NOT_FOUND`: volver a Análisis |
| 8 | Admisión | `lf_programming_development_admission_v1(binding, handoff, source_execution_id)` (#3176), llamada por el llamador, nunca desde `prepare_v1` | Respuesta tipada de la compuerta |
| 9 | Registrar el resultado | Bitácora del llamador; `downstream_execution_allowed` sigue en `false` hasta I1 | — |

### Idempotencia y reintentos

- La pareja `(source_execution_id, context_sha256)` es solo un índice de observación, no una clave suficiente de deduplicación.
- **D7** normaliza seis campos: context_id, context_sha256, target_ref, requested_scope_ids (ordenados y sin duplicados), producer_execution_ref y entry_contract_digest_sha256. El SQL calcula `binding_key_sha256` con el JSONB canónico; el llamador no sustituye ese cálculo por serialización JSON de Python.
- **Identidad del llamador**: source_execution_id + los seis campos normalizados + el router_action_binding íntegro, con namespace/version propios. `caller_request_identity` es un fingerprint distinto del digest D7. Cambiar target, scopes, contexto, productor, digest de contrato o binding del Router no reutiliza una identidad anterior. El productor debe ser la misma ejecución de origen.
- Un replay siempre vuelve a verificar cierre, contexto, juez, currentness y admisión. No cachear un resultado positivo como autorización permanente. El escritor D7 evita duplicar su recibo; eso no demuestra recuperación durable de toda la secuencia.
- Reintentos solo ante errores transitorios (conexión o tiempo de espera): hasta 3, con espera creciente.
- Los estados terminales (`STALE`, `NOT_FOUND`, `SOURCE_MISMATCH`, `JUDGE_INVALID`) no se reintentan: devuelven retorno tipado.
- Recibo vencido (más de 24 h) o definición cambiada: retorno a Análisis, nunca reescritura.
- La observación nunca modifica `report_output`, `COMPLETED`, la continuación calculada ni la ruta del pedido.

### Lo que falta para cablearlo

Quién registra el snapshot A9 (D-A1), con qué rol corre el llamador (D-C1), dónde corre (D-C2), quién crea la ejecución del juez (D-C3) y el proveedor de contrato de ejecución del motor de #3166, que sigue sin admitir. Son proveedores distintos: resolver el técnico no resuelve el del motor.

## D. Verificación en PostgreSQL 17 y requisitos de I0

### Pruebas repetidas en PostgreSQL 17.6 desechable (27-oct)

Binarios `postgresql-17.6.0-x86_64-unknown-linux-gnu` con sha256 verificado contra el publicado; solo socket Unix; cada prueba en su propia base nueva.

| Prueba | HEAD | Resultado |
|---|---|---|
| Sobre V2 y lector (#3181) | `793b6ff` | 19/19 |
| Compuerta de entrada (#3176) | `96c2388` | 21/21 |
| Entrada con lectores D7/V2 reales (#3176) | `96c2388` | `REAL_READERS_OK` |
| Escritor runtime (#3193) | `87e0f87` | 21/21 |
| Retorno tipado (#3180) | `1adb331` | 9/9 |
| Composición (#3194, generador con hash de compuerta `c0ec44b9…` verificado) | `8e87fad` | 8 grupos (`PG01_CANDIDATE_COMPOSITION_PASSED:8`) |
| Adaptador Native (#3194) | `8e87fad` | 10/10 (unittest) |
| Permisos del escritor as-of (#3197) | `9d0f5ae` | 16/16 |
| Prototipo de proveedor técnico (este PR, actualizado) | — | 63/63 |

Las fixtures siguen siendo sintéticas (catálogo, perfil, juez, recibo terminal). Estas corridas no son evidencia hospedada ni de CI.

### Qué falta para acreditar I0

| Requisito | Estado al 27-oct |
|---|---|
| Ejecución real `EJECUCION_PERFIL_LF` con canal `PROGRAMACION` | No existe |
| Perfil de Análisis en el catálogo del selector | No existe (Cristhian los está creando) |
| Pantalla `VIGENTE` con módulo | No existe: las dos `VIGENTE` tienen `module_id` nulo |
| Snapshot A9 registrado por la ejecución correcta | Bloqueado por H1 hasta #3197 y D-A1 |
| `target_ref` igual a su definición; actor en `issued_by_execution_id` | Pendiente de D-A1 |
| Juez independiente del mismo sujeto | 0 ejecuciones `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` con sujeto `PROGRAMMING_ANALYSIS_PACKAGE/…` |
| Recibo persistido, releído, replay idempotente y negativos de vigencia sobre datos reales | Solo con fixtures |

## Decisiones pendientes

| # | Decisión | Dueño |
|---|---|---|
| D-B1 | Aprobador de un delta técnico y cómo se ata la aprobación al `subject_sha` | Cristhian |
| D-B2 | Regla de paridad fuente/vivo: bytes exactos, normalizada o solo informativa | Cristhian |
| D-B3 | Qué perfiles pueden emitir un A9 técnico | Cristhian |
| D-C1 | Rol del llamador: dedicado o `service_role` | Cristhian |
| D-C2 | Dónde corre: worker del runtime, Edge Function o job programado | Cristhian |
| D-C3 | Quién crea la ejecución del juez independiente | Cristhian |


## Continuación del 27-oct: corrección estructural, identidad y simulación

Main integrado: `b57c5de166e9cf3d452239424292a6ce82a0b96f` (merge Train de #3197 observado en GitHub; no se atribuye ese merge a este trabajo). La aplicación/readback hosted no se certifica con esta observación.

### Simulación del llamador

`caller_simulation_v1.py` es diseño ejecutable exclusivamente sintético: no es un adaptador operacional, no tiene credenciales, transporte, scheduler, modelo, sleeps ni acceso a BD. Requiere puertos explícitamente sintéticos, sin considerar ese marcador una barrera de seguridad. Los estados de las fixtures son una proyección de prueba; un adaptador futuro debe validar y traducir los contratos reales de readback, incluido el recibo terminal completo.

`test_caller_simulation_v1.py`: 21 tests unitarios. Cubre orden de lectura, cierre no terminal/ajeno, continuación ausente, origen/contexto ajenos, juez ausente o inválido (nunca creado), recibo ausente/vencido/revocado, booleanos tipados, operación inactiva, autoridad inesperada, reintentos transitorios hasta tres intentos, agotamiento, respuesta perdida después de escribir y replay sin duplicado en el ledger simulado. Un replay reconsulta vigencia; inputs y snapshots no se mutan. Ningún resultado habilita ejecución: operational_admission y downstream_execution_allowed permanecen false.

No demuestra permisos reales, autenticidad del juez, coordinación entre procesos, persistencia de la bitácora, backoff ni recuperación durable; esas partes siguen dependiendo de D-C1..C3 y de un adaptador admitido.

### Contraste con D7 real

`test_pg01_d7_caller_identity_v1.sql` se añade al final de la composición rollback-owned de #3194, antes del ROLLBACK. Usa el resolver D7 real y el recibo creado por el escritor runtime real con fixtures: duplicar el scope conserva receipt_record_id/binding_key_sha256; cambiar por separado cualquiera de los seis campos no encuentra el recibo anterior. Son 7 comprobaciones adicionales, sin reemplazar los 8 grupos originales.

Reproducción: generar la composición con el builder de #3194 y su gate fijado. Conservar `composition.sql` y `sources.json`; producir otro archivo SQL que inserte este test antes del ROLLBACK final. Ejecutarlo desde el directorio generado en PostgreSQL desechable. La simulación Python se ejecuta desde esta carpeta con `python3 -m unittest -v test_caller_simulation_v1.py`.

Resultado de esta continuación: prototipo 63/63 y composición 8 grupos + identidad D7 7 comprobaciones en PostgreSQL 17.6; simulación 21/21 en Python. Todas las entradas de autoridad, catálogo, perfil y juez siguen siendo fixtures explícitas. Sin efectos hosted ni cierre P1/PR2/I0/I1.
