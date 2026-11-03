# PG-01 C4 y C7: diseño del siguiente incremento

Fecha: 2026-10-23. Estado: PROPUESTA_SOURCE_ONLY.
Base del receptor: 80db71a7e240da70445fecc875e3f0615f53f17f, PR draft #3135.
Alcance autorizado: diseño local del siguiente incremento. Sin push, merge, apply ni activación.
El diseño inicial no acreditaba implementación. Actualización posterior: validadores estructurales locales implementados; ver PG01_C4_C7_LOCAL_REVIEW_V1.md. No cierre P1/I0 ni revisión independiente.

## Fuentes comprobadas

| Fuente | Revisión o versión | Hallazgo |
|---|---|---|
| Plan definitivo, v2 17:00 | Archivo del 23-oct | 2A.e exige C4; 2A.f exige C7 |
| Desglose de Programación, revisado con Paulo | Archivo 21-oct, revisión 22-oct | Define los seis componentes de C4 y cinco dimensiones de C7 |
| paulozterra/lf-programming-sandbox | 9f35f69cab231ad683f39431585236b78c9d96b9 | standards/catalog.json: 0.6.1, BORRADOR_EN_REPO_DE_CALIFICACION |
| Mismo repo y commit | standards/consumption/policy.json: 0.1.0 | STANDARD; presupuesto POR_DEFINIR; BUDGET_UNCONFIGURED_MEASURE_ONLY |
| Mismo repo y commit | standards/consumption/pricing.json: 0.1.0 | Las entradas tienen approved_for_use=false; existencia de precios no autoriza llamadas |
| Mismo repo y commit | standards/pins.json: 0.1.0 | minimum_safe_versions tiene valores null; no prueba por sí sola un pin de seguridad vigente |
| paulozterra/lf-architecture | bbe718c6a5981a2e873818dc1e5fd0313723501f | README requiere citar commit exacto; arquitectura AWS V1 por proyecto |
| cristhianlujan/libertad-financiera | 994bda4aac4f92ea40531a2e84fdad6765397e84 | Árbol completo inspeccionado: no se identificó manifiesto de reglas técnicas L3 |
| Receptor candidato #3135 | 80db71a7e240da70445fecc875e3f0615f53f17f | C4 y C7 están en pending_gates; execution_allowed=false |

El catálogo se consultó por commit exacto. Se conserva su estado de borrador.
La búsqueda del manifiesto describe únicamente el árbol de producto indicado; no acredita ausencia en otros repos o ramas.
El producto es un ejemplo de destino inspeccionado, no el destino universal del receptor.
La arquitectura futura no demuestra que el producto actual ya use Spring/Flyway/AWS.

## Decisión de diseño

Mantener PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 con schema_version y sus siete campos de negocio.
Agregar technical_framework y sufficiency_report a la envoltura del resultado.
La proyección material de la siguiente versión deberá conservar el snapshot completo y añadir ambos resultados.
material_projection_sha256 se calculará sobre esa proyección completa; así los pins y la suficiencia quedan ligados al recibo sin agregarle campos.
La proyección actualmente implementada solo contiene scope_id y snapshot; este cambio aún no está escrito.
No alterar ni reescribir el snapshot persistido, el contrato A9 o el digest vigente d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8.

La frontera actual puede emitir ACCEPT de lectura con C4/C7 pendientes.
La futura admisión previa a planificar requerirá ambas comprobaciones; ese ACCEPT de frontera no podrá usarse como aprobación de suficiencia.
Ante una carencia, el resultado agregado será BLOCK, con diagnóstico MISSING cuando corresponda y retorno a Fase 1.
Si el contexto es identificable, se conservará el recibo auténtico con verdict BLOCK. Un fallo temprano seguirá usando receipt=null.

## C4: marco técnico fijado por pedido

| Componente | Datos que debe fijar | Comprobación | Si falta |
|---|---|---|---|
| Catálogo PG-00 C3 | repo, commit, path, versión, digest de bytes | Leer artefacto exacto; comprobar versión y hash; conservar estado de admisión | STANDARDS_CATALOG_MISSING_OR_UNADMITTED |
| Perfil técnico tipo B | repo destino, commit, path del manifiesto, versión, huella, namespace del proyecto y códigos de reglas | El manifiesto pertenece al destino; resolver contenido en su esquema; nunca copiar autoridad ni asumir lf_ops | TECHNICAL_PROFILE_MISSING |
| Mecanismo de control | referencia versionada al mecanismo del destino y evidencia de aplicabilidad | Plataforma LF usa Router/PASE/Train; producto usa su CI y pipeline vigente; Flyway solo si aplica al destino real | CONTROL_MECHANISM_UNRESOLVED |
| Arquitectura D15 | repo, commit exacto, paths y digest del perfil pertinente | Debe pertenecer al proyecto y ser aplicable al scope; no inferirlo por nombre | ARCHITECTURE_PROFILE_MISSING_OR_MISMATCH |
| Optimización PG-00 C11 | policy_version, referencia exacta y modo seleccionado | El modo existe en la política y mantiene estándares, revisiones y pruebas | OPTIMIZATION_POLICY_MISSING_OR_INVALID |
| Presupuesto D17 | política, moneda, monto o estado explícito de no configuración, umbrales y procedencia | No inventar monto; conservar POR_DEFINIR y MEASURE_ONLY cuando así lo dispone la fuente | BUDGET_UNCONFIGURED_MEASURE_ONLY |

Los códigos de esta tabla son propuesta del consumidor, no códigos instalados en Supabase.
BUDGET_UNCONFIGURED_MEASURE_ONLY permite describir/medir el estado de la política; no demuestra un presupuesto fijado ni cierra C4.
El catálogo fuente y el consumo ya existen; falta la admisión de sus pins para este consumidor y pedido.
Un manifiesto puede declarar explícitamente uso de valores L2 cuando el proyecto no tiene reglas propias; el receptor no debe declararlo por su cuenta.
Las reglas tipo A se conservan tal como llegaron en el snapshot. C4 no consulta otras para sustituirlas.

El proveedor será de lectura y deberá hidratar artefactos por identidad exacta, con procedencia comprobable.
No aceptar un booleano CURRENT/VALID o un hash declarado por quien llama como prueba de validez.
Reutilizar CURRENTNESS_AUTHORITY; extender sus materiales ligados al pedido para incluir los pins técnicos.
Si un material requerido cambia, aplicar su política de currentness; no mover el pin silenciosamente durante la ejecución.
No crear otro motor de vigencia, almacén, Router o runtime.

## C7: suficiencia antes de planificar

Evaluar el scope solicitado y su cierre de dependencias ya admitido. No importar bloqueos de scopes independientes.
Reutilizar implementability_schema.requirements y canonical_implementation_bindings.
Cada hallazgo debe citar requirement_id, scope_id, binding_id, canonical_ref y evidencia/currentness cuando existan.
Una referencia debe pertenecer al snapshot exacto y al scope; no alcanza que exista una fila de otro scope.

| Dimensión | Exigencia cuando aplica | Qué no puede inventar el receptor |
|---|---|---|
| Mensajes | Copy exacto y binding canónico del mensaje/resultado definido por Análisis | Texto, tono o traducción |
| Errores | Código del catálogo del proyecto, comportamiento y texto aplicable vinculados al requisito | Código o mensaje técnico nuevo |
| Navegación | Eventos definidos para el scope y referencia a su catálogo | Qué eventos registrar |
| Historial | Respuesta explícita sobre necesidad de historial por entidad afectada | Un sí/no implícito por ausencia |
| Consentimientos | Aplicabilidad y referencias a documentos/textos/versiones requeridos | Consentimiento, texto legal o aprobación legal |

NOT_APPLICABLE requiere decisión explícita de Análisis con motivo y evidencia, vinculada al scope.
Una colección vacía, un binding no resuelto o el silencio no significan NOT_APPLICABLE.
No exigir que todo cambio tenga cinco funcionalidades nuevas: exigir respuesta material de aplicabilidad y lo necesario donde sí aplica.
Los documentos DEMO no acreditan un consentimiento apto para producción.
PG-01 no otorga aprobación legal ni habilita producción.

El contrato A6 usa un catálogo abierto de binding_kind; no define una correspondencia universal para estas cinco dimensiones.
Primero documentar el mapeo consumidor de bindings existentes; si falta o es ambiguo, devolver MISSING/CONTRADICTION.
No introducir campos obligatorios nuevos en A9 ni un nuevo binding_kind operativo sin alinear el contrato de conexión C1.
Hasta disponer de ese mapeo y del paquete, no se puede acreditar C7.

Salida propuesta de sufficiency_report:
- status: COMPLETE, MISSING o CONTRADICTION;
- evaluated_scope_ids y contexto exacto;
- por dimensión: aplicabilidad explícita, binding_ids y canonical_refs comprobados;
- missing_items con rutas concretas, scope y requisito;
- return_target: ANALYSIS si falta material;
- ningún texto o decisión material generado para rellenar una carencia.

## Secuencia del siguiente cambio de código

1. Conservar el emisor y la base SQL de #3135 como frontera de lectura.
2. Añadir validadores puros de C4/C7 y puertos de evidencia; no abrir conexiones ni recibir credenciales.
3. Probar mapeos candidatos con fixtures marcados SYNTHETIC; los puertos operativos quedarán pendientes de admisión.
4. Agregar una evaluación previa a planificar que consuma esa frontera, mantenga snapshot/identidades y emita diagnóstico agregado.
5. Incluir marco técnico y suficiencia en la proyección material y recalcular su digest.
6. Mantener execution_allowed=false y la persistencia C6 pendiente. Un positivo sintético no cierra C1, P1 o I0.
7. Publicar por la cuenta de Paulo cuando esté disponible; el CI anterior no valida cambios locales posteriores.

No habrá nueva migración en este incremento. Los archivos propuestos irán en wave1_boundary_contracts, familia fija PROGRAMMING_AGENT_TESTS.
No cambiar MANAGED_PREFIXES, registry de familias, workflows, rulesets o mecanismos de admisión.

## Matriz de pruebas prevista

| Caso | Resultado esperado |
|---|---|
| Marco sintético completo, cinco dimensiones explícitas y snapshot válido | ACCEPT_SOURCE_ONLY; ejecución deshabilitada |
| Falta cualquiera de los seis componentes de C4 | BLOCK con código y ruta |
| Catálogo con versión/hash diferente | BLOCK |
| Manifiesto de otro repo/proyecto o namespace no declarado | BLOCK |
| Perfil de arquitectura con ref mutable o commit distinto al esperado | BLOCK |
| Control de plataforma aplicado por defecto a producto | BLOCK |
| Modo desconocido o que relaja revisiones/tests | BLOCK |
| Política real 0.1.0 con POR_DEFINIR | MEASURE_ONLY explícito; C4 sigue pendiente |
| Presupuesto agotado en fixture configurado | REQUIRES_DECISION; no recorta calidad |
| Falta mensaje/código/evento/historial/consentimiento aplicable | MISSING; retorno a Análisis |
| Texto sin canonical_ref o valor no resuelto | MISSING |
| Ausencia/array vacío interpretado como no aplica | MISSING |
| NOT_APPLICABLE explícito y sustentado | Se conserva sin inventar funcionalidad |
| Binding de otro contexto o scope | BLOCK |
| Dos decisiones incompatibles de aplicabilidad | CONTRADICTION |
| Scope independiente bloqueado junto a scope evaluado completo | No contamina el scope completo |
| Dependencia material incompleta | BLOCK del scope dependiente |
| Documento DEMO presentado como válido para producción | BLOCK de esa pretensión |
| Cambia un pin técnico o la suficiencia | Cambia material_projection_sha256 |
| Mismo contexto, pins y evidencia | Resultado/recibo idénticos |
| Proyección propuesta elimina un pin, obligación o dimensión | BLOCK |
| Excepción del proveedor de evidencia | BLOCK sin fabricar hash o recibo |

Son casos previstos, no pruebas ejecutadas. Las 97 comprobaciones locales y el CI del HEAD anterior no cubren esta propuesta.

## Estado y siguiente acción

C4: diseño y validador estructural local implementados; manifiesto del destino, admisión de pins, currentness y presupuesto fijado siguen pendientes.
C7: validador estructural local y mapeo sintético implementados; acuerdo A9 y readback semántico pendientes.
C6: emisión ya implementada en #3135; persistencia depende de D7.
P1/I0: abiertos. Revisión independiente pendiente.
La cuenta de GitHub del servidor sigue siendo cristhianlujan; no se hizo push ni se cambió su autenticación.

La implementación local de los validadores puede avanzar con fixtures sin inventar los datos operativos faltantes.
El positivo real seguirá dependiendo de un snapshot A9 admitido y de la evidencia técnica del proyecto correspondiente.
