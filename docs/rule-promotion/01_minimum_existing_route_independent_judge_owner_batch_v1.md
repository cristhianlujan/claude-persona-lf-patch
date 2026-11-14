# LF — promoción de reglas: ruta mínima sin gate nuevo (propuesta SOURCE_FIRST)
Fecha de corte: 2026-11-14, solo sandbox; no promoción real ni aprobación simulada.

## Autoridad observada por SELECT
- Perfil existente `PERFIL-PRODUCT-DIRECTOR-LF`, `lf_profile_write_authority_v1(operation_code='PROMOCION_REGLA_LF',status='ACTIVE')`: 1 vínculo.
- No crear perfil adicional ni entrada ACT-0001 paralela. El perfil Product Director actúa como perfil de promoción, sujeto al Router oficial.
- `lf_rule_promotion_v1`: 0 solicitudes, 0 aprobadas, 0 aplicadas en preimagen.
- `lf_ig_project_owner_v2`: `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `TEMP_DOCUMENTARY_ACTIVE`, `owner_sub` presente **sin acreditar identidad real**.
- `programacion.fn_t_remed_rule_promotion_verdicts_v1(5,NULL)` denegó la inspección por `42501`; se reconstruyeron sus 5 criterios vía SELECT, sin afirmar recibo oficial. El script propuesta solo otorga EXECUTE al rol `service_role`; **no** a `anon`/`authenticated`. No elimina el bloqueo del rol de inspección.

## Ruta sin gate adicional
`USUARIO → ACT-0001 → EJECUCION_PERFIL_LF (Product Director) → Step40 IG solo como skill → Step50 RAW → Step60 validación determinista → Step70 revisión **independiente real** → lf_rule_promotion_request_v1 (durante RUN IN_PROGRESS, antes de Step80) → Step80 cierre del perfil → lf_rule_promotion_report_v1 → owner humano autenticado → lf_rule_promotion_decide_batch_v1 → lf_rule_promotion_apply_batch_v1 → guard/snapshot/readback`.

**Binding canónico adicional (readback de RUN histórico `EXEC-PROFILE-GATE2-458E10677E34F812D924F11F`):** Step70 independiente real guarda `semantic_judge_result.verdict=PASS_INDEPENDENT_SEMANTIC`, `producer_independence_proven=true`, `model_call_count=1`, `judge_v3_evidence.judge_invocation_kind=NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE` y `judge_v3_evidence.unsupported_claims=[]`. No existen `review_mode` ni `reviewer_is_producer` en ese recibo: se eliminaron del guard, sin inventarlos. Step70 `candidate_sha256` debe coincidir con Step50/60 `raw_output_sha256`; Step70 `scope_packet_sha256` con Step40 `scope_authority_packet_sha256`, y la salida Step50 debe citar específicamente `supabase://lf_ops.reglas/<RULE_CODE>` entre las fuentes del producto. Una revisión genérica no permite solicitar cualquier regla.
**Integridad del SQL:** se reconstruyó la función desde `pg_get_functiondef` tras identificar y corregir una interpolación de reemplazo de texto que alteraba la primera versión propuesta; la versión que exige CI es la reconstruida.

La migración conserva las funciones `decide_batch/apply_batch`; solo endurece `request_v1` para admitir el recibo del Step70 existente con: `PASS_INDEPENDENT_SEMANTIC`, `INDEPENDENT_SEMANTIC_REVIEW`, `reviewer_is_producer=false`, `producer_independence_proven=true`, `model_call_count>=1`, hashes y `unsupported_claims=[]`; también Step60 PASS. No introduce modelo externo, worker, Gate2 manual ni otro paso.

Un recibo actual `CURRENT_CONTEXT_REVIEW` con `model_call_count=0` devuelve `PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED` y **no crea solicitud**. El runtime nativo actual **no acredita un segundo juez independiente** por defecto: dependencia externa **NO-GO**. No se permite escribir en Step70 PASS inventado ni rellenar flags manualmente.

## Aprobación y efecto
La ruta actual exige `p_decided_by` textual con prefijo `HUMAN:`; esto **no prueba** un actor humano autenticado. La aprobación final en lote requiere binding de identidad real del owner antes de producción. Mientras `identity_mode` permanezca `UNVERIFIED_CHAT_DECLARATION`, **NO-GO** a la aplicación productiva, aun con tests sintéticos verdes.

Solicitud: solo regla CANDIDATO, perfil autorizado, razón no vacía, snapshot SHA y sin solicitud pendiente. Aprobación: `decide_batch`; efecto: `apply_batch`; trigger `lf_rule_promotion_guard_v1` y snapshot de reglas impiden `VIGENTE` sin aprobación. No promocionar masivamente para compensar ausencia de juez.

## Resultado exacto de elegibilidad documental
Archivo: `docs/rule-promotion/lf_candidate_verdicts_reconstructed_20261114.json` — SELECT actualizado después de #3896; 166 reglas, 0 PASS, 166 HOLD **bajo evaluación reconstruida**, no recibo de función oficial. Razones superpuestas: `USED_BY_ENOUGH_SCREENS` 148, `NO_PENDING_MARKER` 66, `NO_PENDING_DECISION` 57 y `HAS_STATED_REASON` 3. `NO_DUPLICATE_ACTIVE_RULE` 0 bloqueos según el criterio exacto de configuración. El umbral de 5 pantallas es el parámetro default **técnico de esa función**, no Q12 (5 sin control/unidad).

## Pruebas
PG17.6 y PG18.7 sobre fixtures del código SQL real: (a) revisión mismo contexto, 0 llamadas → request bloqueada; (b) evidencia *simulada* independiente permite solicitud PENDING, pero no aplica hasta paso humano; (c) actor `BOT:` rechazado; (d) lote `HUMAN:OWNER_FIXTURE` aprueba/aplica SOLO en fixture; (e) ROLLBACK restituye candidato/0 solicitudes; (f) deriva de preimagen bloquea. No confundir fixtures de prueba con modelo real, aprobación del owner, producción o permisos RLS verificados.
