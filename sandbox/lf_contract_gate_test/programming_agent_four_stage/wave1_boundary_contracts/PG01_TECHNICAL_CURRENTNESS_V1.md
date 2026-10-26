# PG-01: currentness de materiales técnicos

Fecha: 2026-10-23. Estado: SOURCE_ONLY_TECHNICAL_CURRENTNESS_BOUND.
Base revisada: 9a1f21e820de479542c564305c54eb761f945ec3.
Sin push, apply, persistencia operativa, merge o activación. Revisión del implementador, no independiente.

## Revisión y corrección

El adaptador CanonicalCurrentnessPort agregaba un rechazo por invariante del snapshot modificando el resultado canónico y conservando su receipt_sha256.
Ese hash ya no describía el contenido modificado. Se corrigió la separación:
- authority_receipt conserva exactamente el resultado y hash emitidos por CURRENTNESS_AUTHORITY;
- PG01_CURRENTNESS_CONTRACT_CHECK_V1 contiene el motivo y ready=false del consumidor;
- la envoltura del consumidor no se hace pasar por un recibo canónico nuevo.

Las pruebas verifican el hash del recibo canónico tanto en aceptación como en rechazo adicional.
No se modificó el evaluador canónico ni su política de compatibilidad.

## Siguiente paso implementado

TechnicalCurrentnessPort deriva el conjunto de materiales requeridos y delega en CanonicalCurrentnessPort/evaluate_authority existentes.
El proveedor debe resolver evidencia actual observada desde fuentes confiables. Un dict que declare CURRENT no constituye autoridad.
El proveedor real, sus fuentes y admisión no se implementan ni se califican mediante este fixture.

Se ligan catorce materiales técnicos adicionales a las cuatro raíces del snapshot:
- identidad de contexto, scope, cierre de dependencias y target;
- marco completo, incluido modo y presupuesto del pedido;
- mapeo de suficiencia y reporte C7;
- digest de bytes e identidad repo/commit/path/versión de cada uno de los cinco artefactos fijados.

El binding debe incluir todas esas raíces DIGEST, los fingerprints esperados, contexto/scope exactos y el contrato de la ejecución.
No se permiten reemplazos de las raíces del snapshot mediante additional_materials.
Identidades, digest agregado del conjunto técnico y target se cotejan antes de evaluar.

Un cambio de material técnico fijado requiere revalidación del marco; ni una compatibilidad declarada cambia silenciosamente el pin.
Una revisión Git diferente, con todos los materiales invariantes y ancestro válido, puede producir CURRENT_REBOUND.
La decisión, cierre afectado y validaciones acotadas los calcula el evaluador canónico.
Un bounded_validation_required=true sigue bloqueando.

## Integración con el receptor

SourcePreplanningReceiver exige el puerto técnico cuando C4 y C7 están completos estructuralmente.
Si falta o falla, devuelve BLOCK / TECHNICAL_CURRENTNESS_NOT_ADMISSIBLE.
Si la estructura ya está incompleta, no invoca el proveedor de vigencia.
Un resultado ready=true requiere schema, authority_layer, identidad de contrato/implementación y receipt_sha256 consistentes.
Una declaración CURRENT sin ese recibo o un recibo alterado se rechazan.

technical_currentness se conserva en la proyección completa y su hash.
No se amplían los siete campos de PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1.
Snapshot A9, contexto y contrato de entrada quedan intactos.
El recibo del evaluador dentro de la proyección es evidencia del consumidor; no es otra persistencia ni otro lifecycle.

## Validación local ejecutada

| Nivel | Resultado | Límite |
|---|---|---|
| Unitarias | 60 tests únicos satisfactorios | Evaluador real, materiales/proveedor sintéticos |
| Postgres desechable | 106 comprobaciones coincidentes | SQL candidato real; catálogo y puertos sintéticos |
| Históricos | No reejecutados | Evidencia anterior conservada por separado |
| CI del incremento | Pendiente | No hubo publicación |

Incluye CURRENT, CURRENT_REBOUND por revisión no material, STALE_AFFECTED, UNKNOWN_FAIL_CLOSED, raíces incompletas, duplicados, digest bound distinto, identidad/scope/target ajenos, validación acotada pendiente, proveedor ausente y recibo alterado.
El conjunto de tests no contiene duplicados por importación.
pg01_technical_currentness_local_20261023.json vincula los resultados a hashes de las fuentes probadas.

## Estado real

C4 y C7 siguen como candidatos integrados localmente. El enlace al evaluador canónico ya existe como fuente.
Siguen pendientes la admisión/procedencia del proveedor, fuentes técnicas reales, presupuesto fijado, mapeo A9 y readback semántico.
La fixture hidrata DIGESTs sintéticos a partir de los valores esperados: prueba el enlace y sus negativos; no acredita observación independiente de fuentes reales.
Los resultados positivos mantienen planning_allowed=false, execution_allowed=false y operational_admission=false.
C4/C7, persistencia C6 y la calificación del binding técnico permanecen en pending_gates.

Siguientes pasos: fuentes/puerto operativo admitidos y mapeo A9; publicar con la cuenta de Paulo y validar CI del HEAD nuevo; resolver D7/PR2 para I0.
El presupuesto POR_DEFINIR no se convirtió en un monto aprobado.
P1, I0 y PG-01 siguen abiertos. La autenticación del servidor no se cambió.
