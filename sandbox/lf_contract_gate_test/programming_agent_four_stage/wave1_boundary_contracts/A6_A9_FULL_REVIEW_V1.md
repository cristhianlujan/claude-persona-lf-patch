# Revisión completa A6/A9 y regresiones del runtime · 24-oct-2026

Estado: SOURCE_ONLY_DRAFT. Revisión del implementador, no auditoría independiente.
Esta evidencia amplía A6_A9_SOURCE_PACKAGE_V1.md; no declara el motor calificado.

## Omisión encontrada y alcance corregido

Las 129 pruebas previas eran una selección, no la suite completa del servicio.
La revisión ejecutó discover de todos los tests de services/profile_runtime_api:
229 tests en el candidato anterior, con 6 failures y 1 error. Main intacto
633f120f62cf6dfaa950a18d6116fbfd61fe0c6c reproduce los mismos siete casos en 219 tests;
la diferencia de diez tests corresponde al dispatcher/API nuevos del candidato.

El séptimo caso no inventariado antes es
S26W2RepairTest.test_large_ui_literal_fails_before_model_or_health_call: su request
manual no especificaba executor_mode, por lo que el guard de identidad se
activaba antes del guard de presupuesto que la prueba pretendía ejercitar.
Se añadió REMOTE_API a esa fixture. La expectativa de rechazo por presupuesto
permanece, y NeverCalledClient sigue impidiendo health/inferencia.

El error de GenericRuntimeBindingTest.test_declared_model_context_partition_and_materialization
se corrigió declarando required_source_refs=['profiles/p/SKILL.md'] y
allow_additional_sources=false en su fixture. No se modificaron RepositoryBindings,
las validaciones de fuentes, los catálogos o el perfil de producción.

Se añadió un negativo explícito al test del adaptador: ausencia de executor_mode
produce LLAMA_EXECUTOR_MODE_INVALID y no llama a health ni chat. El caso previo
de modo GPT_NATIVE incorrecto conserva su rechazo. No se relajó llama.py.

## Resultado vigente

313 tests únicos: suite completa del servicio (230) + caller/shadow/preview,
transporte y empaquetado (83). Resultado: 308 satisfactorios, 5 failures,
0 errors, 0 skipped. unittest sigue devolviendo FAILED. El comparador contra
los cinco fallos conocidos comprueba que no aparecieron regresiones nuevas;
un exit=0 de ese comparador no es un PASS de unittest.
Regresión A9 separada: positivo payload + positivo assembler + 2 negativos
assembler + 14 negativos payload, satisfactoria localmente.

Los cinco fallos pendientes siguen en test_engine:
- test_batch_prepares_context_once_and_continues_all_profiles
- test_noncanonical_artifact_set_prepares_each_artifact_and_executes_one_profile
- test_queue_native_path_reuses_profile_source_and_schema_bindings
- test_transport_success_does_not_promote_label_only_output
- test_valid_completion_keeps_three_gates_separate

Causa: el motor usa execute_profile_runtime genérico, sin executor_mode; el
adaptador exige REMOTE_API y bloquea. No se modificaron motor/runner/adaptador
para fabricar éxito. Las llamadas se probaron con clientes fake, sin ejecutar
modelos o perfiles activos ni atribuir una caída al servicio desplegado.

## Base y revisión de la conexión

main incorporó #3150, contrato del selector semántico del Router. Se integró
preservando su migración 20261024233000_lf_profile_semantic_selector_v1.sql,
sin aplicarla ni modificar el Router en esta tarea. También se conserva #3149.
El diff de este incremento contiene únicamente tres archivos de tests y estos
dos documentos/evidencias; la migración concurrente no es cambio propio del PR.

Se releyeron dispatcher, caller, transporte, factoría, empaquetador y wrapper
contract_bound. Default-off, límite de cupos, resultado fuera del callback,
rollback/cierre y binding de identidad conservan sus límites ya documentados.
No se ensayó un driver hosted, rol o carga de producción. No existe garantía de
impacto cero ante carga/recursos: esa calificación sigue pendiente antes de activar.

## Condición para avanzar

El usuario condicionó el siguiente paso a que nada falle. Esa condición no se
cumple: los cinco fallos reales mantienen pendiente la corrección del binding
del motor. Se corrigieron las omisiones de revisión y las fixtures, pero no se
avanzó al nuevo binding ni al despliegue.

La corrección debe usar un execution_contract obtenido de una fuente gobernada,
con run_id/profile/scope/hash y modo compatibles; el wrapper existente añade el
modo y el digest del contrato antes de hashear request y valida adaptador y
atestación. Añadir REMOTE_API dentro del adaptador después del hash o inventar
un contrato en el motor no resuelve la procedencia.
La inspección Supabase fue solo RO de funciones: input_validate devuelve scope e
Input Governance, no ese envelope; no se infiere que no exista una fuente en
otro lugar. Falta resolver su entrega exacta al motor antes de implementar la
corrección. No se llamó a input_validate ni se crearon ejecuciones para probarlo.

Sin instalación, restart, activación, merge, ready-to-merge, apply o escritura
hosted. Revisión independiente, positivo A9, PG-01/P1/I0, C4/C7 y D5/D7 abiertos.
