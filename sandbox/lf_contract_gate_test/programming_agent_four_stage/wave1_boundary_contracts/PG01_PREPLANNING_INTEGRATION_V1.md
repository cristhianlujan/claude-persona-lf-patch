# PG-01: integración local de C4/C7 y proyección

Fecha: 2026-10-23. Estado: SOURCE_ONLY_INTEGRATED_CANDIDATE.
Base: 2e87f154266d425600a80e0535a2c2e539cbeeff.
Sin push, apply, merge, persistencia operativa ni activación.

## Cambio

SourcePreplanningReceiver compone ReadOnlyReceiver y los dos validadores puros.
Conserva la base SQL, el contexto exacto y el snapshot A9 completo.
No crea un runtime, Router o almacén. No cambia el contrato de entrada ni su digest.
El resultado sigue sin permiso para planificar o ejecutar.

El puerto de evidencia se configura al construir el consumidor. Recibe expected, scope_id y cierre de scopes.
Su paquete candidato PG01_PREPLANNING_EVIDENCE_CANDIDATE_V1 contiene:
- context_id y context_sha256;
- scope_ids del cierre READY ya validado;
- snapshot_sha256, hash canónico del snapshot exacto;
- target exacto, incluido repo y base_head_sha;
- technical_framework y binding_map;
- schema_version.

Se rechazan campos desconocidos, NaN, evidencia de otro contexto/scope/hash/target y proveedores indisponibles.
Un rechazo previo de la frontera no invoca ese puerto.
Los artefactos se leen por los pins del marco; la procedencia y currentness operativos de esos pins siguen pendientes.

## Proyección y recibo

La proyección retiene:
- scope_id y snapshot completos;
- preplanning_binding, identidad del paquete sin duplicar marco/mapeo;
- technical_framework y sufficiency_binding_map, sin completar datos faltantes;
- technical_framework_validation y sufficiency_report, calculados por los validadores.

El hash se calcula con canonical_sha256 existente sobre la proyección completa.
El recibo conserva schema_version y los siete campos originales.
Los paths adicionales corresponden a las comprobaciones materiales de la proyección.
El recibo del wrapper reemplaza al recibo de la frontera para este resultado; no se persisten dos recibos.
Un cambio en el marco, presupuesto medido o mapeo cambia el digest.
Una propuesta que omita o modifique cualquier material se rechaza conservando el hash de la proyección completa retenida.

C4 o C7 incompletos producen BLOCK. MISSING conserva el retorno a la autoridad técnica del proyecto o a Análisis.
Un presupuesto agotado produce BLOCK con PREPLANNING_REQUIRES_DECISION.
Un conflicto de suficiencia produce BLOCK con PREPLANNING_CONTRADICTION.
Si todavía no hay datos técnicos válidamente ligados, el rechazo conserva el contexto y la proyección de frontera auténticos.
Un fallo temprano del contexto sigue usando receipt=null.

## Límite de ACCEPT

ACCEPT significa SOURCE_ONLY_PREPLANNING_STRUCTURE.
planning_allowed, execution_allowed y operational_admission permanecen false.
Se conservan C4, C7 y persistencia C6 en pending_gates.
Además quedan visibles la admisión de fuentes técnicas, acuerdo del mapeo A9, readback canónico y currentness de los materiales técnicos.
No equivale a P1, I0, PG01_CONSUMED_AND_RECONCILED ni autorización del Worker.

La integración es un componente fuente instanciado en pruebas; no es una ruta operativa desplegada.
No hay un productor real de evidencia técnica admitido ni persistencia del recibo.

## Verificación

- 41 tests unitarios locales: 27 previos y 14 del wrapper.
- 101 comprobaciones en Postgres desechable: frontera SQL real, evaluador canónico de currentness y puertos técnicos sintéticos.
- Ejemplo integrado ACCEPT con C4/C7 estructuralmente completos.
- BLOCK por falta de marco, falta de mapeo/material, identidad incompatible, puerto fallido y proyección con pérdida.
- Siete campos preservados, snapshot inalterado, hash recomputado y repetición idéntica.
- Cero escrituras en Supabase. Ningún histórico reejecutado en esta corrida.
- No hay CI del incremento local; #3135 sigue publicado en 80db71a7e240da70445fecc875e3f0615f53f17f, draft.

pg01_preplanning_integration_local_20261023.json vincula los resultados a los digests de las fuentes.
Los fixtures usan normalización candidata; no se promueven a autoridad o prueba de aprobación legal.

## Pendientes

1. Publicar los commits locales con la cuenta de Paulo y ejecutar CI en ese HEAD.
2. Acordar con A9 el mapeo de las cinco dimensiones de suficiencia.
3. Proveer manifiesto técnico, arquitectura aplicable, control y política/presupuesto fijados por pedido con admisión y readback.
4. Extender el binding de CURRENTNESS_AUTHORITY a los pins técnicos; no crear otro evaluador.
5. Resolver D7 y obtener un positivo real PR2 para persistir/releer en I0.
6. Revisión independiente. P1 e I0 siguen abiertos.
