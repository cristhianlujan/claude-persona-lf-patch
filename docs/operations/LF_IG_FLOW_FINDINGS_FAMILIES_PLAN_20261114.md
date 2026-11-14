# LF — Input Governance: contrato de flujo, hallazgos y plan de recuración (2026-11-14)

Estado: **PROPUESTA EN PR #3902 / NO DESPLEGADO / NO CERRADO**. Proyecto de ensayo `mhwmirqcgxxukpctffuv` exclusivamente. No hay permisos nuevos, rutas alternas, escrituras manuales de assessments ni promoción implícita.

## Contrato de cuatro causas máximas de bloqueo del flujo

| Código de nivel 1 | Condición demostrable | Acción | Permitido |
|---|---|---|---|
| `FLOW_CONTRACT_INVALID` | Esquema/versión, identidad o campos obligatorios incompatibles; paso/bridge no cumple predecesores | No despachar llamada; reportar campo y reparar contrato | No |
| `FLOW_TRANSPORT_INVALID` | Payload nulo/vacío/`{}`, RAW con `semantic_receipt_sha256`, `catalog_sha256` o `request_sha256`, ticket o respuesta estructuralmente inválida | No enviar; informar campo exacto; solicitar transporte correcto | No |
| `FLOW_SOURCE_UNREADABLE` | Fuente inexistente/no legible, snapshot imposible de leer/verificar, digest de fuente o alcance diferente al autorizado | No usar fuentes sustitutas; validar fuente/hash y predecesores | No |
| `FLOW_AUTHORITY_INVALID` | Consumidor no autorizado, ticket no asociado al RUN, identidad falsa, escritura/promoción no autorizada, `ACTION_AUTHORIZATION_GATE` | Bloquear efecto y registrar evento de autorización | No |

Los cuatro códigos son una **taxonomía propuesta**, no se deben presentar como implementados por todos los escritores hasta el readback del contrato y pruebas. Los códigos internos existentes de SQL/Edge se conservan: nunca reconstruir o quitar autoridad de Gate2, handoff ni Router.

## Hallazgos que NO bloquean el análisis READ_ONLY del perfil

| Causa de contenido | Acción sin privilegios |
|---|---|
| Regla incompleta o contradictoria, coverage `PARTIAL`, decisión humana pendiente | Documentar brecha, referenciar regla; propietario decide sobre la regla y efectos |
| Skill/IG no requerido, READY ausente, `BLOCKED`, Curator o Validator pendientes | Mantener RUN del perfil; `finding_class=INPUT_GOVERNANCE_CONTENT`; recurar por dependencia gobernada |
| Fuente vigente con cambios de contenido, currentness `STALE`, evaluación sin cierre | Releer fuente canónica y revalidar; NO aceptar aserción de padre sin evidencia nueva |
| `VALIDATOR_EXECUTION_ID_REQUIRED` en worker o timeout 90s | La llamada inválida no sale (fallo del transporte hijo); el perfil conserva hallazgo de skill y sigue analizando en READ_ONLY |
| `HUMAN_DECISION_REQUIRED` | Continuar SOLO el análisis; toda promoción/escritura regulada permanece bloqueada por autoridad |

No convertir `finding` en `READY` ni `PASS`. `continuation_allowed=true` se refiere exclusivamente al análisis sin efectos.

## Estado reproducible de la recuración (SELECT, 14 nov 2026)

Pantalla `lf_ops.pantallas.id=44`, código real `B2B-CARGA-002` — Wizard de nueva carga.

| IG RUN | Estado medido | Familia | Validator PASS | Comparación contra 513 |
|---|---|---:|---:|---|
| 513 padre | COMPLETED | 47 | 47 | Antecedente histórico; no usar como PASS del sucesor |
| 954 | BLOCKED | 47 | 0 | 0/47 `curator_sha256` iguales, 0/47 evidencias binarias iguales |
| 955 | BLOCKED | 47 | 0 | 0/47 `curator_sha256` iguales, 0/47 evidencias binarias iguales |
| 956 | CURATING | 47 | 0 | 0/47 `curator_sha256` iguales, 0/47 evidencias binarias iguales |

Que los bytes difieran NO prueba por sí solo independencia semántica: es obligatorio reabrir fuente vigente, revaluar 47 familias y verificar recibo del Validator. No promover ni atribuir cobertura al padre #513.

## Plan de las 17 familias incompletas (revisión READ_ONLY del RUN 956)

Las 17/17 figuran `coverage_status=PARTIAL` y `qa_ready_status=BLOCKED`. Orden de ejecución sugerido por dependencias, no por supuesta facilidad:

| Grupo | Familia | Brecha medible o siguiente evidencia que Curator debe leer |
|---|---|---|
| 1 datos y contratos | API_DATA_CONTRACT | 0 contratos ejecutables/0 bindings de esquema materializados; resolver contrato versionado real |
| 1 datos y contratos | VALIDATIONS | 7 campos obligatorios de 73 sin validaciones canónicas; leer reglas de campo y contratos fuente |
| 1 datos y contratos | TRANSITIONS | 2 transiciones vigentes para 12 estados canónicos; contrastar grafo de transición completo |
| 1 datos y contratos | IDEMPOTENCY_CONCURRENCY | Fuentes parciales; verificar unicidad, reintento y concurrencia con contratos/versiones |
| 2 seguridad | SECURITY | Leer controles de acceso y negativas asociadas a los estados de carga |
| 2 seguridad | PRIVACY_PII | Verificar clasificación/minimización y retención del archivo por origen vigente |
| 2 seguridad | SESSION | Verificar expiración, revocación y contexto de sesión B2B en fuentes actuales |
| 2 seguridad | AUDIT | Verificar eventos y identidad de actor para carga y rechazo, sin afirmar QA |
| 2 seguridad | RATE_LIMIT | Verificar alcance por endpoint y regla vigente; REG_API_005 da 100/min IP y 300/min JWT, sin extrapolar a todas las rutas |
| 3 interfaz/estados | DESIGN_SYSTEM | Verificar tokens por pantalla; dependencia de decisión humana regla #390 (dark_mode) |
| 3 interfaz/estados | ASSETS_ICONS | Resolver assets/iconos con refs vigentes, sin imágenes supuestas |
| 3 interfaz/estados | LOADING_EMPTY_ERROR_STATES | Materializar evidencia de loading/empty/error por transición |
| 3 interfaz/estados | BROWSER_PLATFORM | 4/5 reglas vigentes, 1 candidata; contrastar matriz de navegador/responsive y pruebas |
| 3 interfaz/estados | VISUAL_EVIDENCE | Releer capturas/fuentes versionadas y corroborar pantalla real, no inventar QA |
| 4 resiliencia y pruebas | TIMEOUT_RETRY | Releer presupuestos por hop, reintentos idempotentes, y negativo 90s |
| 4 resiliencia y pruebas | OBSERVABILITY | Verificar logs, métricas, correlación RUN y error reportado |
| 4 resiliencia y pruebas | TESTING_OBLIGATIONS | 11/12 reglas vigentes, 1 candidata, 5 marcas pendientes; pruebas reproducibles por capa |

**Lote Curator autorizado:** solo relectura de fuentes CURRENT, recalcular cada assessment/hashes mediante escritor oficial y presentar evidencia; **no completar** si falta fuente, QA, prueba o decisión. Toda modificación funcional requiere otra operación gobernada con autoridad de efecto.

**Reglas reservadas al owner** (todas comprobadas `CANDIDATO` por SELECT): 390, 421, 422, 617, 620, 648. El Curator puede registrar el hallazgo, pero NO ratificarlas.

## Readbacks exigidos para cerrar

```sql
SELECT id,status,supersedes_run_id,family_count,source_snapshot_sha256
FROM programacion.input_readiness_runs WHERE id IN (513,954,955,956) ORDER BY id;
SELECT family_code,coverage_status,well_defined_status,qa_ready_status,
       validator_outcome,curator_sha256
FROM programacion.input_family_assessments WHERE run_id=956 ORDER BY family_code;
SELECT execution_id,step_order,step_id,status,evidence_ref,evidence_payload
FROM public.lf_operation_execution_steps
WHERE execution_id='<NUEVO_RUN_REAL>' ORDER BY step_order;
```

No cerrar el ensayo 0→80 sin RUN nuevo vinculado a frase, pasos 11/11, juez real, `public.lf_profile_execution_terminal_authority_receipt_v1` READY, y dos escenarios con/sin skill seleccionada. Despliegue Edge debe igualar contenido exacto de main con checksum/readback y conservar autenticación original.
