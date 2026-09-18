# POL-LF-SOURCE-RESOLUTION / SOURCE_RESOLUTION_POLICY

Inventory status: `ACTIVE_TRANSVERSAL_POLICY`.

Este README cubre `POL-LF-SOURCE-RESOLUTION` y el alias/capability `SOURCE_RESOLUTION_POLICY`.

## Propósito

Gobierna cómo resolver la fuente autoritativa antes de hidratar contenido: Supabase primero para autoridad operativa, IDs/aliases registrados antes de búsqueda libre y fallback controlado sólo con evidencia.

## Cuándo consumirlo

Antes de buscar, leer o usar GitHub, Drive, migrations, imágenes o artefactos como fuente de decisión operativa.

## Cómo consumirlo

Resolver la policy activa por snapshot, clasificar la familia de fuente y seguir su `resolution_order`. GitHub es artefacto técnico y requiere binding Supabase; Drive puede apoyar visualmente pero no decide estado, reglas o permisos.

## Superficies canónicas

- Policy: `public.lf_policy_versions.policy_code=POL-LF-SOURCE-RESOLUTION`
- Fuente operativa: `public.v_lf_fuente_operativa`
- Router: `ACT-0001`
- Migration family: ledger Supabase → exact GitHub migration path → parity validator.

## Fail-closed / límites

Bloquear ante ID/alias no resuelto, autoridad inferida por similitud, source family desconocida o fallback sin evidencia. ZIP es último recurso para migrations, no ruta normal.

## Validación y readback

Comprobar version/SHA activos, binding Supabase de cualquier artefacto técnico y trazabilidad de la ruta de resolución aplicada.

## No duplicación

No crear resolvers de fuente paralelos. `SOURCE_RESOLUTION_POLICY` es alias de inventario de la policy canónica, no otra policy.

## Currentness

Releer policy activa, fuente operativa y bindings antes de hidratar contenido. Un path histórico no constituye autoridad actual.
