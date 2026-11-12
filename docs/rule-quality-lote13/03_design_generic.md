# Lote 13 — Diseño genérico de calidad de reglas / PG18 sandbox

**Estado:** SANDBOX_VERIFIED (28 pruebas ejecutadas), **GLOBAL NO-GO / UNVERIFIED**. No apto para aplicar en producción.
**Autoría del lote:** GPT-6, no identidad Claude verificada ni juez independiente acreditado.
**Fuentes:** EKB «INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4» (candidato parcialmente verificado); L12: `audits/rule-quality-lote12/`, y reproducción de métricas confirmada por el dueño. El modelo aquí es PROPUESTA no implantada.

## Dato corregido de L12
- `count(*)` por nombre de categoría **exacto**: 76 categorías, **19** con una regla.
- `upper(trim(categoria))` agrupa 73 categorías, **18** con una regla.
- La diferencia se explica por `ANALYTICS` (1 regla), que se une a `analytics` (9 reglas). No hay contradicción entre ambos conteos; dependen del criterio de agregación.

## Contrato agnóstico de proyecto
| Componente de esquema `rule_quality_l13` | Contrato / control |
|---|---|
| `projects` | `project_code`, `owner_name`, `owner_profile_code`, `created_by`, `review_interval_days`; prohíbe owner `SUPER_ADMIN` |
| `actors` | Identidad/profilado solo **simulado** en sandbox; incluso `can_approve=true` no permite aprobar como `SUPER_ADMIN` |
| `families` | `(project_code,family_code)`, `scope`, owner distinto de `SUPER_ADMIN`, texto de criterios de nacimiento/fusión |
| `category_family_map` | `(project_code,category_raw)` único y FK compuesta a familia; mapeo **propuesto**, sin renombrar fuentes |
| `rules` | Regla canónica con familia, sujeto `entity_code`, `config` JSONB y estado/ciclo de vida |
| `rule_references` | Referencias por regla y proyecto; sin FK en destino para detectar códigos inexistentes |
| `family_birth_requests` / `family_change_requests` | Propuestas auditables de nacimiento o fusión, nunca fusionan/crean familias automáticamente |
| `review_decisions` | Evidencia de decisión explícita del dueño, sin registro de aprobación por `SUPER_ADMIN` |
| `lf_source_synthetic` / `saly_source_synthetic` | Fixtures, no datos oficiales: importación por adaptadores `adapter_lf` / `adapter_saly` |
| `sandbox_test_results` | Evidencia de pruebas del runner PostgreSQL, no autoridad operacional |

### Separación entre fuente, modelo y decisión
```text
LF fuente  ── adapter_lf ──┐
                          ├─> rules + category_family_map
SALY fuente ─ adapter_saly ┘          │
                                     ├─> list_review_due() ─── PROPONER_REVISION
                                     ├─> find_noncurrent_references() ──┐
                                     └─> find_parameter_differences() ─┤
                                                                       ▼
                                                     REQUIERE_REVISION_SEMANTICA
                                                                       │
                                   Perfil dueño validado ──> decisión documentada
                                                                       │
                                 decide_rule_review() → review_decisions [sandbox]
```

## Familia: nacimiento y fusión
- **Proponer nacimiento:** `propose_family_birth` exige owner del proyecto, distinción de alcance (`scope_difference`), impacto de propietarios/consumidores (`owner_impact`), `source_ref`, `decision_ref`. No agrega una familia real ni reasigna reglas: crea `family_birth_requests` con estado `PROPOSED`.
- **Proponer fusión:** `propose_family_merge` exige `semantic_equivalence`, `impact_review`, `source_ref`, `decision_ref` y actor dueño. Solo crea una propuesta `PROPOSED`; la normalización debe mantenerse reversible y no aplicarse por similitud de idioma, nombre o parámetro.
- **Regla canónica:** cada regla queda asignada a exactamente una familia por proyecto mediante una FK combinada. En este candidato no existe fusión automática ni actualización física de `lf_ops` o `saly`.
- **LF:** 76 categorías actuales, mapeadas a **15 familias propuestas** mediante el CSV completo de L12; todas las categorías presentes y sin duplicar la clave. **SALY:** 3 familias propias (CALENDARIO, GOBERNANZA, MOTOR_DISPONIBLE), sin forzar taxonomía LF.

## Ciclo de vida (manual, no temporalmente automático)
| Evento | Comportamiento de este candidato |
|---|---|
| Nacimiento | `created_at` más estado inicial `CANDIDATO` y `effective_from` cuando aplique |
| Validación vigente | `VIGENTE`, `reviewed_at`, `next_review_at`; período parametrizado por proyecto |
| Revision vencida | `list_review_due(project,as_of)` es `STABLE` y **solo SELECT**; propone, no cambia estado |
| En revisión | `EN_REVISION`, requiere decisión del dueño, no caduca por reloj |
| Caducidad aprobada | `decide_rule_review(...,'EXPIRE',...)` registra `CADUCADA` y `effective_to` en sandbox |
| Sustitución aprobada | `SUPERSEDE` exige sucesora explícita existente y `VIGENTE`; estado `SUCEDIDA` |
| Retención de evidencia | `review_decisions` conserva actor, motivo, fuente y fecha de decisión |

Los intervalos LF 90 días y SALY 60 días **solo son supuestos sintéticos de test**, no decisiones oficiales para esos productos.

## Detectores genéricos: misma implementación LF y SALY
1. `find_noncurrent_references(project)`: fuente VIGENTE hacia destino inexistente o distinto de VIGENTE. Emite `REQUIERE_REVISION_SEMANTICA`; se inyectaron 3 casos LF en fixtures para replicar el patrón observado.
2. `find_parameter_differences(project)`: dos reglas VIGENTE de **misma entidad**, mismo nombre de clave y valores JSON distintos; emite `REQUIERE_REVISION_SEMANTICA`. Una diferencia en `ventana_minutos` o `max_operations` puede ser legítima: **nunca se clasifica como contradicción probada**.
3. Ambas funciones son SQL `STABLE` y sus definiciones son las mismas para `lf` y `saly`, sin condicionales por producto. El adaptador se ocupa de traducir `descripcion/estado` (LF) frente a `regla/vigente` (SALY). Las diferencias SALY usadas en pruebas fueron **inyectadas**, no halladas en datos reales.

## Evidencia PG18 / límites
- Ejecución 100% aislada en contenedor GitHub Actions `postgres:18`, DB vacía `rule_quality_sbx`, sin contraseña Supabase, sin producción, sin merge ni migraciones.
- **28 casos positivos/negativos**: rechazó SUPER_ADMIN como owner de proyecto/familia y como aprobador; rechazó fusión/nacimiento sin evidencia; revisión vencida produjo una propuesta sin cambiar la fila; sucesión sin sucesora rechazó; sucesión/caducidad con dueño funcionó; los dos detectores funcionaron sobre SALY sin cambios de implementación.
- Ejecuciones iniciales: primera falló por `UNION ALL` sin cast de timestamp; defecto corregido y reprobado. Evidencia final vigente en `02_pg18_real_results_final.json` y log del CI.
- Gate ajeno: migración de promoción y fixtures del Lote 11 tienen Git blob idéntico a L12; comparación MD5 en `04_gate_readback.json`.

## Bloqueos explícitos de adopción
**GLOBAL NO-GO / UNVERIFIED.** Las funciones de decisión aceptan `actor_code` como argumento de una prueba sintética; **no autentican por sí mismas al usuario**. Para producción sería obligatorio vincularlo al contexto confiable del servidor, restringir DML directo mediante grants/RLS/funciones con autorización, validar la herencia real de reglas, obtener dictamen semántico por familia, fijar políticas de revisión por producto, plan de adopción/rollback y operación gobernada distinta. Este lote no ejecutó esas actividades ni solicita incorporarse al gate.
