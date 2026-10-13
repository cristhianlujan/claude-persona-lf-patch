# Fuentes retiradas sin aplicación — lote 1 de reconciliación

Retiro source-only. Se preservan los blobs sin cambios fuera de `supabase/migrations`; no deben volver a ejecutarse.

| Archivo Git v1 | Blob Git SHA-1 | SHA-256 canónico Git | Versión v1 en ledger | Reemplazo aplicado (versión_nombre) | SHA-256 canónico del ledger |
|---|---|---|---|---|---|
| `20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql` | `dbe466b827f10c257dba6449d65d6750f2328057` | `0b4bd0f822d82e6bd752af45c754652ca0f0ea4cc5a885d6307ba09f4b2c373a` | `20261012223000`: ausente | `20261013160002_lf_ig_m100_sandbox_admission_coherent_v2` | `4fb55f0933e142c2479d8117957bb3a2e7c581a297215d105384ada954b07107` |
| `20261013001500_lf_profile_evolution_phase_boundary_v1.sql` | `e17a50b18e4a239639eaeb936fe70e9be23cb0ca` | `73e93a170f2554f91b5f8a6605d890ccc32ec78703f32094bc3e5480d928f55b` | `20261013001500`: ausente | `20261013020001_lf_profile_evolution_phase_boundary_v2_train` | `6c7b5b7b1df06edbef36545598ea7ce7c638d91f99af649768263ecec61f9957` |

El ledger de solo lectura no devolvió filas para los dos v1 y sí devolvió las filas de los reemplazos indicados. Los SHA-256 se calculan con la normalización del comparador del Train: saltos de línea normalizados, líneas completas de comentario SQL omitidas y saltos finales recortados. Como los hashes canónicos difieren, son retiros por supersesión aplicada, no renombres equivalentes por contenido.

No se modificó el ledger ni el estado de la base. No se aplicó SQL ni se dejó fuente ejecutable en `supabase/migrations`.
