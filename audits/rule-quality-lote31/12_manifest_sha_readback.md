# L31 — MANIFIESTO de integridad B02 + B03, no-go

**Base de la rama nueva:** `5e2c418c1ad5c43a4fc5b71ecc44e4382d5e06d3`, de L28. La rama oficial L28 recibió un commit concurrente de B07 y otras fuentes después de este fork. La última versión de `12_criterios_cierre_motor_7.md` tiene blob `130d474921e0ad010e94a645a8f350f3ca86e611`, sin cambios en el texto literal de B02/G01 o B03/G02; fueron releídos. No rebase ni mutación de L28.

**Trabajo realizado:** Supabase live `mhwmirqcgxxukpctffuv` solo SELECT; PG18 copia efímera; GitHub read-only del objeto asociado a cada `github_write` y escritura de esta evidencia en rama de laboratorio. **Ningún RUN creado, alterado, reintentado o cerrado**. Ningún DML/DDL en Supabase ni invocación de escritor/función de efecto.

## SHA de la evidencia live y CI

- B02 R01 canónico (as_of `2026-11-13T07:32:11.933662+00:00`, 234 RUN): SHA-256 `d14568937e82995b0c141cd8be75bc7091fb0076164933209e0c616b1d564acc`.
- B03 por mismos 234 IDs (as_of `2026-11-13 07:32:15.742705+00`, SHA-256 JSONB): `ec233aa608d66167f9a0206cac3f4db9d0e40167fbf6daf15437b06e8ea3b60f`.
- CI PostgreSQL 18.7 [#43386747597](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43386747597), job `131756962233`: **16/16 PASS**. SHA-256 del JSON RAW de runner `1ccce4c1bd2abf9fc4f8667c4b5898ec9e02af08e169980adc9fc355fb1772cb`.
- Artifact de CI `14019400418`, ZIP SHA-256 `98e9ac8d37432c3d827f5eea33bac136e9a39a378e2a2b973dd981379a5f8a40`, retención 30 días.
- **Precisión del test de integridad:** PG17.6 y PG18.7 pueden serializar objetos JSONB de forma distinta. Se verifica el texto JSONB canónico real de Supabase byte a byte en PG18, con ese mismo SHA, y la igualdad estructural/IDs de la copia; la huella de la reserialización PG18 **NO es exigida idéntica**. Las primeras dos CI fallaron al exigir erróneamente esa equivalencia; la tercera corrigió la hipótesis sin falsear hash.

## Hash SHA-256 del contenido Git UTF-8 y blob SHA1

| Archivo relativo al repositorio | SHA-256 UTF-8 | Git blob SHA-1 |
|---|---|---|
| `audits/rule-quality-lote31/01_b02_r01_live_cohorte_jsonb.json` | `2c3f3d0bee20ef650ae0dd0118a298fec9c40f87863ca70bab4d620469ce28d7` | `7b5fe371661c75cb42c23b8620f5d14f89cb84e3` |
| `audits/rule-quality-lote31/02_b02_cohorte_ids.csv` | `6f86c663c43aa6ee488b7595f176abc20e00590c9d516062c63b5bf7cce58291` | `f3076bc1d79e4f4d5eb590823ab9f580907c9e61` |
| `audits/rule-quality-lote31/03_b03_run_effects_live.json` | `4eb24937ef375239d4ba22d48acd2114b61743c919d2a6c64cb2057eacb60415` | `9688561a27b0f384807723b309f4aa30d925444d` |
| `audits/rule-quality-lote31/04_b03_per_run_readback_234.csv` | `f9eed878073768f712e6e5cce2285dd566755c777a5b6d41c362b43c896c2896` | `550adfdf4ed3ca3dd72c0e56455403846dad7a7f` |
| `audits/rule-quality-lote31/06_b02_canonical_live_jsonb_text.json` | `342a47689129de51b127822262917b8aaa144cad87ab2fd00c9d7b5e90881f2e` | `34f8b6ff1223a94940ea9c520c5fc941fd9ea383` |
| `audits/rule-quality-lote31/07_b03_canonical_live_jsonb_text.json` | `cd3cab5856a6e1e50d5a988ca5075f88b41bf35a418f295cf4f6e2ed2164a308` | `0c121bb6f790fc43577635044007bd6799565700` |
| `audits/rule-quality-lote31/10_b03_github_object_existence_summary.json` | `2a134be7a3c0142e3a4f87d322bdfe76fe3de2fcec6a0e13390c97302d6f4af1` | `decc029fb241130f79709e43e80d1e2674009164` |
| `audits/rule-quality-lote31/11_informe_ejecutado_b02_b03.md` | `eb42be354972f3c091e059cba80c1d8a4374b75074c33926e735018a9e2b4404` | `9fa3576b6c230ef1969daa94a17730c1caedbe17` |
| `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_l31_b02_b03_snapshot.py` | `6d76e5b566d71e1d4d050f4ba6c01ec43ba3e911f14fc324ce70857b18a7d1c1` | `9e0f608dcedb64b2fe0754eae3c9769765214d3b` |
| `.github/workflows/l31-b02-b03-run-forensics-pg18.yml` | `5084461ac718853561e7990bdedbc5ee72142bfce391c2ae7738fbd898a8d513` | `6773677aee39d866793f5d23a48882cb1c0bd4e5` |

El SHA-256 de archivos se calculó sobre texto UTF-8 leído de GitHub, verificado el algoritmo contra `SHA256('abc')`. No confundir con los SHA JSONB internos del servidor ni el ZIP de CI. Los archivos `09_b03_github_check_batch_00..03.json` están incluidos en el diff de rama y alimentan el resumen 29/29.

## Gate y responsables pendientes

| Criterio | Evidencia L31 | Falta para cerrar / responsable | Dictamen |
|---|---|---|---|
| B02 / G01 | SELECT R01, 234 IDs, 232 históricas presentes, 32/32 propuestos, SHA, negativos PG18 | Lista 32 original o nuevo universo **firmado por dueño**, custodio Operaciones, 61 PR con IDs/filtro/as_of, recibo oficial | **ABIERTO** |
| B03 / G02 | 234 preimágenes+pasos+guard+idempotency+leases, 8 expirados, 29 referencias GitHub existentes, negativos PG18 | `EFFECT_RECON_RECEIPT` y `LIVENESS_RECEIPT` por RUN; efectos DB/Git/proveedor y workers verificados por **Operaciones/DBA/custodios**; alcance B02 firmado | **ABIERTO** |
| G15 Motor temporal L28 | Pruebas B02/B03 no cierran gates G01/G02 | Restantes B06/B07/B08/B09/B12 y autoridad del Motor | **0/7 CERRADOS** |

**Ningún criterio firmado, aprobado o promocionado.** El autor es GPT-6, mismo modelo; no hay juez independiente ni representación Claude. No se cerraron las plantillas L28. **NO-GO / UNVERIFIED**.
