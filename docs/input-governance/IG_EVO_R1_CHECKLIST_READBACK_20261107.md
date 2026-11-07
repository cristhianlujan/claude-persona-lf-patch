# IG LF — R1 | Checklist de procedencia de parámetros numéricos

**Fecha:** 2026-11-07 · **Estado:** AUDITORÍA ESTÁTICA DEL CONTRATO / RUNTIME NOT_TESTED.  
**Fuente LIVE (solo lectura):** `programacion.fn_ig_evo_r1_parameter_provenance_v1(p_pantalla_id integer)`, MD5 SQL `d60c4906b5d97b4a419dc7f8ffd99db4`; migración original `20261107024108_lf_ig_evo_r1_curator_provenance_v1.sql`. No se ejecutó R1 sobre pantalla o RUN, no se alteraron políticas y no se generó un informe nuevo.  
**Antecedente:** checklist de familias del RUN 949, documentado en PR #3693; 47 familias, piso externo de 300 celdas, pruebas de RUN sin vinculación directa, producción no aprobada.

## Entrada → proceso → salida

```text
Curator RUN → materializador existente → R1(p_pantalla_id)
  → lectura directa de políticas y sus vínculos
  → diagnóstico JSON IG_EVO_R1_PARAMETER_PROVENANCE_V1
  → envelope Curator.proposal_materialization.ig_evo_r1_diagnostics
  → archivo RAW íntegro por RUN (candidato #3694; NO ejecutado LIVE)
```

R1 no autoriza escribir, reparar valores, validar seguridad real ni aprobar semántica. Su parámetro es `pantalla_id`; el `run_id` **no va en su firma**. El enlace a RUN debe demostrarse mediante el Curator que lo invocó y archivó la respuesta, no inferirse desde la función R1 individual.

## Checklist basado en código desplegado

| Control | Resultado | Evidencia / restricción |
|---|---|---|
| Identidad de código y operación | **PASS estático** | Función STABLE, `SECURITY INVOKER`, retorno JSONB; `schema_version=IG_EVO_R1_PARAMETER_PROVENANCE_V1`, `mode=DETERMINISTIC_SOURCE_INSPECTION` |
| Alcance de orígenes | **PASS, limitado** | Fuente `lf_ops.pantallas_politicas` + `politicas_rate_limit`, `politicas_timeout`, `politicas_sesion`, `politicas_seguridad`. No es un escáner universal de las 47 familias |
| Parámetros numéricos | **PARCIAL explícito** | `jsonb_each(attrs)` y `jsonb_typeof(value)='number'`, solo **nivel superior**. Para `SECURITY`, se aplica además regex de nombres `limit|timeout|ttl|window|seconds|requests|burst|retry|intentos|threshold|concurrent|max_|count|expiracion`. Otros numéricos o anidados no se analizan |
| Procedencia por parámetro | **PASS estático** | Comprueba `parameter_provenance` con `fn_input_parameter_provenance_valid_v1`. Distingue `MISSING` e `INVALID`; no cambia el parámetro |
| Vinculación a pantalla | **PASS de referencia** | Cada finding incluye `pantalla_id`, familia, IDs/código de política, estado del binding y source locator con tabla y PK. No acredita por sí solo aplicabilidad funcional |
| Integridad del origen | **PASS de estructura** | `policy_row_sha256` y `policy_binding_sha256`. Falta recibo E2E de que la evidencia estuvo vigente en el RUN |
| Identidad del hallazgo | **PASS estático** | `stable_finding_key=IG_EVO_R1_<family>_<policy_id>`, `finding_count`, `findings[]` con orden determinado |
| Contrato y limitaciones | **PASS de separación** | `canonical_write_authorized=false`, `semantic_quality_evaluated=false`, `source_decision_validation=NOT_VERIFIED_FROM_DECISION_REGISTRY`, `numeric_policy_values_incorrect=NOT_PROVEN`, `source_readback_proof=DIRECT_POLICY_ROW_AND_BINDING_DIGEST_ONLY` |
| Riesgo rate-limit | **RIESGOS CONSERVADOS** | El finding de RATE_LIMIT reporta contadores, alcance, eventos contabilizados, atomicidad y endpoint como `NOT_DEFINED_BY_POLICY` / `NOT_VERIFIED`; no es QA runtime |
| Escenarios negativos/positivos de R1 | **NOT_TESTED** | No se ejecutó el detector en este lote ni se acreditó un caso favorable/adversarial de cada estado |
| Archivo original y transporte | **NOT_TESTED** | RUN históricos 949: 0/47 assessments con `ig_evo_r1_diagnostics` directo, 0/25 propuestas con ese campo, 0/51 eventos recientes que contengan esa clave. El PR #3694 incorpora captura futura del envelope sin reejecución; aún sin SQL LIVE |
| Perímetros de seguridad | **SIN CAMBIOS** | Solo SELECT, ningún `GRANT`, migración aplicada, endpoint alternativo, nueva familia u origen inferido |

**Regla de interpretación:** `finding_count=0` significa *ningún parámetro numérico faltante/ inválido encontrado dentro del alcance real de R1*, no prueba conformidad global ni ausencia de vulnerabilidades. Para políticas con parámetros anidados o nomenclaturas fuera de regex el estado correcto es **cobertura no acreditada**, no NOT_APPLICABLE.

## Acciones sin repetir investigación

- **No reconstruir** resultados R1 del RUN histórico 949 ni ejecutar otra vez las cuatro tablas para simular un RAW.
- Preservar SHA y contenido del resultado **si fue emitido originalmente**; si no hay archivo, marcar `NOT_CAPTURED_LEGACY_RUN`.
- Para un RUN nuevo, Curator debe transportar el **objeto completo** `ig_evo_r1_diagnostics`, no un resumen o solo `finding_count`.
- Cualquier futura ampliación a campos anidados o nuevos tipos requiere contrato de alcance, controles positivos/negativos y fuentes autorizadas; no “arreglar” silenciosamente desde la lectura.
- **Habilita revisión de R2–R6**, pero no cierre funcional R1, promoción de políticas ni entrada anticipada del Perfil.

**Controles EKB:** GOV-010, GOV-032, SEC-011 e IG-M107-A3. **Ruta:** ACT-0001 → Perfil → IG Curator/Validator → Perfil; no se modifica.
