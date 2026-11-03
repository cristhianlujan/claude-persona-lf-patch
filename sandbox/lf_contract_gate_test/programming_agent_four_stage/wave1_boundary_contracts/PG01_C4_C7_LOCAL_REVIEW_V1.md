# Revisión local PG-01 y avance C4/C7

Fecha: 2026-10-23. Estado: SOURCE_ONLY_LOCAL_VALIDATORS.
Base revisada: 424e6df9c4abc2ab370bae0d77803de2f86a2670.
Sin push, apply, merge, runtime o cierre PG-01. Revisión del implementador; no revisión independiente.

## Qué se corrigió

ReadOnlyReceiver podía lanzar AttributeError cuando el puerto de currentness devolvía None, lista, texto o booleano.
Se reprodujo sin acceso a BD. Ahora devuelve BLOCK / CURRENTNESS_RESULT_INVALID con recibo BLOCK del contexto identificado.
También rechaza una respuesta ready/CURRENT que omite bounded_validation_required o devuelve un tipo no booleano.
Una evaluación canónica que pide validación acotada sigue devolviendo BOUNDED_VALIDATION_REQUIRED.

Se verificaron los hashes de las dos migraciones fuente de #1912/#2306.
La migración candidata no cambia en este incremento.
La guardia SQL y los tres wrappers siguen sujetos a la misma ruta de aplicación futura.

## Código añadido

programming_pg01_preplanning_checks_v1.py contiene dos validadores puros:
- validate_technical_framework: revisa los seis componentes de C4; verifica bytes contra digest, commit exacto, identidad del destino, versiones, controles, modo y presupuesto;
- validate_sufficiency: revisa cinco dimensiones por scope y cierre READY; exige evidencia canónica resuelta, aplicabilidad explícita y cobertura de requisitos.

No hay conexión a DB, descubrimiento, lectura de credenciales, modelo o servicio de pago.
El lector de artefactos se inyecta y debe resolver la identidad exacta del pin.
Los validadores no persisten ni emiten recibos de admisión.

Todos los resultados incluyen validation_level=SOURCE_ONLY_LOCAL_STRUCTURE, execution_allowed=false y operational_admission=false.
COMPLETE significa completitud estructural local. No afirma vigencia, admisión semántica, autoridad legal ni permiso de programar.
El estado de borrador del catálogo se conserva; no se promueve.

## Interfaz candidata y límites

C4 espera una envoltura de referencia que fija target_repo, project_ref, cinco pins, optimization_mode y request_budget.
Cada pin identifica repo, commit, path, sha256 y versión cuando aplica. El lector devuelve los bytes exactos.
Los artefactos de catálogo y política de consumo usan sus schemas existentes.
Los schemas PG01_PROJECT_TECHNICAL_PROFILE_CANDIDATE_V1 y PG01_CONTROL_MECHANISM_CANDIDATE_V1 son propuestas de adaptador; no se afirma que existan en el proyecto.
La arquitectura puede ser texto nativo; el binding del adaptador declara proyecto y repos aplicables.
La procedencia de ese binding y CURRENTNESS_AUTHORITY sobre los pins siguen pendientes.

El presupuesto del fixture debe coincidir con la política fijada; el consumidor no puede inventar un override.
Una política con POR_DEFINIR devuelve MISSING y MEASURE_ONLY aunque el caller proporcione un monto.
Con un presupuesto sintético configurado: aviso al 80 %, REQUIRES_DECISION al 100 %.
No se efectúa gasto ni se comprueban precios externos.

C7 usa un binding_map candidato con:
- schema_version PG01_SUFFICIENCY_BINDING_MAP_CANDIDATE_V1;
- snapshot_sha256 calculado con el hash canónico existente sobre el snapshot;
- source_ref del mapeo;
- binding_kinds, una correspondencia distinta por cada una de messages, errors, navigation, history y consents.

No hay binding_kind operativo nuevo por defecto. Los tests usan FIXTURE_<dimension>.
El mapeo debe acordarse con A9 antes de uso operativo; si falta, devuelve MISSING.
El valor normalizado de un binding candidato usa PG01_SUFFICIENCY_DECISION_CANDIDATE_V1:
dimension, requirement_ids, reason, disposition APPLICABLE/NOT_APPLICABLE e items.
Estos datos solo se prueban como fixtures sobre el catálogo abierto de A6; no se agregan campos obligatorios al snapshot.
APPLICABLE exige materiales; NOT_APPLICABLE exige respuesta explícita sustentada y items vacío.
Un literal resuelto sin comprobación independiente no es prueba de verdad canónica: el readback semántico sigue pendiente.

Se preservan los siete campos del recibo y el digest del contrato A9.
El recibo actual sigue describiendo la frontera de lectura; C4/C7 permanecen en pending_gates.
La integración de ambos resultados en la proyección material y en la admisión previa a planificar sigue pendiente.
No se conectó automáticamente un COMPLETE local para quitar gates o habilitar un scope.

## Verificación ejecutada

| Nivel | Resultado | Alcance |
|---|---|---|
| Unitarias locales | 27 tests satisfactorios, con subcasos | C4/C7 y regresión de currentness malformado |
| Postgres local | 88 comprobaciones coincidentes | Base SQL y emisor; catálogo/proveedor sintéticos |
| Payload existente | Positivo, 14 negativos y dos negativos del ensamblador satisfactorios | Validador determinista previo |
| Contratos Wave1 | 99 negativos satisfactorios | Self-test previo |
| Históricos | No repetidos en esta corrida | Se conserva la evidencia anterior, sin atribuirla al código nuevo |
| CI | No ejecutado para este incremento local | #3135 sigue en el último HEAD publicado |

La matriz de 22 casos del diseño es un plan para el incremento completo.
Todavía no se ejecutaron los casos de cambio de hash/proyección del marco integrado ni una prueba de proveedor operativo.
No confundir los 27 tests implementados con cobertura completa de esa matriz.

pg01_c4_c7_local_validation_20261023.json registra nombres de tests, digests del código probado y resultados de regresión.
El archivo de evidencia previo de 97 comprobaciones se conserva como evidencia histórica de su fuente, no como validación de este incremento.

## Estado por checkpoint

| Checkpoint | Estado |
|---|---|
| C1-C3 | Frontera candidata existente; comprobaciones locales conservadas |
| C4 | Validador estructural implementado; admisión de fuentes, manifiesto real, presupuesto y currentness pendientes |
| C5 | Regresión local satisfactoria; sin calificación operativa |
| C6 | Emisión existente; persistencia y positivo real pendientes |
| C7 | Validador estructural implementado; mapeo A9 acordado y readback semántico pendientes |
| P1 / I0 | Abiertos |

Siguiente incremento: integrar marco y suficiencia en la proyección/resultado candidato con puertos de evidencia ligados al contexto, sin quitar los gates operativos pendientes.
La publicación queda pendiente de usar la autenticación de Paulo; este trabajo no usa la cuenta de Cristhian para publicar.
