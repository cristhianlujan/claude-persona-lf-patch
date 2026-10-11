# LF — RLS empresarial por empresa y permiso, metadatos de cargas

**Alcance autorizado por usuario:** revisar y modificar los RLS de las fuentes B2B para permitir lectura mínima cuando exista autorización real. Solo sandbox y solo `lf_ops.cargas_lotes`, `lf_ops.cargas_archivos`, una función auxiliar de autorización; no se tocan otros RLS.

## Cambios
- Conserva `FORCE ROW LEVEL SECURITY` en ambas tablas.
- Introduce una política **PERMISSIVE SELECT TO authenticated** para `cargas_lotes` que exige a la vez `company_id=lf_ops.b2b_current_company_id()` y una función que comprueba usuario real, empresa APPROVED/ACTIVE, asignación VIGENTE, permiso exacto `B2B_LOAD_DETAIL_VIEW` VIGENTE con ALLOW VIGENTE y ausencia de DENY VIGENTE.
- Introduce política de `cargas_archivos` que solo ve archivos asociados a una carga **ya visible bajo su propio RLS**. No consulta archivos originales mediante un helper privilegiado.
- Grant de SELECT **solo columnas de metadatos**: se excluyen `policy_snapshot`, `idempotency_key`, rutas de almacenamiento, hash del archivo, y campos internos. Sin GRANT para `anon`, `service_role` ni DML.
- Función `lf_ops.fn_b2b_can_read_load_company_v1(uuid)` es un auxiliar **SECURITY DEFINER de alcance restringido únicamente a tablas de identidad y permisos**; debe usar `auth.uid()` del JWT y compañía existente; nunca consulta registros de cargas. Esto evita conceder SELECT directo sobre catálogos B2B bajo FORCE RLS. No usarla como autorización para otro producto y nunca aceptar un `company_id` suministrado por GPT para seleccionar datos.

## Pruebas reversibles
Suite en una única transacción `BEGIN; [migración] [datos sintéticos] [assertions] ROLLBACK;` con ids y correos `example.invalid`, sin usuarios reales. PASS comprobado:
- acceso positivo a un registro de carga y archivo de la empresa del actor **con JWT simulado a nivel SQL**, asignación y permiso VIGENTE temporales;
- aislamiento de carga y archivo de empresa ajena;
- cambio de ALLOW a DENY, asignación INACTIVO, permiso CANDIDATO, empresa SUSPENDED, usuario DISABLED, JWT ausente;
- no concesión a anon, FORCE RLS intacto, acceso a columnas sensibles no concedido, DML denegado.

**Limitación:** el helper prueba reglas RLS con contexto de JWT simulado en SQL, NO un JWT auténtico de Supabase ni autenticación externa. No se crea/promueve empresa, usuario o permiso real; todo fixture y cambio CANDIDATO→VIGENTE se revierte. Un permiso no VIGENTE en producción sigue bloqueando. El usuario pidió cambiar los RLS, no habilitar usuarios reales o exponer datos.

## Admisión pendiente (Unidad 7)
1. Registro vinculante de fuente/fachada `VIGENTE` en Supabase con contrato actual; no generarlo automáticamente a partir de candidatos.
2. Identidad real verificada, empresa, asignación, permiso e identificación de contexto; pruebas negativas entre empresas con sesión auténtica.
3. Fachada gobernada con límites y recibo de evidencia en el ledger. La política RLS no equivale a un recibo ni autoriza por sí sola a GPT/runtime.

**EKB:** `RLS-001` recuerda que RESTRICTIVE sin política PERMISSIVE bloquearía también accesos válidos; por ello se añadió una política PERMISSIVE SELECT específica. `SEC-007` recuerda que roles propietarios o con BYPASSRLS quedan fuera de la frontera: el runtime nunca debe leer como `postgres` o `service_role`.

Supabase contiene autoridad/estado; Excel solo visualización.
