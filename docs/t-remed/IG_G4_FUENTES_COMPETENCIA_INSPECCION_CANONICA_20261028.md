# LF Input Governance — G4: inspección de fuentes canónicas de competencia
**28-oct-2026** · **PR #3269 DRAFT** · `G4_EVIDENCE_DISCOVERY` · **NO RATIFICACIÓN / NO PUBLICACIÓN / NO G5**.
EKB consultado antes de actuar: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`, `CI-MIGRATION-SOURCE-PARITY-001`. Consultas en Supabase exclusivamente SELECT, sin Router.

## 1. Hallazgo principal

**LF tiene un precedente gobernado de aplicabilidad declarativa, pero no se encontró un binding de competencia aprobatoria de scope por regla.**

`private.lf_reusable_policy_registry_v1` contiene una política VIGENTE (`LF-DESIGN-TOKEN-REFERENCE-POLICY-V1`) con:
- `business_scope`, `channel_scope`, `capabilities_any`, `action_families_any`, `asset_types_any`: atributos declarativos de ámbito y acción.
- `status`, `priority`, `execution_constraints`, `source_ref`, `required`: lifecycle, condiciones y fuente.
- Fuente Git canónica: `docs/standards/LF_DESIGN_TOKEN_REFERENCE_POLICY_V1.md`. El documento exige que excepciones identifiquen **excepción, alcance, motivo, owner y vencimiento/revisión**. Esto constituye un precedente contractual, **NO** una autoridad individual de N-4.
- **No incluye columnas `rule_ref/authorized_issuer/delegation_scope/approval_receipt`.** El registro es de políticas reutilizables de uso y ejecución, no demuestra delegación de competencia para cambiar cualquier regla.

## 2. Cruce estructural y exclusiones (ejecutado)

SQL exacto en `sandbox/lf_contract_gate_test/input_governance/ig_g4_source_competence_structural_audit_20261028.sql` con CTE `MATERIALIZED` de fuentes utilizadas en varias comprobaciones:

| Indicador | Lectura viva |
|---|---:|
| Reglas en `lf_ops.reglas` | 578 |
| Activos en `public.lf_activos` | 237 |
| Registros vigentes reutilizables | 1/1 |
| Selectores N-4 ACTIVE | 14 |
| Regla.codigo = Activo.codigo_activo | **0 coincidencias de 578 reglas** |

**Inferencia permitida:** `lf_activos.owner_name` no es actualmente un JOIN canónico de competencia por `reglas.codigo`. El catálogo de activos incluye 193 owners nominales no vacíos, pero mezcla `LF_GOVERNANCE`, personas, `SUPER_ADMIN`, etiquetas transitorias y unidades técnicas; esa información describe custodios de activos, **no delegaciones firmadas sobre reglas**.

**Inferencia NO permitida:** las 578 reglas carecen necesariamente de propietarios en todos los sistemas; el cero es únicamente de equivalencia exacta de códigos, **no** prueba de ausencia de cualquier relación documental/semántica.

## 3. Diferencia de fronteras, verificable

| Fuente existente | Qué puede aportar a N-4/G4 | Qué NO puede acreditar sola |
|---|---|---|
| `lf_ops.reglas` | Texto, efecto, origen, categoría, estado, selector | Competencia de quien emite scope |
| `private.lf_reusable_policy_registry_v1` | Patrón existente de declaración dinámica por atributo/acción/capacidad | Owner competente por regla o delegación |
| `public.lf_policy_versions` | Hash, versión, vigencia y fuente de política | Aprobador facultado para una regla específica |
| `public.lf_capability_registry` | `INPUT_GOVERNANCE` owner_scope `LF_GOVERNANCE` | Gerencia funcional universal sobre Seguridad/Legal/UX |
| `public.lf_activos.owner_name` | Custodio nominal del activo | Join exacto con reglas (0 observado), delegación válida |
| `private.lf_source_documents` | 88 secciones documentales con fuente/versionado | Los metadatos observados no tienen `owner/authority_ref`; `READ_ONLY` no autoriza scope |
| `private.lf_human_decision_*` | Clasificación, políticas y recibos de decisión humana existentes | Sin rutas activas ni ámbito `RULE_APPLICABILITY_CHANGE`; no prueba fuente de competencia |
| `programacion.input_governance_cohort_*` | Cohortes y referencias propias de selección de pantallas | Titularidad de obligación/regla |
| `private.lf_evidence_ledger_v1` | SHA, fuente, currentness, receipts y authority_ref para acreditar evidencia | Competencia funcional sin otro contrato |

## 4. Alternativas a discutir, no escoger por intuición

**Alternativa 1 — Ampliar la política versionada existente:** expresar en `lf_policy_versions` una política de delegación por tipo de obligación y ámbito, con fuente de delegación verificada. Ventaja: hashes/lifecycle; riesgo: `policy_payload` por sí solo puede ser autocertificado. Requiere owner y guard de competencia independiente.

**Alternativa 2 — Extender el patrón declarativo reutilizable:** añadir semántica de `authorized_issuer/operation/delegated_scope` a la fuente vigente, sin hardcodear categorías. Ventaja: unificable con atributos N-4; riesgo: la única política observada hoy es de Design Tokens, una extensión puede contaminar su contrato. No proponer DDL hasta comprobar el owner del registro.

**Alternativa 3 — Autoridad documental externa con recibos en registro existente:** consumir decisiones firmadas por el dueño de cada obligación y verificar `authority_ref`, SHA, vigencia y delegaciones mediante las herramientas de evidencia central; el motor de scope solo valida. Ventaja: no añade otro motor; riesgo: ausencia de fuente canónica y orquestación de revocaciones.

**Condición transversal de las tres:** probar el acto de delegación para `rule_ref + operation + scope + consumer + version`, y su revocación. Los campos son un **contrato lógico propuesto**, no schema/enum nuevo. `categoria`/`origen`/similitud semántica sirven para **encontrar posibles fuentes**, nunca para autorizarlas.

## 5. Prueba mínima de falsación antes de elegir

Trazar 5 reglas con procedencias heterogéneas:
- `REG_SES_001`: negocio/sesión; identificar owner de política y alcance de onboarding vs B2B.
- `REG_ABT_004`: efectos mixtos de producto/experimento; distinguir dominios obligatorios de los meramente informativos.
- `B2B-RULE-AUTH-001`: obligación de autorización; identificar autoridad normativa no delegable.
- `B2B-RULE-DESIGN-001`: tiene selector por shell/módulo/IDs; encontrar fuente y alcance de la decisión de Design System.
- `B2B-RULE-STORY-READINESS-001`: política de readiness no equivale a ejecutar automáticamente las 47 familias.

Para cada una exigir **fuente verificable de competencia**, no solo owner nominal; documento/version/permiso/operación, evidencia del alcance, vetos, falsos positivos, falsos negativos, excepciones y consecuencias de `UNKNOWN`.

**Criterio de cierre:** un revisor independiente puede reconstruir de la fuente quién estaba autorizado **en el momento de la decisión**, sobre qué operación y alcance. Si una muestra no tiene evidencia, `NO_VERIFICADO` y no se publica selector. **No escalar todas las reglas a humanos por defecto**; primero buscar evidencia que pueda cambiar la decisión.

## 6. Resultado

- Evidencia reutilizable identificada; **ningún source owner firmado por regla fue demostrado**.
- **No hay motivo suficiente para crear nueva tabla**, enlazar todo por `owner_name` ni elegir entre las tres alternativas todavía.
- `G4_NO_VERIFICADO` y `G5_NO_RECLASSIFY` persisten. El trabajo preparatorio tiene evidencia reproducible en Git y Supabase solo lectura; sin activar políticas ni pasar a producción.
