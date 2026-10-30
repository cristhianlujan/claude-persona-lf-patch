# PG-00.C3.5 — Contrato candidato de atestación para publicación gobernada

**Estado:** `DESIGN_ONLY / AUTHORITY_NONE / NO_GO_WRITE`. No es aprobación de release, migración ejecutable, llave de firma ni sustituto de Router, PASE o LF Merge Train. Separa preparación de propuesta, decisión autorizada, aplicación y consumo. Complementa `PG00_C3_AUTHORITY_CHAIN_V1.md` y el preflight de #3371.

## 1. Alcance y reglas fail-closed

- El agente solo puede **preparar y verificar offline** un manifiesto candidato. Los valores declarados por el agente (incluidos `approved_by`, recibos de Train, firmas embebidas o `PASS`) **no son evidencias de autoridad**.
- El preflight de #3371 sigue devolviendo `verdict=BLOCKED`, `authority=NONE` para cualquier entrada. Nunca usar sus comprobaciones estructurales como permiso de INSERT.
- La fuente `paulozterra/lf-programming-sandbox/standards/catalog.json` debe obtenerse del proveedor GitHub usando un commit completo fijado desde un contexto autenticado. El candidato no decide el commit de confianza.
- No usar aprobación de otro HEAD, aprobación expirada/revocada, ejecución anterior, recibo histórico ni evidencia perteneciente a otro release.
- No ejecutar SQL/DDL/DML directo: la única ruta posterior, si se aprueba formalmente, es Router ACT-0001 → DB_WRITE_TRANSPORT `MIGRATION_VIA_MERGE_TRAIN` → PASE/checks exact-HEAD → Train → recibo/ledger/readback post-apply.

## 2. Sobre de propuesta offline (no confiable)

El preparador puede emitir un `candidate_manifest` **informativo**, sin campo capaz de otorgar autoridad. Estos datos serán recomputados por un verificador independiente contra proveedores confiables:

| Campo | Propósito | Verificación obligatoria |
| --- | --- | --- |
| `schema_version` | Identificar versión del contrato de propuesta | Igualdad exacta a versión formalmente admitida |
| `proposal_id` | Referencia única no reutilizable | Identidad y unicidad verificadas en ledger gobernado; no aceptar unicidad autodeclarada |
| `source_repo`, `source_path` | Ruta de origen | Coincidencia con fuente permitida |
| `source_commit_sha` | Fijar contenido fuente | SHA obtenido por GitHub autenticado, no por el candidato |
| `source_file_sha256` | Vincular bytes originales | Recalcular sobre bytes de GitHub en el SHA fijado |
| `source_catalog_version` | Pin de versión | Comparación con documento fuente y política de versión |
| `release_catalog_sha256` | Pin del payload transformado | Recalcular sobre canonicalización JSON formalmente definida |
| `release_status_requested` | Cambio solicitado | Debe existir decisión autenticada específica de promoción; no autoriza por sí solo |
| `chg_id`, `migration_path` | Referencias del cambio propuesto | Resolución de CHG, naming, una migración/PR y trazabilidad a propuesta |
| `policy_version` | Política de autorización exigida | Versión admitida por órgano gobernante, recuperada de contrato versionado |

**Decisión pendiente:** algoritmo concreto de JSON canónico y digest (bytes y normalización), esquema del manifiesto y política de identificadores no deben inventarse a partir de este diseño. Hasta su ratificación, el verificador debe bloquear.

## 3. Atestaciones independientes y separación de funciones

El sistema verificador recuperará desde fuentes autenticadas (no del JSON enviado por el agente):

1. **Atestación de fuente:** proveedor GitHub, repositorio/ruta, commit completo, bytes y digest. Resolver de nuevo el SHA y estado de admisión, sin confiar en enlaces o capturas.
2. **Atestación del owner:** identidad autorizada por una política versionada, acción explícita para *ese* proposal ID, source SHA, digest release, versión y estado destino. Establecer vigencia/revocación.
3. **Juicio independiente:** revisión del proveedor con identificador, actor autorizado y SHA revisado; reviewer distinto del autor donde la política lo exija. Un comentario textual no es `APPROVED`.
4. **Atestación de admisión:** Router `ACTUALIZACION_DB_LF` y `select_route()` autorizado para la propuesta concreta; controles de naming, PR exact-HEAD y los cuatro checks `lf-independent-change-admission`, `ig-runtime-candidate-judge`, `PASE` y `migration-source-parity`. El estado verde de un HEAD antiguo no cuenta.
5. **Atestación post-apply:** solo después de aplicar, Train receipt verificado, ID de ejecución, ledger, versión, digest y lectura de fila exacta. Nada de esto existe durante preflight.

Los IDs, SHA, digest, versión, status, CHG y ruta de migración deben estar vinculados **a la misma propuesta**, bajo una política de expiración y antirreplay aprobada. La transformación permitida estructuralmente por el preflight es únicamente `status`, pero su autorización sigue siendo externa.

## 4. Estados y autoridad

| Estado | Entrada mínima | Autoridad que concede |
| --- | --- | --- |
| `SOURCE_DRAFT` | Fuente observada | Ninguna |
| `SOURCE_REVIEWED` | Revisión exact-SHA verificada | Sistema de admisión autorizado, no agente |
| `RELEASE_APPROVED` | Owner autorizado + revisión independiente + política vigente + digest de release fijado | Mecanismo de decisión aún **por aprobar** |
| `TRAIN_ADMITTED` | Router, transport, PR/checks exact-HEAD | Gobernanza vigente y Train |
| `TRAIN_APPLIED_VERIFIED` | Recibo Train y readback/ledger concordantes | Verificador post-apply independiente |
| `CONSUMABLE_BY_PG` | Permisos mínimos, contrato de lectura y pin versión/digest | Autoridad del consumidor PG, por definir |

Si no existe fuente de autoridad verificable, la salida es `BLOCKED` o `REQUIRES_DECISION`, jamás `GO_WRITE`.

## 5. Reglas de ejecución y casos negativos

- Un `null` añadido/eliminado, duplicados JSON raíz/anidados, cambios de reglas o waiver: rechazo estructural (MEDIA-1/MEDIA-2 cerradas en preflight).
- Identificador de revisión falso, texto `approved_by`, firmas y recibos sintéticos: rechazo de autoridad.
- Review de SHA A y fuente SHA B; digest anterior y release nuevo; CHG no vinculado: rechazo.
- Reutilización de revisión con propuesta distinta, aprobación revocada o actor sin permiso: rechazo.
- Semver igual con payload diferente, downgrade o inserción duplicada: rechazo; la transacción gobernada deberá revalidar versionado/unicidad sin UPDATE/DELETE.
- Resultado PASE verde sobre HEAD anterior, checks incompletos, Router equivocado o migración fuera de Train: rechazo.
- Recibo post-apply ausente, ledger divergente o fila con digest diferente: nunca marcar publicación verificada ni habilitar consumo PG.
- No reutilizar PASS histórico de otra ejecución al incorporar C3 al puente PG-03_C2 de #3372.

## 6. Dependencias de implementación que bloquean cualquier INSERT

1. Política formal de identidad, autorización, separación de funciones, vigencia y revocación para el cambio `BORRADOR_EN_REPO_DE_CALIFICACION` → `APROBADO` / `VALIDAR_CON_LEGAL`.
2. Esquema versionado de atestaciones y manifiesto, incluyendo fuente autenticada, canonicalización y antirreplay.
3. Aprobación explícita del mecanismo **dentro de Train** que pueda insertar sin relajar ni evadir silenciosamente el guard `PG00_C3_UNTRUSTED_INSERT_FORBIDDEN` de #3365.
4. Política formal de versiones/duplicados, validación concurrente en transacción y restricciones de acceso mínimo.
5. Ensayo end-to-end desechable con proveedor autenticado o fixtures verificables, controles negativos, revisión independiente exact-HEAD y comprobación de recibo postapply.

Hasta satisfacerlas: mantener #3365 y #3371 en draft, no crear writer ejecutable ni migración de datos, no cambiar triggers/RLS, no añadir credenciales o rutas alternativas.

## 7. Próxima salida revisable

Entregar por separado una propuesta formal de autoridad (quién aprueba y cómo se consulta), esquema de manifiesto/atestación con fixtures adversariales y diseño del transport de Train. Cada uno requiere dictamen independiente; ningún `PASS` del validador local basta para activar escrituras.
