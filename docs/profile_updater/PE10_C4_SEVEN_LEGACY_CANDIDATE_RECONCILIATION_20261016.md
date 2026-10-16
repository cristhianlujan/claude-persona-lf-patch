# PE10_C4 — conciliación de las siete ejecuciones históricas finales

**Alcance:** `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1 / PE10_C4`. Evidencia consultada en Supabase + GitHub antes de persistir. Reconciliar una ejecución histórica abierta no equivale a entregar ni descartar el candidato que produjo.

## Resultado del contraste (GitHub / Supabase)

Los siete `github_write` y `github_readback` tienen `STEP_PASS_WITH_EVIDENCE`, con SHA exacto y `sha_match=true`. Ninguno conserva `post_merge_reconcile`, `close` o `report_output`. Tampoco tienen lease activa o permiso de activación. Ninguno de esos siete SHA históricos es ancestro directo de `main`.

| Ejecución (sufijo) | Commit congelado | Código preservado / prueba de titularidad | Estado de contenido frente a `main` |
|---|---|---|---|
| `SRCR-CLOSURE-003` | `0526ff7f2f54e912fe6e26bbfbfc9e9d2739d2d1` | Rama `lf/srcr-producer-artifact-closure-20260919`; PR [#949](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/949) **OPEN**; branch HEAD `9f278f8182c72adb7a1684262bcffd548c93836a` | Diferencias materiales en `validators/runtime_semantic_utility.py`: no afirmar que el ajuste de cobertura esté en `main` |
| `OIDC-5f3f5a6c` | `10e976a20b3bbf286fb5bf826ffbaa4792aff1b5` | Rama `fix/srcr-semantic-judge-b-canonical-20260920` existente | Un detalle de `mini_judge.md` no coincide literalmente; no certificar integración |
| `OIDC-fc12ca18` | `a5ab605d15bfabd16a8453a787980c4f39a3add0` | Rama `fix/srcr-v03-incremental-value-proof-20260921` existente | `schemas/output.schema.json` de `main` contiene más reglas, pero no equivale a certificación de equivalencia completa; paso `semantic_judge` histórico fue bloqueado |
| `OIDC-4f3c28ca` | `39a7021b9453b281a01089d7b9e3f765ff6c16b5` | Rama `sandbox/srcr-v04-governed-r2-20260921`; PR [#996](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/996) **OPEN**; branch HEAD `69ce23e2afda0608a4975852266a6b94c5743b2e` | Candidato V0.4 con PR propio pendiente |
| `OIDC-2c272d7f` | `00d9970e17527647a2ae477a38a14e2c289de166` | Rama `sandbox/srcr-v04-governed-r3-20260921`; SHA existe; commit asociado a PR [#996](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/996), [#997](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/997) y [#998](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/998) **OPEN** | Contenido no certificado como incorporado en `main` |
| `OIDC-7ba517b6` | `e31bfe6c319e852e9cc083dbc611f3a5acbb4d2c` | Rama `lf/srcr-v06-mc13-governed-rebuild-20260922`, HEAD `2566bb239e362efc27e6f118f92caff66ed65bd7` | Versiones posteriores V0.7 existen, pero la inclusión del cambio exacto NO se presume |
| `OIDC-674014fd` | `67adb54827fc5871e0afec8021a3122621a666c1` | Rama `agent/srcr-v07r1-canonicalize-20261007`, HEAD `b976c719674d10137a89b6b02bc8cecaef2d8df0`; PR [#1889](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/1889) **merged** bajo otro SHA | Método V0.7R1 en `main`, pero no se falsifica merge de commit histórico |

## Disposición aprobada para C4

**Solamente la sesión histórica se cancela** mediante siete transiciones `IN_PROGRESS → CANCELLED`, cada una con eventos de evidencia individuales que preservan SHA, rama, referencia de PR cuando existe, hash del manifiesto original, número de pasos y declaración explícita de que **no** fue integrada, desplegada o validada una mejora de forma inferida.

Las ramas, commits y PR permanecen independientes y se mantienen intactos. **No se cierran los PR #949/#996/#997/#998** ni se ejecuta su contenido ni se activa el Reparador.

Después de las siete cancelaciones, el SQL de C4 vuelve a ejecutar el contrato original de lectura: `open_total=0`, `open_unclassified=0`, `open_v01_resolved=0`. Sólo si los tres son cero registra un evento de control, y transiciona `PE10_C4 → DONE` mediante `programacion.fn_engineering_checkpoint_transition_v1`. La transición se prueba íntegra en una subtransacción con rollback intencional y readback negativo antes del replay definitivo.

**Límite:** `PE10_C4 DONE` prueba que no queda una sesión v0.1 abierta. No prueba que los candidatos de sus ramas hayan sido implementados en `main`, no prueba una mejora material adicional y **no autoriza** `PE10_C5` / v0.2: el evento `PROFILE_EVOLUTION_CUTOVER_ADMITTED` sigue siendo una condición independiente.

## Reglas EKB aplicadas

`LF-PE10-C4-HISTORICAL-POSTMERGE-CURRENTNESS-REWIND-20261013-001`: prohibido ejecutar reconciliador fuente-mutable sobre un merge histórico. `LF-PE10-C4-SNAPSHOT-STEPSET-NO-RETROACTIVE-POSTMERGE-20261013-001`: no reconstruir artificialmente los pasos ausentes. `LF-PE10-C4-LEGACY-CONTRACT-CLASSIFY-IMMUTABLE-20261013-001`: no modificar manifiestos ni snapshots. `LF-PROFILE-UPDATER-LEGACY-TERMINAL-GAP-001`: tratar los recibos terminales ausentes como ausentes, no inventarlos.
