# Execution binding separado del observador

26-oct-2026. Propuesta draft desde main 7e861f1fa4293e93a5a43fc352ef1250f11dd5af. Extrae sin expansión los nueve paths del motor que estaban mezclados en #3148 HEAD 89867aedd455ca0edc7679fc5e615ee56fe90c89. No incluye app/hook A6/A9 ni configuración/despliegue.

El constructor admite execution_binding_provider. Si falta, la ejecución de perfiles falla con RUNTIME_EXECUTION_BINDING_REQUIRED antes del modelo. El proveedor debe entregar contrato exacto y digest esperado independiente; los tests solo usan proveedor sintético con opt-in. No se incorpora proveedor operativo ni se simula su admisión.

## Impacto y revisión

EXECUTION_BINDING_CONSUMERS_V1.md inventaría consumidores ANTES de proponer este PR. El entrypoint/deploy actual no configura proveedor: las cuatro rutas de ejecución, queue worker y benchmark dejarían de completar inferencias de perfil. Health/readback y los tests advisory con fakes no evidencian disponibilidad de ejecución. Cristhian debe conocer y revisar este cambio compartido antes de composición; este documento es el aviso revisable, no una aprobación.

## Evidencia local

Suite completa: 232 tests ejecutados; 231 sin error y 1 error preexistente. test_explicit_source_changes_projected_method_without_affecting_default falla para systemic_root_cause_repair_lf con PROFILE_RUNTIME_MODEL_CONTEXT_BUDGET_EXCEEDED: 8648. Reproducido sobre main 7e861f1 intacto: 2 tests de test_profile_evolution_context_delivery_v1, 1 error idéntico. No se aumenta presupuesto ni se alteran los perfiles concurrentes para ocultarlo.

Sin modelos reales, DB writes, despliegue o activación. Sin cambios a workflows o scripts operativos. Los conteos son locales y el fallo basal permanece pendiente fuera de esta separación. Revisión independiente y proveedor admitido pendientes.
