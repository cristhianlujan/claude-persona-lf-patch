# PE10_C3 V2 — Reconciliación de autoridad y componentes

## Fuente verificada

- Supabase `public.lf_capability_registry`: `CAPABILITY_SELECTOR` ACTIVE; `public.lf_capability_version_registry`: versión 1.0.0 RELEASED, provider `capability_selector_v1.py`. No se autorizó ningún cambio en la versión/release.
- GitHub, PR #2579: se incluyeron `profile_assessment_v1.py`, `capability_selector_v2.py`, `method_pack_registry_v1.json`, `plan_profile_evolution.py` y sus pruebas, como fuentes candidatas.
- El catálogo `method_pack_registry_v1.json` declara `SUPABASE_REGISTRY_WITH_REPOSITORY_SOURCE`, pero **no hay comprobación de que esté efectivamente materializado, registrado, versionado y enlazado como autoridad activa en Supabase**. No convertir una etiqueta JSON en recibo.
- `PROFILE_ASSESSMENT` opera con evidencia/senales proporcionadas por quien invoca; no existe readback de extracción autónoma de lenguaje natural ni de fuentes de datos de producción.

## Contrato corregido

- Ruta única: `PROFILE_ASSESSMENT v1` → `CAPABILITY_SELECTOR v2` → `plan_profile_evolution.py`, con `CAPABILITY_SELECTOR v1` transversal reutilizado y sin modificar.
- Retirados compositor v1 y prueba sintética redundantes. No hay dos selectores de métodos activos.
- Reproducción local previa al arreglo: método `HOSTILE_CHALLENGE` y capacidad compatible se añadían pese a ausencia de `candidate_exists` y `candidate_ref`.
- Arreglo: método elegible únicamente si están enlazadas las precondiciones y referencias requeridas y cabe en presupuesto. Referencias suministradas por el llamador no constituyen atestación independiente; selección no otorga escritura/ejecución/activación.
- El planificador pasa las referencias `precondition_evidence` y `method_evidence` al selector en vez de descartarlas.

## Ejecución y límites

- 10 tests locales de reconciliación + 3 de planificador: PASS. Copias locales del código fuente corresponden exactamente a los Git blobs `capability_selector_v1.py`, `capability_selector_v2.py`, `profile_assessment_v1.py` y `plan_profile_evolution.py` tras el arreglo.
- `test_profile_evolution_reconciliation_v1.py` quedó en PR para replay de la integración sobre el catálogo candidato de repositorio; no atribuirle resultado de CI/Train hasta ver evidencia real.
- Pendiente: resolver autoridad canónica del catálogo de métodos, fuente de señales, validación de referencias, replay del paquete con Train y source projection de runtime.

Estado de este lote: código reconciliado en PR borrador; SIN MERGE, SIN SUPABASE WRITE y SIN ACTIVACIÓN.
