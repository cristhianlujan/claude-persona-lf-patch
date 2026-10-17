# RW1-01_C2 — Evidencia material de validación del corpus (sin E2E)

**Ámbito:** `LF_ROUTER_ARCHITECTURE_WAVE_V1 / RW1-01 / RW1-01_C2` · **Fecha de ejecución:** 2026-10-17 · **Tipo de evidencia:** GitHub Actions, proveedor CI, **NO** respuesta simulada.

## Fuentes identificadas y verificadas

| Propiedad | Lectura real |
|---|---|
| PR que integró el ejecutor | [#2879](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2879), MERGED por Train |
| Commit fuente de la prueba | `e453818c3e6098a1d958eed57d6f4131c951d651`, evento `push`, branch `main` |
| Workflow | `LF Router Level2 Advisory Tests` |
| Ejecución | [39055242275](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39055242275), `completed/success`, intento 1 |
| Job | [117461769688](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39055242275/job/117461769688), `router-level2-advisory-contract`, `success` |
| Actor fuente | `lf-migration-train[bot]` |
| Origen real | Log de job: `git fetch ... +e453818c...:refs/remotes/origin/main`, checkout a `e453818c...` |
| Verificación del corpus | Log: `CORPUS_VALID_NOT_EXECUTED`, `checkpoint_done=false`; **30 casos, 12 necesidades, 9 familias** |
| Verificación de negativos | Log: `SELF_TEST_VALIDATOR_NEGATIVES_PASS`, **15** negativos, `shape_only=true` |
| Compilación Python | Paso `python3 -m py_compile` en job satisfactorio |

## Identidad exacta de archivos fuente

Los dos archivos fueron leídos en `e453818c...` y en `main` después del merge #2882: sus identidades Git blob son iguales. El SHA-256 fue medido sobre el contenido UTF-8, y el cálculo se verificó contra el vector estándar SHA-256 de `abc`.

| Archivo | Git blob | SHA-256 de contenido |
|---|---|---|
| `docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json` | `58884d37d74f1c784dfb5920ed2ac548781bfe18` | `0592fbfec256d18014a8362d2f7ebf116793b6039da0516a00bbf85285fc5d94` |
| `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py` | `2605fc675448104f69deef8a27210fc0047ea6fb` | `e5fc3aa3f1097b8a60d5e1a7259c8242ef3aaba8e02909cab3ba752705434620` |

## Alcance de la aserción de C2

- **Sí demostrado:** el corpus es sintáctico/estructuralmente válido (30 casos/12 requisitos/9 familias) y el verificador Python rechaza 15 mutaciones negativas; runner, job, commit y archivos fuente están identificados.
- **No demostrado:** que ACT-0001 derive correctamente las 30 solicitudes, que los nueve casos contextuales se hayan ejecutado en entorno real, que un consumidor haya ejecutado efectos, o que exista revisión independiente. El propio stdout especifica `shape_only=true`.
- La aserción `negative_probes_detected_at_least=12` representa el umbral mínimo contractual superado; la medición independiente es **15**, que se registra aparte. No presentar ese mínimo como medición.
- `test_passed=true` significa solamente que el **test del verificador del corpus** pasó en GitHub Actions. `no_e2e_claim=true` y `no_authority_effect=true` impiden promover este resultado a evidencia Router-runtime.
- La evaluación independiente y la comparación de arquitecturas corresponden a `RW1-01_C3` y `RW1-02` respectivamente.

## Límite de autoridad de cierre

El resultado de CI fue leído de GitHub Actions, no generado por Supabase. El paso SQL de cierre consume referencias y observaciones ya medidas por el proveedor; **la base de datos no tiene un verificador en línea del endpoint de GitHub**. No convertir el registro de aserción en una afirmación de independencia del proveedor. La transición debe usar la función canónica de aserción estructurada y el guard de `DONE`, nunca DML directo sobre status. Cualquier cambio material en test/blob, SHA o checkpoint exige otra lectura real y bloquea el cierre si no coincide.
