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


## Lote 3 — vinculación verificable y bloqueo seguro

Readback solo lectura (2026-10-14): `public.lf_capability_version_registry` registra `CAPABILITY_SELECTOR@1.0.0 RELEASED`, pero no devuelve una versión registrada bajo `METHOD_PACK_REGISTRY` ni `PROFILE_ASSESSMENT`. El archivo JSON y la función Python del PR son **fuentes candidatas, no una liberación operativa**. No se efectuó ninguna escritura SQL.

Corregido en `skills/profile_creator/validators/plan_profile_evolution.py`:
- Las banderas y referencias aportadas dentro de assessment/catalog JSON no acreditan autoridad.
- Se requiere `trusted_source_readback` inyectado por el invocador de confianza; por omisión no está vinculado y se bloquea solo `candidate_materialization_allowed`.
- El verificador recibe digests SHA-256 exactos del catálogo y assessment normalizado; solo un recibo que concuerde en ambos, confirme estado vigente, versión y liberación del catálogo, y verifique las evidencias permite **candidatura reversible**.
- No se alteran `profile_source_write_allowed=false`, `automatic_runtime_activation=false` ni `automatic_production_activation=false`.
- Los tests positivos del verificador son dobles de prueba, nunca recibos reales de Supabase.

Reproducción local sobre copia byte-exacta de `plan_profile_evolution.py` con Git blob `24093e701da9d75493e2a15ee3b0e450d1e5dbba`: **10/10** regresiones de composición, **3/3** flujo de planificación y **4/4** límites de autoridad: total **17/17 PASS**. La nueva regresión se añadió al archivo del PR `test_profile_evolution_reconciliation_v1.py`; la ejecución por CI/Train sigue sin constancia.

**Siguiente frontera real:** definir y registrar un catálogo cualificado en autoridad Supabase con política de versionado y evidencia empírica, y proporcionar un resolver confiable que emita readback de métodos/señales. Ningún valor artificial `provider_verified=true` o texto `fixture://` sustituye ese trabajo. PR aún borrador: no iniciar Train ni merge mientras esas pruebas operativas falten.
