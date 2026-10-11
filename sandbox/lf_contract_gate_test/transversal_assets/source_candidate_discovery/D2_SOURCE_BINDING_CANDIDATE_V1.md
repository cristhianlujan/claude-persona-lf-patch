# LF D2 — Generación de propuesta de binding desde inventario canónico

**Unidad 7 (componente)**: `private.fn_lf_d2_source_binding_candidate_v1(source_ref)` reutiliza D2 binding readback, `inventory.fn_lookup_v3`, `pg_catalog` y `POL-LF-SOURCE-RESOLUTION` desde Supabase. Recibe únicamente referencias exactas `db://schema.object`, sin nombres de tabla incorporados al código.

Devuelve una propuesta técnica no publicable automáticamente, con huella de esquema y columnas observadas. Todo campo de permiso queda vacío: `permitted_columns=[]`, `allowed_filter_fields=[]`, `read_facade_ref=null`, `required_permission_code=null`, `admission_status=CANDIDATO`. No modifica `lf_activos`, permisos, RLS, policy ni crea read facades; no ejecuta lectura de filas.

**Verificación reversible:** cinco casos, 5/5: dos fuentes existentes de distinta forma, una inexistente, una URI de catálogo obsoleta y entrada nula. La matriz exige que nunca se otorgue acceso ni se realice ejecución y que incluso las fuentes existentes permanezcan CANDIDATO. El inventario se refrescó separadamente antes de la prueba (6.325 objetos, 13.203 dependencias, drift 0); no se confundió currentness con ausencia de fuente.

**Estado:** bajo gobernanza Supabase, solo propuesta. Es necesario resolver binding aprobado y fachada parametrizada ejecutable bajo identidad empresarial real con política y RLS, y demostrar lecturas positiva/negativa antes de marcar la unidad 7 COMPLETADA.

Este componente no activa el runtime ni prueba una investigación empresarial. Excel no es registro ni fuente de verdad.
