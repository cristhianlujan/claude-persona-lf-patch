# HANDOFF — Independent Re-audit Input Governance v5.11 — Live Reconciliation

**Estado:** READY_FOR_INDEPENDENT_REAUDIT — NO ES PASS FINAL
**PR:** #179
**Agente/version:** `INPUT_GOVERNANCE_AGENT` · `version_id=19` · contrato `5.11`
**Módulo:** `B2B_AUTENTICACION`
**Fecha de reconciliación:** 2026-08-20 America/Lima / 2026-08-21 UTC

## 1. Alcance exacto

Re-auditar el estado vivo posterior a drift canónico. No asumir vigencia de evidencia histórica del PR.

Pantallas activas y runs terminales candidatos actuales:

| Pantalla | Screen | Run actual | Supersede |
|---|---:|---:|---:|
| B2B-AUTH-001 | 51 | 153 | 140 |
| B2B-AUTH-002 | 52 | 154 | 141 |
| B2B-AUTH-003 | 53 | 155 | 142 |
| B2B-AUTH-004 | 54 | 156 | 146 |
| B2B-AUTH-006 | 56 | 157 | 144 |

`B2B-AUTH-005` / screen55 permanece inactiva / `RETIRED_LEGACY_TRACE_ONLY`.

## 2. Readback de reconciliación — evidencia candidata

Al cierre de la reconciliación ejecutada por el builder:

- 5/5 runs `COMPLETED`.
- 5/5 `fn_input_readiness_run_is_current(run_id)=true`.
- 235/235 family assessments con Validator `PASS`.
- 313 assertions almacenadas/re-evaluadas por los guards.
- 0 familias `non-PASS`.
- 0 familias P0 bloqueadas.
- Module Health V3: `mechanics_pass=true`, `story_health_pass=true`, `health_pass=true`.
- `promotion_authorized=false`.
- Health SHA candidato: `bd15816b8b431d3ee05d53752756003fc5c9cb8db30e1ef3d1fb3a2531e7ec5e`.

Estos datos son **evidencia del builder** y deben ser reproducidos independientemente antes de cualquier veredicto.

## 3. Drift que invalidó la evidencia anterior

Los runs 140/141/142/146/144 seguían `COMPLETED` pero quedaron stale por fuentes canónicas cambiadas. El live delta mostró:

- `EKB_ERROR_SET` cambiado en las cinco pantallas.
- `SCREEN_CANONICAL_GRAPH` cambiado en las cinco pantallas.
- `SCREEN_RULE_SET` cambiado en las cinco pantallas.
- `CURRENT_VISUAL_ARTIFACT` adicionalmente cambiado en screen51.
- Impacto live observado antes de remediación: 42 familias afectadas en screen51 y 36 en cada una de 52/53/54/56.

No hubo refs añadidos/eliminados en ese readback; el cambio era de SHA/resolución canónica.

## 4. Hallazgo y corrección específica AUTH-001

La primera ejecución fail-closed abortó porque `VISUAL_EVIDENCE` de screen51 heredaba una assertion antigua atada a `artifact.id=7`.

El estado canónico vigente contiene tres candidatos visuales independientes para desktop/tablet/mobile. Se corrigió la recuración para validar semántica estable, no IDs históricos:

- `pantalla_id=51`
- `is_current=true`
- `status=CANDIDATO_VISUAL`
- `storage_provider=GOOGLE_DRIVE`
- `storage_metadata.canonical_canvas=true`
- variant codes:
  - `B2B-AUTH-001-DESKTOP-LIGHT`
  - `B2B-AUTH-001-TABLET-LIGHT`
  - `B2B-AUTH-001-MOBILE-LIGHT`

El auditor debe verificar que esta relajación **no** ocurrió: la assertion sigue exigiendo los tres candidatos canónicos completos; solo se eliminó dependencia de un ID histórico concreto.

## 5. Migraciones nuevas sincronizadas GitHub ↔ Supabase

- `20260821030610_input_governance_v511_auth001_visual_recuration_template.sql`
- `20260821030620_input_governance_v511_canonical_drift_successors.sql` — screen51
- `20260821030630_input_governance_v511_canonical_drift_successor_screen52.sql`
- `20260821030640_input_governance_v511_canonical_drift_successor_screen53.sql`
- `20260821030650_input_governance_v511_canonical_drift_successor_screen54.sql`
- `20260821030660_input_governance_v511_canonical_drift_successor_screen56.sql`

Los successors se separaron por pantalla porque el lote agregado superó `statement_timeout=2min`. Los guards no fueron desactivados; cada lote utilizó timeout transaccional ampliado y mantuvo la validación fail-closed.

## 6. EKB obligatoria antes de auditar

Leer como mínimo:

- `ARC-006`, `ARC-013`, `ARC-014`
- `AUD-019`, `AUD-038`, `AUD-039`
- `DB-001`, `DB-003`
- `GOV-010`, `GOV-012`
- `SRC-001`
- `TEST-006`

Y sus prevention rules aplicables, incluyendo `PRV-ARC-006`, `PRV-ARC-013`, `PRV-ARC-014`, `PRV-AUD-019`, `PRV-AUD-038`, `PRV-AUD-039`, `PRV-DB-001`, `PRV-GOV-010`, `PRV-GOV-012`, `PRV-TEST-006`.

## 7. Procedimiento obligatorio del auditor

1. Pin del PR: tomar el **HEAD exacto indicado en el cuerpo vigente del PR #179** y verificar que el checkout coincide.
2. Leer EKB directamente desde Supabase antes de ejecutar pruebas.
3. Comparar el contenido de las seis migraciones nuevas del repo contra el registro/statement de migraciones aplicado en Supabase.
4. Resolver el último run terminal de cada screen 51/52/53/54/56 sin confiar en IDs de este handoff.
5. Verificar `status`, `contract_revision`, cadena `supersedes_run_id`, invalidación del predecesor y `fn_input_readiness_run_is_current`.
6. Releer y reevaluar las 313 assertions desde fuentes actuales; exigir stored result PASS y `source_observed_sha256` coincidente.
7. Confirmar que cada una de las 235 familias tiene Validator PASS autorizado por componente/identidad independiente.
8. Reejecutar `fn_input_governance_module_health(19,'B2B_AUTENTICACION')`; comparar el payload y recalcular/confirmar SHA.
9. Verificar especialmente `VISUAL_EVIDENCE` de screen51 contra los tres candidatos canónicos actuales.
10. Confirmar ACL de `fn_input_v58_build_assertions(bigint,bigint,text)`: SECURITY DEFINER sin EXECUTE público; esperado solo `postgres` salvo cambio autorizado posterior.
11. Ejecutar controles adversariales existentes de stale source, assertion relevance, cardinalidad/duplicate identity, contract pin y terminal immutability.
12. Confirmar que `promotion_authorized=false` y que ningún resultado de health se interpreta como autorización de promoción.

## 8. Límites

El auditor **NO** debe:

- modificar código o Supabase;
- hacer merge;
- promover Golden/Human;
- activar EKB;
- autorizar producción;
- reabrir Challenge6 ni `PROG-ADR-AUTH-001`;
- usar ZIP como evidencia final.

Clean bootstrap y paridad histórica completa GitHub↔Supabase siguen siendo gates separados.

## 9. Veredicto permitido

Solo uno de estos dos resultados:

- `PASS_INDEPENDENT_REAUDIT` con evidencia reproducible; o
- `FINDINGS` con cada falla reproducible, fuente exacta, impacto y gate afectado.

No aceptar un PASS basado exclusivamente en este handoff o en la evidencia producida por el builder.