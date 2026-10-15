# PASE-X16 — resultados del shadow local sobre main actual

Estado de X16: BACKLOG. No se activaron checks ni se cambiaron rulesets.

## Tercera vuelta — Claude, 15/10/2026

Planner evaluado: `emit_ci_execution_plan_v2`, sin cambios, sobre `main` `df3f283` (merge de #2766). Resultados comunicados por Claude desde evaluación local; no se crearon PRs canario ni se aplicaron migraciones.

| Canario / ruta evaluada | Decisión y controles | Lectura |
|---|---|---|
| `docs/pase/x16/ACTIVATION_PLAN.md` | `NOT_APPLICABLE`; `required_controls=[]` | Pasa sin bloquear. |
| `supabase/migrations/…_lf_x16_shadow_canary_v1.sql` | `APPLY`, `SPECIALIZED_REQUIRED`; `DB_CANDIDATE_APPLY_ROLLBACK`, `LF_CONTRACT_CORE`, `MIGRATION_SOURCE_PARITY`, todos observe-only | La ruta migratoria queda clasificada y los controles requeridos no activan nada. |
| `supabase/functions/get-perfil-lf-runtime-protocol-public-test/deno.json` | `NOT_APPLICABLE`; sin controles | Pasa sin bloquear. El carrier `SUPABASE_FUNCTION` no exige control para esta ruta; el owner debe decidir si ese archivo de prueba amerita uno. |
| `sandbox/lf_contract_gate_test/train_receipt_verifier/test_verify_train_receipt.py` | `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:CLASSIFICATION_REQUIRED` | Falso bloqueo: el test válido del verificador de recibos no tiene familia de changeset. |
| Base tres commits anterior a #2766 | `FAIL_REPAIR_POLICY_UNIVERSE_DIGEST` | Bloqueo correcto: la política de cuarentena de esa base no coincide con el universo de controles que introdujo #2413. |

La migración del canario se evaluó como diff local; no se etiquetó, no se aplicó y no se creó rama canario persistente. El código `train_receipt_verifier/` sigue siendo el falso bloqueo reproducido que requiere decisión de CHANGESET_GOVERNANCE.

## Lectura del runtime

`classify(["supabase/functions/get-perfil-lf-runtime-protocol-public-test/deno.json"])` devuelve `DEEP_SHARED_KNOWN`, familia `SUPABASE_FUNCTION`, `required_controls=[]`. El caso es un manifiesto Deno bajo el endpoint de prueba pública; el resultado confirma que hoy no se pide control. La decisión pendiente es si basta esa clasificación para config de prueba o si el owner quiere un control de runtime para cambios de comportamiento en esa función.

## Historial de la vuelta anterior

Los resultados de #2763 previos a #2766 quedaron superados. En aquella revisión la cuarentena todavía tenía el digest de 25 controles y fallaba globalmente; tras #2766 el planner ya evalúa el universo de 26. No usar esos bloqueos globales como resultado de esta vuelta.

## Conclusión

El shadow sobre main actual separa los casos: docs y runtime de prueba no bloquean; una migración cae en la vía especializada; el canario stale se bloquea correctamente; el código del verificador de recibos aún cae en `CLASSIFICATION_REQUIRED`. X16 permanece en BACKLOG y no se solicita activación.