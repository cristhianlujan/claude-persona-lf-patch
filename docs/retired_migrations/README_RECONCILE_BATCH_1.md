# Retired unapplied migration sources — reconciliation batch 1

Source-only retirement for PR reconcile batch 1. These files are preserved byte-for-byte outside `supabase/migrations`; they must not be replayed.

| Git source | Git blob SHA-1 | Ledger v1 | Applied replacement in ledger | Replacement canonical SHA-256 |
|---|---|---|---|---|
| `supabase/migrations/20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql` | `dbe466b827f10c257dba6449d65d6750f2328057` | absent: `20` | `20261013160002_lf_ig_m100_sandbox_admission_coherent_v2` | `4fb55f0933e142c2479d8117957bb3a2e7c581a297215d105384ada954b07107` |
| `supabase/migrations/20261013001500_lf_profile_evolution_phase_boundary_v1.sql` | `e17a50b18e4a239639eaeb936fe70e9be23cb0ca` | absent: `20` | `20261013020001_lf_profile_evolution_phase_boundary_v2_train` | `6c7b5b7b1df06edbef36545598ea7ce7c638d91f99af649768263ecec61f9957` |

Read-only ledger check on 2026-10-13 found no rows for either v1 version and exact version/name rows for both replacements. The replacement canonical hashes are SHA-256 of the Train-normalized ledger statements (line-ending normalization, full-line SQL comments omitted, trailing newlines removed). The old v1 sources have different content from their replacements; these are supersession records, not content-equivalent renames.

No ledger rows or database state were changed. No SQL was applied or added to the executable migration directory.
