# PG01_A9_ADMISSION_ENVELOPE_DESIGN_V1

26-oct-2026. Solo diseño dependiente del acuerdo C1. Ningún campo siguiente existe hoy en runtime_output ni se implementa en el receptor. No se modifica programming_entry_contract_v1.json, su digest d2e347ef…, el recibo de siete campos, Router, D7 ni runtime.

## Marco v3

A9 es interno al agente de Programación y pertenece al frente de Paulo. A9 ensambla; el juez semántico gobernado independiente evalúa, y la operación que registra su resultado aporta la procedencia admitida. No se espera a un productor A9 externo. Véase A9_ASSEMBLER_SOURCES_V1.md para las fuentes y límites de las funciones as-of, y PG01_D7_OPTION_A_SPEC_V1.md para la propuesta D7-A. Todo sigue en diseño.

## Objetivo y punto de entrada

Antes de cualquier ACCEPT, PG-01 deberá exigir una admisión A9 obtenida por un lector gobernado con expectativas independientes, asociada al mismo paquete, snapshot exacto, ejecución/pedido/target y scope solicitado. Un objeto entregado por el caller o firmado por el propio modelo no constituye admisión. candidate_only=true se conserva como propiedad del artefacto candidato original; no se cambia a false para aparentar autoridad.

## Contenido mínimo propuesto, sin inventar API existente

Estos son requisitos semánticos del futuro envelope. Los nombres JSON finales, schema/discriminador y autoridad se acuerdan en C1; no se publica un schema implementable con campos ficticios.

| Contenido propuesto | Validación futura | Carencia actual |
|---|---|---|
| Referencia inmutable del paquete ANALYSIS_IMPLEMENTATION_PACKAGE_V1 | Repo/commit/path o referencia canónica equivalente, readback exacto y versión; ninguna resolución latest | runtime_output solo lleva discriminador y referencias libres |
| Digest del paquete y algoritmo/canonicalización | Recalcular sobre bytes exactos o representación canónica explícita; distinguir SHA de paquete/contrato/snapshot | No emite digest ni política de hash |
| Referencia al contexto persistido y hash exacto | Resolver context_id/context_sha256 y verificar correspondencia paquete↔snapshot sin reinterpretación mutable | ExpectedHandoff local existe, pero no prueba que el paquete fue admitido |
| Identidad de ejecución, pedido y destino | Vincular operación/ejecución real, productor, pedido exacto y target/revisión al mismo admission scope | stage_trace no contiene identidad de ejecución verificable |
| Identidad del juez gobernado y operación registradora | Referencia verificable a actor/política/operación vigente y evidencia de evaluación independiente; autenticidad mediante mecanismo gobernado a elegir | El contrato de salida del modelo no contiene el resultado del juez gobernado ni la operación que lo registra; falta implementar/calificar ese binding |
| Currentness admitida y dependencias materiales | Proveedor CURRENTNESS_AUTHORITY admitido, cierre material, decisión vigente y vínculo a hashes/autoridad del mismo paquete; stale/unknown bloquean | Refs y currentness sintéticas no acreditan admisión |
| Scopes READY admitidos y su procedencia | scope_id exacto, decisión admitida, referencia a scope_proposals candidato, resultado evaluador y cierre de dependencias/frentes; requested scope debe pertenecer | READY_CANDIDATE y PARTIAL_READY_CANDIDATE carecen de recibo de promoción |
| Binding de versiones y decisión | Paquete/entrada/snapshot exactos y sus digests; decisión de admisión, revisión y vínculo al envelope verificado | No existe envelope ni política de compatibilidad/corte |

La admisión no concede planificación, ejecución, despliegue o escritura. Esas compuertas permanecen independientes. No se elige almacenamiento ni se implementa persistencia: D7 sigue pendiente.

## Semántica fail-closed propuesta

Código principal nuevo propuesto: A9_ADMISSION_ENVELOPE_REQUIRED. Falta de envelope o candidato estructural sin admisión devuelve BLOCK antes del ACCEPT estructural. No se trata EXPECTED_HANDOFF_INVALID_OR_MISSING como prueba completa de esta condición: puede haber handoff válido sin admisión A9.

Otros códigos propuestos, aún no existentes:
- A9_ADMISSION_ENVELOPE_INVALID: forma, versión, autenticidad o juez/operación sin autoridad verificable.
- A9_ADMISSION_BINDING_MISMATCH: digest/identidad/ejecución/pedido/target/contexto diferentes o replay a otro scope.
- A9_READY_SCOPE_NOT_ADMITTED: scope READY candidato pero ausente en la admisión, o procedencia/evaluación/dependencias incompletas.
- A9_ADMISSION_CURRENTNESS_NOT_ADMISSIBLE: admisión stale, unknown o sin proveedor admitido.

Orden a acordar: validar identidad mínima del handoff → exigir/verificar envelope y binding independiente → resolver snapshot exacto y currentness material → validar proyección/READY y cierre completo → emitir recibo. Un fallo temprano no fabrica recibo con hashes inventados; conservar la regla de no emitirlo si la identidad mínima falta. El receptor puede emitir BLOCK identificable cuando existan los bindings exactos suficientes, según el contrato acordado. Errores de transporte del lector también bloquean; no hay fallback a ACCEPT estructural.

## Versionado: propuesta V2

V1 ya exige analysis_package_digest_required, source_currentness_required, exact_target_identity_required y only_ready_scopes_admissible, por lo que exigir evidencia independiente es coherente con su intención. Sin embargo, hoy V1 no define envelope, identidad del juez gobernado y operación registradora, autenticidad ni procedencia de la promoción READY; los positivos actuales no lo aportan.

Recomendación para C1: PROGRAMMING_ENTRY_CONTRACT_V2 y contrato de envelope/versionado acordado. Es una nueva entrada obligatoria y cambia resultados observables; no conservar el digest d2e347ef… mientras se cambian sus bytes o se declara el nuevo comportamiento como ya acordado en V1. Actualizar consumidor, ensamblador A9/juez/operación registradora, validadores, pins y referencia posterior al precheck del Router requerirá una tarea futura aprobada. El Router actual sigue nombrando V1.

Alternativa solo si C1 la aprueba: mantener el archivo V1 byte a byte y gobernar la admisión como precondición de operación separada, con contrato/versión propios. Eso no significa que el receptor V1 aislado sea fail-closed respecto al envelope. Debe existir un único camino operativo que ejecute dicha compuerta; si hay bypass directo V1, la brecha continúa. Añadir campos obligatorios dentro del snapshot V1 puede ser rechazado por la validación de campos materiales desconocidos y exigiría coordinar versiones. No añadirlos silenciosamente.

El recibo de siete campos puede seguir como recibo de frontera si el envelope externo enlaza su hash completo con la admisión exacta. Si se exige acreditar esa procedencia en el propio recibo, se debe versionar también su contrato; no agregar un octavo campo a V1 ni afirmar que un ACCEPT antiguo ya demuestra admisión.

## Tests que deberán cambiar después de C1, sin modificarlos ahora

| Test/caso actual | Resultado futuro sin envelope | Nuevo control necesario |
|---|---|---|
| test_programming_pg01_receiver_v1.py: emitter_positive_boundary y emitter_accepts_identical_proposed_projection | BLOCK / A9_ADMISSION_ENVELOPE_REQUIRED | Nuevo positivo solo con envelope fixture explícito, lector, juez y operación registradora simulados etiquetados fixture |
| test_programming_pg01_router_v2_compatibility_v1.py: router_v2_structural_snapshot_positive y router_v2_gap_missing_package_not_independently_attested | Dejará de caracterizar ACCEPT estructural como salida aceptada de la nueva frontera | Router no emite envelope; debe bloquear hasta entrega admitida. El nombre de continuación no lo sustituye |
| preplanning_real_sql_boundary_accept y source_git_real_objects_integrated_ACCEPT | BLOCK sin admisión aunque hashes/readback sean exactos | Artefacto exacto no equivale a admisión; añadir fixture de envelope coherente |
| emitter_repeat_entire_result_identical y preplanning_full_repeat_deterministic | Mismo input completo → mismo recibo/resultado | Repetir también envelope/expectativas/currentness; no incluir reloj/UUID variable en recibo |
| Negativos N1–N8 y suites preplanning/technical_currentness/exact_artifact_reader | Falta envelope puede ocultar el negativo específico | Añadir envelope fixture válido a cada caso que deba alcanzar un gate posterior; preservar los ocho negativos de P1 |
| Casos nuevos de envelope | BLOCK por falta, inválido, digest alterado, juez/operación no autorizados, replay de ejecución/target/contexto/scope, currentness stale/unknown y READY no admitido | Evaluar cada causa por separado y comprobar no llamadas a planificación/modelo ni persistencia |

El test actual de Router V2 continúa siendo evidencia histórica válida de la brecha V1; no se renombra su ACCEPT a una admisión real. Positivos con envelope fixture no sustituyen el positivo acordado C1/PR2. Nada se implementa hasta acordar C1.

La procedencia de admisión será el resultado del juez gobernado más su registro por operación, ligado al snapshot as-of exacto. record_v1 ya da identidad/persistencia estructural, pero no evalúa READY ni autentica al escritor por solo recibir un actor no vacío. resolve_v1 es as-of por consumer/subject, no lookup por context_id/hash. No se escribe el juicio retrospectivamente dentro del snapshot; queda enlazado desde el envelope separado.
