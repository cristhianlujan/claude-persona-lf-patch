# Anexo abierto al plan LF — binding de hechos al runtime (decisión del dueño 2026-11-21)

**Estado:** propuesta de arquitectura **NO IMPLEMENTADA**. **Tablero sin variación por estas casillas (69/100 antes del lote F4)**. No promueve ni cambia ningún juicio. Se conserva el plan base de Library y los deltas F0/S/AM.

**Decisión:** Paulo proporciona fuentes ejecutables (tabla/columna, función/RPC o endpoint). El **núcleo** registra el binding gobernado del hecho y su lector autorizado lo resuelve. Ningún hecho lógico se da por operativo solo por existir en `nucleo_hechos`. Las reglas `REG_CHK_004`, `REG_CHK_005`, `REG_CHK_008`, `REG_CHK_013`, `REG_TEC_009` y `REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001` permanecen `CANDIDATA/DEVUELTA`, sin `BLOQUEADA` fabricada ni publicación.

## Propuesta de registro (sin DDL en este lote)

Una tabla de contratos de fuente en **cada instancia** del motor (idea: `lf_ops.nucleo_hecho_bindings` y `saly.nucleo_hecho_bindings`, con misma definición y datos separados). No duplicar el hecho ni su tipo; FK a `nucleo_hechos.codigo` y tipos derivados del catálogo existente.

| Campo propuesto | Función |
|---|---|
| `hecho`, `version_binding`, `instancia` | Identidad, historial inmutable y aislamiento de producto |
| `source_kind`, `source_ref` | `TABLE_COLUMN`, `RPC`, `HTTP_ENDPOINT` o `CONFIG`; ruta exacta, no una descripción |
| `input_schema`, `output_path`, `subject_keys` | Contrato de parámetros, campo normalizado de salida y correlación usuario/operación/deuda/empresa |
| `auth_policy_ref`, `freshness_policy_ref` | Referencias a políticas existentes; sin copiar claves ni introducir umbrales |
| `source_commit_sha`, `deployment_ref`, `evidence_ref` | Código, despliegue y pruebas enlazados por versión/hash |
| `estado`, `registered_by`, `verified_by`, `verified_at` | `PROPUESTO` / `VERIFICADO` / `RETIRADO`, separación de productor y verificador |

**Quién registra:** Paulo **entrega** fuentes y prueba. Programación/verificador **inspecciona** firmas, RLS, despliegue, correlación y caso negativo. El escritor **gobernado del núcleo** registra mediante migración y Merge Train; no usar el conector solo lectura como escritor. Las decisiones funcionales o de proveedor se elevan al dueño, sin atribuirlas al desarrollador.

**Contrato de entrega por hecho (Paulo):** `{producto, hecho, source_kind, source_ref, commit_sha, deployment_ref, input_schema, output_path, subject_keys, auth_policy_ref, evidence_positive, evidence_negative, readback_sql_or_endpoint, verified_runtime_version}`. No colocar credenciales, DNI ni PII en el paquete; las rutas externas son referencias de interfaz, no endpoints inventados.

**Pruebas de aceptación futuras:** fuente positiva devuelve tipo y unidad correctos y misma operación; falta de binding, tipo inválido, versión de código obsoleta, dato no fresco, sujeto ajeno o error de proveedor **fallan cerrado** con razón identificable. PG17 positivo/negativo y ROLLBACK más integración real contra endpoint desplegado (incluido duplicado/tardío), 17/17 regresiones y readback. Ningún valor se asume ni se transforma `DEVUELTA` en `BLOQUEADA` sin crear y verificar el contrato de bloqueo runtime.

## Casillas ABIERTAS del plan — ninguna suma avance ahora

- [ ] **Binding por hecho:** aprobar e implementar catálogo/versiones/autoridades por instancia con referencias verificadas de Paulo (NO IMPLEMENTADO).
- [ ] **Lectura de hechos:** resolver seguro, autenticado, trazable y fail-closed a partir de un binding `VERIFICADO` (NO IMPLEMENTADO).
- [ ] **Pruebas y gobernanza:** adapter desplegado, positivo/negativo, correlación, rechazo de stale y comparación de output con contrato, sin auto-publicación (NO IMPLEMENTADO).

**F6, F2b, AM y seis candidatas:** sin cambios por este anexo. Los 150 enlaces semánticos ambiguos de F0 continúan fuera de alcance.
