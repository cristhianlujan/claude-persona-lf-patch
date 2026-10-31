# WEB-001 — Continuidad de ejecución y juez independiente

**Estado:** handoff ejecutable, no certificación Group2. **Ejecución del actualizador existente:** `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-a4b04585-e518-482c-ab02-855a807ee0ae`. Mantener PR #3399 DRAFT. No crear ejecución de actualización adicional.

## Fuentes y anclajes

| Elemento | Valor |
|---|---|
| Repo | `cristhianlujan/claude-persona-lf-patch` |
| Operación de ejecución nativa | `EJECUCION_PERFIL_LF` |
| Caso único | `skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/WEB-001.case.json` |
| Entrada literal idéntica | `docs/profile_updater/handoffs/WEB001_EXACT_PAIR_EXECUTION_INPUT_20261030.json` → `literal_case_input` |
| Perfil base | commit `52c0f68ad243d2a98f959db8f3a935179b5681aa`, treeSHA256 `2f4ac419ee3a49b2366a684daf4df2613a28426e77f0a880851fe07841105381` |
| Perfil evolucionado | commit fijado `f3a922ab54d951da506220703429e2c079843096`, treeSHA256 `6ac9063859b13e65c5cdf15b22969b097b859d8053b2af6e4747731bb28b10ac` |
| Comprobación árbol candidato | [GitHub Actions #41160540021](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41160540021), 15/15, fuente exacta |
| Fuentes N1–N5 | `WEB001_N3_N5_LIVE_SOURCE_CASCADE_20261030.json`, `WEB001_N1_N5_SOURCE_EVIDENCE_MANIFEST_20261030.json` |
| Manifiesto canónico | `WEB001_CANONICAL_EXTERNAL_EVIDENCE_MANIFEST_20261030.json` |
| RAW candidato de referencia | `WEB001_GPT_NATIVE_CANDIDATE_RAW_DRAFT_20261030.json`, autoría de chat / **no** cold run ni atestado |
| Validación Python canónica | [#41160169385](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41160169385), pack PASS, runtime PASS, errores 0 |

## Flujo de trabajo obligatorio

1. **Recuperar el contrato de EJECUCION_PERFIL_LF y la misma entrada literal.** Cargar el perfil base del SHA fijado, no suponer que el candidato es línea base.
2. **Correr realmente el perfil BASE** en modo nativo sobre WEB-001, conservar JSON RAW íntegro, recibo de procedencia y validación conforme a su propio esquema y validator.
3. **Correr el perfil CANDIDATO** con la misma entrada y constraints, desde su árbol fijado. Conservar JSON RAW íntegro nuevo, no reetiquetar el borrador actual como corrida fría.
4. **Validar ambas corridas:** output íntegro, `validator.valid` real, digest canónico SHA-256 del JSON, `profile_tree_sha256` exacto. Incluir errores literales y negativos; no convertir los 13/14 self-check del borrador en pase.
5. **Registrar corridas `PROFILE_OPERATIONAL_RUN_V1`** únicamente por el transporte gobernado y dentro del trusted root. `attestation` explícita `NONE` o `RUNTIME_ATTESTED` según recibo genuino. Prohibido inventar origen o alterar comparator.
6. **Juez semántico independiente:** debe releer N1/N2 y las fuentes de política, resolver si hay *regla realmente aplicable* a owner ACT-0058, valorar límites del alcance, verificar discrepancia retry `>3` vs SQL `>=3`, evaluar productor/consumidor y los dos bordes `E-FETCH-CLOSE` / `E-CLOSE-READMIT`.
7. **Comparador oficial:** correr `mode=compare` sobre ambos commits y trusted main con ambos runs genuinos. Exigir `EVOLUTION_DEMONSTRATED`, al menos un OP mejorado, cero regresiones y sin `cases_unmeasured` materiales.
8. **Solo tras PASS:** enviar `evolution_proof_run_id` del GitHub Action oficial al paso 90 `deterministic_validation` del **mismo** execution ID; continuar 100, 110, Train, readback y cierre según snapshot vigente.

## Hechos negativos ya comprobados

- La corrida de Python #41160169385 **sí** certificó que el borrador candidato y manifiesto pasan su suelo estructural.
- El paso 90 fue rechazado en el [despacho #3405](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3405), con `PROOF_RUN_ID_INVALID` desde el servidor `v22-profile-update-server-trust-context`: exige **run de comparación oficial**, no Python arbitrary job. Sin registro del paso 90.
- El RAW histórico del 29/10 no corresponde a los árboles actuales. No usarlo como nueva corrida.
- El owner de ACT-0058 sigue `UNRESOLVED`, sin política de asignación aplicable verificada. No confundir SUPER_ADMIN de otras operaciones con owner de este activo.
- El reingreso de filas FALLIDO en un ejecutor externo sigue **no verificado**. Cero coincidencias en `cron.job` bajo filtros consultados **no** prueba su ausencia.
- `PASE` del PR es el único punto de entrada PR, y el workflow temporal de diagnóstico fue eliminado. No crear otro router ni modificar el guard para conseguir un verde artificial.

## Criterios de cierre

El estado `NEEDS_MORE_EVIDENCE` es salida correcta si las fuentes aún no permiten reparar la operación. La **evolución del perfil** puede mejorar su metodología de búsqueda y fail-closed sin resolver arbitrariamente un owner. El juez debe decidir mejora real y no limitarse a que el schema valide.

**Actualmente:** diagnóstico y validación determinista logrados; comparación operacional y revisión semántica independientes PENDIENTES; PR sin merge ni producción.
