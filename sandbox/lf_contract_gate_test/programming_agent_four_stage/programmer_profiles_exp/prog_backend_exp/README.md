# Backend Java/Spring — candidate sandbox pack
Estado: CANDIDATE_SANDBOX_ONLY. No se registra, activa ni promueve. Misma estructura de archivos de `profiles/_template`, más `runtime_binding.json` y eval ejecutable.

Ejecutar: `python3 validators/validate_pack.py .` desde esta carpeta, y `python3 evals/run_cases.py` desde esta carpeta. Los ejemplos y fixtures NO son instrucciones para el Worker. La conformidad con PG-07 C2 se comprueba también en el test de integración de #3667 (sobre visibles v2).

Fuente técnica: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` y `cristhianlujan/programming-agent/docs/WORKER.md`. No se inventa contenido de STD: los IDs y versiones se resuelven en el catálogo gobernado antes de cualquier activación.
