# LF D1/D2 — Contrato candidato de asociación de fuente/lectura v1

**Estado**: DRAFT en GitHub. Supabase sigue siendo autoridad. **No es registro publicado ni activa lecturas**. Basado en EKB `GOV-FIELD-LEVEL-SOURCE-RESOLVER-GAP-001`, política actual `POL-LF-SOURCE-RESOLUTION`, tablas `public.lf_activos`, `public.lf_operation_step_contracts` y `lf_ops.permisos`.

## Principio: reutilizar autoridad antes de crear una tabla

1. **D1 (descubrimiento)** consulta `pg_catalog` dentro del alcance permitido y entrega referencias candidatas a objeto, columnas, relaciones y procedencia. La coincidencia léxica o una FK no certifica autoridad ni permiso.
2. **Registro canónico**: antes de admitir lecturas, resolver el activo exacto mediante `public.lf_activos` / `public.v_lf_fuente_operativa` usando código canónico o alias registrado, con versión, estado y vínculo Supabase. El tipo `DB_TABLE` existe en el catálogo. **No hay todavía un binding publicado para `lf_ops.cargas_lotes` o `lf_ops.cargas_archivos`; no se inventa.**
3. **Contrato de acceso tipado**: especificación candidata como metadatos versionados del activo existente, adjudicados desde Supabase, no desde GPT:
   - `source_ref`: identidad estable de origen; `object_locator` y `object_kind`: objeto observado en `pg_catalog`.
   - `source_schema_fingerprint`: hash de columnas, tipos y claves observados; divergencia bloquea.
   - `permitted_columns`, `allowed_filter_fields`, `max_rows`, `max_cost`, `freshness_rule_ref`: solo lectura acotada.
   - `read_facade_ref`: RPC/query-template tipado y probado; no ruta derivada de nombre de tabla.
   - `required_permission_code`: referencia a código de `lf_ops.permisos` si aplica B2B; en otros dominios, referencia a SU catálogo de autorización autorizado. No se inventa un permiso.
   - `tenant_scope_rule_ref`: condición de aislamiento con identidad autenticada y empresa de sesión; nunca se acepta la empresa propuesta por el modelo.
   - `operation_code`, `step_id`, `resolver_ref`: enlazan al `public.lf_operation_step_contracts` existente y recibo de ejecución autorizado.
   - `policy_code`, `policy_sha`: binding de `POL-LF-SOURCE-RESOLUTION` CURRENT en Supabase.
   - `binding_version`, `admission_status` (CANDIDATO/VIGENTE), `approved_by_ref`, `receipt_ref`, `evidence_ref`: publicados únicamente bajo gobernanza Supabase.
4. **D2** resuelve el contrato **dentro de Supabase**. No evalúa autoridad a partir de flags autodeclarados por LLM; solo utiliza un resultado de la ruta autorizada y vigente. El planificador `TARGETED_EVIDENCE_ACQUISITION` recibe `candidate_ref` validado; no hay otro planificador.
5. **Data plane**: únicamente la fachada canónica ejecuta una SELECT parametrizada, con identidad real, filtro de empresa derivado de contexto confiable, RLS y control de fila/costo. No habilitar SQL libre, `SECURITY DEFINER` genérico ni lectura mediante `postgres`/service_role.
6. **Resultados, trazas y benchmark**: se registran en Supabase mediante los contratos existentes de ejecuciones, evidence y tests; Excel es una proyección informativa y no se usa como entrada.

## Semántica vigente verificada para B2B

- `lf_ops.permisos.status`: `CANDIDATO/EN_REVISION/VIGENTE/INACTIVO/ARCHIVADO`, nunca asumir `ACTIVE`.
- `lf_ops.b2b_user_company_assignments.status` y `lf_ops.b2b_user_company_permissions.status`: mismo grupo de estados; `access_effect = ALLOW|DENY`. Una denegación explícita prevalece.
- `lf_ops.empresa_usuarios.status = ACTIVE` para la función de usuario actual.
- Confirmar permiso exacto por `permission_id`, empresa y usuario, con asignación `VIGENTE`; negar si no existe, es `CANDIDATO`, está revocado o se trata de otra empresa.
- El objeto `lf_ops.cargas_lotes` tiene `FORCE ROW LEVEL SECURITY`, y `anon`/`authenticated` **no tienen SELECT**. El permiso de visualización `B2B_LOAD_DETAIL_VIEW` en `permisos` está todavía `CANDIDATO`: no autorizar lectura por simple coincidencia.
- Estado observado del sandbox el 10/10/2026: 0 empresas-usuario asignadas, 0 asignaciones de permisos empresariales, 0 usuarios empresariales. La conexión administrativa no contiene `auth.uid()`. Por tanto, en sandbox hoy **no hay ruta de lectura B2B autorizada demostrable**.

## Prueba previa y criterio de admisión

Se ejecutó `source_permission_admission_matrix_synthetic_v1.sql` en LF_SUPABASE_SANDBOX, sin escrituras: **12/12 PASS, 1 caso lógico favorable y 11 negativos**. Esto demuestra lógica condicional sobre fixtures sintéticos, NO una ejecución real bajo identidad/tenant ni que la política esté lista para activación.

Antes de admitir cualquier binding real:

- Verificar y registrar en Supabase una fuente canónica exacta y una `read_facade_ref` autorizada, con operación/step, columnas, filtros y fingerprint probados.
- Confirmar estados VIGENTE y prueba negativa de ausencia de permiso + prueba propia positiva + cross-tenant negativa usando identidades **de prueba reales y válidas** en un entorno aislado; no simular JWT de usuarios reales ni saltarse RLS.
- Verificar que la fachada se puede invocar como principal autorizado y que la consulta está limitada; si hay rechazo o falta de identidad, bloquear sin reutilizar credenciales privilegiadas.
- Registrar caso, evaluación y recibos en Supabase. Aplicar gobernanza Git → PR → merge → migración exacta sandbox (si se requiere) → ledger → readback.
- Solo entonces considerar incorporar D1/D2 al runtime y comparar un benchmark ciego. Sin esto, PR #2190 permanece DRAFT.

**No crear** permisos paralelos, tabla de casos operativos en Excel, rutas especializadas por tabla ni bypass SQL. El contrato de metadatos se propone; no se escribe ni publica automáticamente en `lf_activos`.
