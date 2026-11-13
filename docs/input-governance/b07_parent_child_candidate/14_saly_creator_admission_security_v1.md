# B07 SALY — extensión mínima de admisión OIDC de CREACION_PERFIL_LF

**Solo propuesta PR gobernado.** Dueño 2026-11-13 12:53 Lima: «Si me designo». Designación SALY **documental**, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false`, `production_authorized=false`. SHA-256 del literal JSON de evidencia: `107332ebbae4295dc76179bd5619856cb61807b91a856c080b12e1942018fb0f`. No firma de Auth.

La operación del perfil existente `EJECUCION_PERFIL_LF` (Gate2 → `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1`) **no es** la creación. Para alta de `CREACION_PERFIL_LF`, reutilizar **exactamente los componentes existentes**: Issue `lf-profile-create-saly-governed` → `scripts/lf_profile_update_issue_dispatch.py` (validación/dispatch, cero DML) → `.github/workflows/lf-customer-profile-creator-governance-caller.yml` (`workflow_dispatch` en `main`, OIDC) → `lf-profile-creator-governance-caller-v1` → `run-creacion-perfil-lf` → registradores nativos. No se crea escritor paralelo, nuevo role ni nueva Edge Function.

**Contrato de Issue**: un JSON exacto, no credenciales:
```json
{"schema_version":"LF_SALY_PROFILE_CREATE_REQUEST_V1","action":"saly_profile_create_init","project_code":"SALY","target_code":"PERFIL-PRODUCT-DIRECTOR-SALY","profile_slug":"saly_product_director","owner_decision_sha256":"107332ebbae4295dc76179bd5619856cb61807b91a856c080b12e1942018fb0f","identity_verified":false,"production_authorized":false}
```
El Issue con etiqueta `lf-profile-create-saly-governed` dispara solo el dispatch del workflow canónico; **el workflow nunca toma el UUID del Issue**. El UUID lo genera el workflow OIDC y Edge vincula `caller.run_id`, `workflow_ref` y SHA.

**Invariantes**:
- Se acepta el **único** target SALY en el método OIDC ya admitido para `workflow_dispatch` de `main`; los cuatro targets Customer conservan el allowlist de rama histórica y `production_authorized=true` sin ningún cambio de sus permisos.
- SALY exige `owner_decision_sha256` exacto, `project_code=SALY`, `identity_verified=false`, `production_authorized=false` tanto en caller como runtime. El manifest persistido usa `customer_profile_scope=false`, `production_authorized=false` solo para SALY. El readback del job exige ambos falsos y aborta de lo contrario.
- Ningún cambio en OIDC `issuer/audience/JWKS`, ninguna nueva ruta de escritura, ningún secret en Issue. Runtime sigue verificando target, router `PROFILE_CREATE`, `init_execution`, recibo y todos los pasos existentes. El registro final en `lf_activos` se verificará sin INSERT directo.
- Los negativos deben probar SALY con identidad false vs true, `project_code=LF`, target LF, slug incorrecto, hash falso, scope customer, y caller con método no autorizado.
- **Gate antes de ejecución viva**: #3835 perfil SALY debe estar disponible en `main` por ruta gobernada, y esta modificación de Edge+workflow debe pasar CI global (R17/PASE/seguridad), desplegarse por su vía oficial y mostrar readback de versión/scope. Sin esos recibos NO abrir Issue operativo ni afirmar RUN.
- #3832 Train de owner/operación requiere después `CREACION_PERFIL_LF COMPLETED` + `lf_activos`; #3818 Train permanece prohibido sin OK DDL específico del dueño.

**Estado**: CANDIDATO, NO-GO, ninguna autorización productiva nueva.
