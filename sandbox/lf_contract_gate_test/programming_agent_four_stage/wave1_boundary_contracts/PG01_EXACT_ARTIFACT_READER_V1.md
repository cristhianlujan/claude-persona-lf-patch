# PG-01: lector exacto de artefactos y readback de fuentes reales

Fecha: 2026-10-23. Estado: SOURCE_ONLY_EXACT_ARTIFACT_READER.
Base: 4becd1292321357aa061fd5edd5362272bc8c4d1.
Sin push, apply, merge, credenciales nuevas ni activación.

## Implementación

ExactArtifactReader implementa el callable que consume validate_technical_framework.
LocalGitBackend lee objetos desde repositorios registrados. Exige repo/origin coherentes, commit exacto, path literal y blob regular.
No usa el archivo mutable del worktree. Rechaza rutas externas, traversal, symlinks, objetos no commit, archivos ausentes y tamaños excesivos.
Deshabilita reemplazos de objetos, lectura de configuración global, lazy fetch y prompts de credenciales.
Rechaza clones parciales/promisor antes de leer objetos. No ejecuta fetch, clone, push ni operaciones de red.

ConnectedReadbackBackend acepta exportaciones base64 de un puerto autenticado de solo lectura.
Repo, commit, path y blob deben coincidir con una entrada de árbol previamente registrada.
Comprueba el OID Git del blob desde sus bytes y luego el SHA-256 del pin.
La conexión/autenticación pertenece al adaptador externo; el lector no recibe tokens ni URLs ni selecciona cuentas.
La identidad del registro y su procedencia aún requieren admisión operativa: un origin local no es por sí solo aprobación ni prueba de autorización.

observe lee una revisión explícita y devuelve hechos: identidad, blob, SHA-256 y tamaño.
No devuelve CURRENT/ready ni reescribe el pin. Una observación puede diferir del hash esperado; esa diferencia debe evaluarse por CURRENTNESS_AUTHORITY.
Así puede hidratarse un digest observado en lugar de hacer eco del digest esperado.

## Fuentes reales comprobadas

| Fuente | Commit | Resultado |
|---|---|---|
| Contrato de entrada en claude-persona-lf-patch | 4d399c9ffb20f1d22b69782231e96918a5fdb7bb | Lectura real de objeto Git local; blob 56e561a72f8cfd9d085dd8087b854ff2ac740b1b; SHA-256 d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8 |
| standards/catalog.json, lf-programming-sandbox | 9f35f69cab231ad683f39431585236b78c9d96b9 | Exportación RO autenticada verificada contra árbol/blob; catálogo 0.6.1, BORRADOR_EN_REPO_DE_CALIFICACION |
| standards/consumption/policy.json, mismo repo | 9f35f69cab231ad683f39431585236b78c9d96b9 | Exportación RO exacta; política 0.1.0; presupuesto POR_DEFINIR |
| README.md, lf-architecture | bbe718c6a5981a2e873818dc1e5fd0313723501f | Exportación RO exacta; referencia de arquitectura del proyecto |

Las tres fuentes remotas se consultaron mediante la conexión GitHub de solo lectura en esta ejecución.
El backend se verificó sobre sus exportaciones exactas, no sobre JSON reformateado.
La evidencia conserva solo metadatos/digests. No se incorporan al repo copias de la autoridad ni los blobs exportados.
La referencia de arquitectura leída no demuestra por sí sola aplicabilidad al producto actual ni aprobación de un perfil.
En el inventario de rutas del producto no se identificó un manifiesto L3; no se afirma ausencia en otros repos, ramas o ubicaciones.
Las revisiones main de los tres repos remotos siguen en los commits ya inventariados.

## Pruebas ejecutadas

- 76 tests unitarios únicos satisfactorios: 60 previos más 16 del lector.
- 111 comprobaciones en Postgres desechable, incluidas cinco con lectura de objetos Git de artefactos sintéticos.
- Readback real de un contrato desde Git local y de tres artefactos remotos exportados por RO.
- Observación de un archivo cambiado en otro commit devuelve el digest observado nuevo, manteniendo intacta la lectura del commit fijado.
- No hubo replay histórico en esta corrida ni escrituras Supabase.

La prueba SQL usa contexto/catálogo/proveedor sintéticos con las funciones candidatas reales. Los artefactos Git de esa prueba son fixtures.
Los readbacks reales son evidencia de integridad de lectura por separado; no son un positivo real A9 ni admisión de cinco fuentes de C4.

## Estado del proveedor

La capa de lectura exacta ya está implementada y se conecta al validador C4 en pruebas.
Todavía falta construir/admitir la hidratación operativa completa: revisión vigente autorizada por fuente, contexto A9 real, mapa C7 acordado, manifiesto técnico y control del destino, presupuesto aprobado y readback semántico.
No se completa el binding de catorce materiales declarando observados los valores no resueltos.
El catálogo permanece borrador y POR_DEFINIR no se transforma en un monto.
planning_allowed=false, execution_allowed=false y operational_admission=false se mantienen.
C4, C6, C7, P1 e I0 siguen abiertos.

pg01_exact_artifact_reader_local_20261023.json registra tests, SQL, readbacks reales y hashes de fuentes.
Siguiente: resolver los inputs operativos faltantes y la admisión del proveedor, sin nuevos almacenes ni autoridad paralela.
La publicación/CI sigue pendiente de usar la autenticación de Paulo.
