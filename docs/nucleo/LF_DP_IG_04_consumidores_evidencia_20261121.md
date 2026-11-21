# DP-IG-04 — Evidencia de consumidores y dependencias externas (PARCIAL)

Decisión de Cristhian 2026-11-21 13:49 Lima (18:49 UTC): no esperar a Paulo, avanzar lo posible sin él. D8 permanece aprobada: desacople de datos/lógica legados; IG skill opcional y hallazgos reportados, conservar EKB, Step50 y hashes de procedencia. No redirigir consumidores reales, cambiar ACL, ejecutar perfiles, activar Edge, publicar reglas o retirar controles. DP-IG-03 #4556 / 9404474f5435b9394005058ae584b93ddf8a19af / Train 44928649880 cerrado. Fuente repo 08360ba89306c7592f354d7ce5ca4b8e3c67f0b1. EKB preflight focal revisada: LF-NUCLEO-A4-DIRECT-LEGACY-READER-CI-20261121-001 RESUELTO; LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001 ACTIVO; LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001 ACTIVO; LF-IG-SKILL-FAILED-STEP40-FINDING-20261114-001 ACTIVO; LF-PROFILE-STEP80-IG-CLEARANCE-OMITTED-20261116-001 CANDIDATO; PROFILE-CREATOR-EKB-PREFLIGHT-MERGE-ORDER-005 y PROFILES-EKB-PREFLIGHT-OMISSION-001 activos. No corregir ni duplicar hallazgos por diagnóstico. Fuente operativa de proyecto V1.4 (CANDIDATO VERIFICADO PARCIALMENTE), contrastada contra catálogo y recibos reales.

## 1. Evidencia operacional, corte desde 2026-11-14 UTC

98 RUN EJECUCION_PERFIL_LF, 91 con registros de steps 40/45/50/60/80 (378 registros). 167 payloads citan lf_ops.reglas_pantallas, no necesariamente 167 llamadas. 0 contienen referencia con los nombres exactos del canon/compat nuevos; 0 RUN iniciados desde merge DP-IG-03 (17:12:11 UTC). La ausencia de recibos no prueba ausencia universal de ejecución. No certificar adopción del contrato por perfiles. No confundir LF_PRODUCT_CANONICAL_RULE_READ_V1 (nombre histórico del paquete) con nucleo_reglas_efectivas_v1. Los RUNs se distinguen de los hits por paso. Registro LF reciente:

| Perfil | RUN / con steps | Estado de RUN | Hits producto / enlaces / screen contract / skill IG | Prueba sin Paulo |
|---|---|---|---|---|
| PERFIL-PRODUCT-DIRECTOR-LF | 84 / 77 | 42 COMPLETED, 30 IN_PROGRESS, 12 ABANDONED | 73 / 156 / 75 / 7 | Sí: recibos step45 y lectura comparativa SQL. E2E futuro por Router gobernado, no ejecutado. |
| PERFIL-QUALITY-PACK | 1 / 1 | 1 COMPLETED | 1 / 1 / 1 / 0 | Sí: paquete y proyección SQL. No afirmar que consume la nueva puerta. |
| PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | 6 / 6 | 4 COMPLETED, 2 IN_PROGRESS | 4 / 5 / 4 / 0 | Sí: recibo step45 y RAW existente en step50; no repetir efectos del reparador. |
| PERFIL-UI-ARCHITECT | 7 / 7 | 3 COMPLETED, 4 IN_PROGRESS | 4 / 5 / 4 / 3 | Sí: contexto SQL y recibos; IG BLOCKED registrado, no reanudar RUN. |

Muestras inmutables: tabla public.lf_operation_execution_steps, step45 salvo indicado.
- Product Director EXEC-PROFILE-GATE2-8B455BD3FABBC952FFD3CB43, COMPLETED, supabase://public.lf_eventos/22182#context_receipt, md5 payload c2654e4d925c8ab9cc9f7ba965d43f17.
- Quality EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C, COMPLETED, evento 21888, md5 130394a03fec21ddd30f041a33b8240d.
- Reparador EXEC-PROFILE-GATE2-4E7A86DAECA05A09424BA1D1, IN_PROGRESS, evento 21903, md5 ec2ea2ff6aa007987db35cc80bd441cc; EXEC-PROFILE-GATE2-95968F50D6214EADB117E45E COMPLETED, step50 actions run 43819250112 artifact profile-native-output, md5 c08e5dc2aacb5a42ae193ad0fe477d88.
- UI EXEC-PROFILE-GATE2-8F4491E640E7D8D12FDFB539, IN_PROGRESS, evento 22210, md5 2c3d7e3344657de79c237adb641ab3e6; EXEC-PROFILE-GATE2-DB23CE4D9324F04A8E2709DF COMPLETED, evento 22201, md5 c283280b61def8525222d2a9994b11d8.
Status STEP_PASS_WITH_EVIDENCE en las muestras; no sustituye evidencia terminal READY. 10 invocaciones skill IG históricas: Product 4 BLOCKED (SKILL_IG_RUNTIME_ATTEMPTS_EXHAUSTED_AS_FINDING), 2 FAILED (SKILL_HANDLER_ERROR), UI 4 BLOCKED mismo código. Ejemplo UI RUN-2F8C5C6C009B32F37EFA parent 8F449... y RUN-C2DFF563836831863F4D parent DB23...; Product RUN-43B37AB32F6DC470A5BE parent EXEC-PROFILE-GATE2-19E9D70E1FEC2684C4999CED. Readiness 957–961 BLOCKED (pantalla 52); 952 COMPLETED pantalla 51, 2026-11-14; status no equivale a currentness. No llamar ejecutor IG ni reparar estos RUNs.

## 2. Resto de perfiles actuales: sin RUN reciente, no consumidores acreditados

8/8 fuentes GITHUB_SKILL recuperadas por su SHA registrado y blob exacto; ningún token de puerta nueva. 2 RAW consultados, sin token, digest registrado sin recalcular. Los 6 restantes con cero ejecuciones en ventana:
| Perfil | Fuente exacta (ruta/ref, blob registrado) | Qué se puede probar sin Paulo |
|---|---|---|
| ACT-0051 | profiles/frontend_prototype_architect_lf/SKILL.md @33684cc36e6ca0a7d74e3d547fce50898a16f0a5; cc1ac8c6d0455c1b9d9e225e5e1382a084be6cd4 | Descriptor y selector SQL; falta RUN si aplica. |
| PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING | profiles/customer_financial_ux_decisioning/SKILL.md @33684cc3; 8729433b02b0905da0ea29f94073144273ee5b88 | Igual. |
| PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531 | public.lf_activos.raw_payload por código; sha256:468721d2388d54e902b0c8b0072e553abca61873c7ce39c7dfd28afd802f2f2d | RAW y descriptor, falta ejecución. |
| PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF | profiles/evidence_lineage_reviewer_lf/SKILL.md @33684cc3; 2acf40bb9130a76a1b8cf3dc5a71dae1f0da0b3c | Descriptor y selector SQL; falta RUN. |
| PERFIL-GAMIFICATION-SYSTEM-ARCHITECT | profiles/gamification_system_architect/SKILL.md @33684cc3; 09deca7a98efaa1efb836a53b087eecaa4d805ce | Igual. |
| PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531 | public.lf_activos.raw_payload por código; sha256:78f2d6fe1f9edf522eea7ea88c68baeb949745e649ac3a512a73e199648f6589 | RAW y descriptor; falta ejecución. |

No pedir a Paulo datos internos ya disponibles en Supabase. Estas verificaciones son posibles sin él por la ruta gobernada; no reproducir nuevos RUN aquí porque el alcance del lote es solo diagnóstico y no modificar lectores.

## 3. Funciones: consumo estático vs probado

pg_proc.prosrc con nombres de contrato: 11 funciones (LF 6 incluyendo adaptador, SALY 4, public 1). LF: lf_nucleo_lectura_transicion_v1, lf_puente_autotest_v1, nucleo_autotest_cambio_v1, nucleo_cola_trabajo_v1, nucleo_contrato_verificar_v1, nucleo_regla_proponer_v1. SALY: nucleo_autotest_cambio_v1, nucleo_cola_trabajo_v1, nucleo_contrato_verificar_v1, nucleo_regla_proponer_v1; public.lf_nucleo_autotest_conjunto_v1. Ningún perfil/IG lector aparece como consumidor directo. La búsqueda incluye referencias internas y tests; no demuestra llamada operacional. GitHub code search coincide en migraciones/diagnósticos/tests; no prueba ausencia de código externo. pg_stat_statements visible: postgres 47 entradas/47 calls y supabase_read_only_user 20 entradas/24 calls al corte de consulta; sin correlación de request/RUN, incluye auditorías/DDL propios, no se atribuye a consumidores. No se reinician estadísticas ni se exponen textos de otras consultas.

| Ruta comprobable | MD5 actual | Acción posible sin Paulo / pendiente |
|---|---|---|
| public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb), step45 | 9302760ee29525f02832c628eed397d7 | DATO: DIRECTAS y CONTRATO_PANTALLA; SQL comparativo por pantalla ya DP03. Recibo observado. |
| lf_ops.fn_screen_contract_v1(text,text,text) | 4407d40bb6d6d913b4d9ee72399d6f55 | DATO: 42 contratos; preserva semántica directa+global; 16 sin contrato. |
| programacion.fn_input_effective_rule_links_v1(integer,text) | 156247a925d74c6f4accd7a6d2508489 | DATO: IG_EFECTIVAS, selector vigente; no llamarlo como escritor. |
| public.lf_input_family_catalog_context_v1(integer) | 0efbaa02411e52b0c4e0ab83c3ac20e8 | MIXTA: cobertura/datos y evidencia. Prueba de proyección separada, sin retirar control. |
| public.lf_input_family_reuse_claims_gate_v1(integer,jsonb) | f0e41d043a695f414a536b4aad5f13a8 | CONTROL: no modificar; futuros positivos/negativos aislados. |
| programacion.fn_input_governance_execute(integer,text) | 68a6a5466ed40a06d673eb1cffc24ec2 | MIXTA; metadata y recibos disponibles, no invocar RPC con efectos; E2E autorizado pendiente. |
| programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint) | c8767ab3b931a84752d5a25ff12ecd4e | CONTROL conservar. |
| programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint) | 0f43271e2d42cfe461ef1797d2cc9e6c | CONTROL procedencia conservar. |
| public.lf_profile_step50_rule_snapshot_v1(text) / effect_guard_v1(text,jsonb) | 7bd1e3d1b29d3839fe7bc6d5c599a985 / 23128b6e12c302358a40b47830b38ae0 | CONTROL conservar. |
| public.lf_skill_h_input_governance_context_pack_v1(jsonb) | e20544acc09117d97d642f323ec94b54 | CONTROL/transportador opcional; hallazgos persistidos, no acreditar éxito. |
| lf_ops.lf_nucleo_lectura_transicion_v1(integer,text,text) | 8c0e417f6cbc8d5ba3ddd20496067a7a | Diagnóstico disponible y probado; service_role/anon/authenticated sin EXECUTE. No abrir ACL ni redirigir ahora. |

El núcleo original por nodo/fecha y vista compat siguen intactos. DP03 probó paridad actual 58/58 DIRECTAS,58/58 IG_EFECTIVAS,42/42 CONTRATO_PANTALLA; mixto pendiente. No confundir esos tests con ejecución real de perfil.

## 4. Edge (código desplegado recuperado, no solo metadata)

list_edge_functions: 39 en total. Cuatro componentes focales ACTIVE. get_edge_function devuelve código fuente y SHA de paquete, comparado archivo TypeScript exacto contra repo 08360ba89306c7592f354d7ce5ca4b8e3c67f0b1: 11 archivos entregados incluyendo repetición de shared, todos iguales; ninguno contiene tokens del contrato nuevo. No se prueba endpoint llamándolo ni se exponen tickets/secretos. private.lf_edge_function_deployment_evidence_v6 no tiene filas focales; la evidencia es API de gestión y comparación de código, no recibo V6. Rutas conocidas:
| Edge / versión | Ruta de código / blob (principal) | RPC / acción y verificación |
|---|---|---|
| input-governance-agent-v1 / 20 | supabase/functions/input-governance-agent-v1/index.ts, 61ac4022000cbe9685b7bd728d522b2148affff9 | líneas 95,128,201 fn_input_governance_execute con ticket. SHA paquete 55518749847e1303c62f74a8c51c140fef125838296087c20411d1262cdf6369. |
| input-governance-curator-v1 / 16 | supabase/functions/input-governance-curator-v1/index.ts, 7686a463f933e7aa756ae824bc9b2e7c05e45158 | 67 materialize,81 handoff receipt. SHA 96369da9d3bccd233a649c3132557c2b47e90b3514b9aa5bf6f8838d1d8b8efe. |
| input-governance-validator-v1 / 21 | supabase/functions/input-governance-validator-v1/index.ts, 234f4d6267fcbaf4683b9d600e569fc705d75695 | 11–12 handoff assert/validate,90 resume. SHA bc1b1cc106bd8b52ec02b4104745d7953af0fa13e9a2bbb7fa704abc17931be9. |
| lf-profiles-governance-caller-v1 / 106 | caller.ts, e3de51c339b968b1aadebdaca1637c157b6fef46; index.ts cbd2c58eadc586f49755361dd5e5602f6f9d0088; cp2_edge_bridge.ts 43b94b67cda67b46b4e4f37d317c9458fbce2ba8; profile_continuation.ts c019fbc16c9d9679636a29be721b8cc25af5ee80 | acción input_readiness_context_pack_runtime_v1 líneas 15,647; SHA ab95b8835f8a2055b11245748d7b480507d7acdfd193023fd0f2d8b6b5b57c2a. |

shared lf_ig_transport_guard_v1.ts blob 7bd4b23eb8a2352739835799702fb1655f4f3c71, idéntico en las cuatro. Endpoint estándar /functions/v1/{slug} derivado del mecanismo Supabase, no verificado con petición activa. Se puede preparar prueba autorizada por Router/OIDC en infraestructura existente sin esperar a Paulo; no se ejecuta en este lote. No se sustituye ticket por acceso directo.

## 5. Dependencias reales que faltan y no deben bloquear la otra fase

- Worker Hetzner: services/profile_runtime_api/scripts/hetzner_queue_worker.py blob af4777616aab6c1c0eefaab380c3d50ad780c233 línea 673 invoca public.lf_profile_execution_channel_context_v1. private.lf_profile_runtime_queue_v1 sin filas en ventana. Código repo sí, despliegue real no identificado. Si Paulo administra ese runtime: pedir **nombre del servicio/imagen, commit desplegado o digest OCI, endpoint interno/ruta exacta, método/autorización (sin secreto), identificador de request y evidencia correlacionada de SELECT/RPC y respuesta**. No pedir cambios ahora ni asumir necesario para los perfiles GPT_NATIVE.
- Aplicaciones cliente/backend ajenas a este repo: pedir a Paulo repositorio y SHA desplegados, archivo y líneas de lectura de reglas, endpoint/RPC y versión, identidad/rol de acceso no secreto, ejemplo request/response no sensible, correlación de llamada, positivo/negativo y evidencia de despliegue. No se conoce endpoint exacto, no inventarlo. Los bindings de hechos por producto se mantienen aparte.
- Para consumidores internos: falta un RUN nuevo autorizado por receptor con recibo de consumo del contrato, permisos de runtime (adaptador solo lectura diagnóstico), paridad mixta al coexistir versiones publicadas/legadas. No redirigir ni ampliar permisos por este documento. Se puede preparar/evaluar en otra fase; las trazas existentes no bastan. DP-IG-04 **PARCIAL**, no cerrado. DP-IG-05 no iniciado. No confundir falta de evidencia externa con bloqueo de trabajo F4. Tablero 70/100, DP-IG 3/5 (60%); sin punto adicional. Decisión 13:49 registrada. Ningún cambio de DB, EKB, IG o perfiles en este PR.

## 6. PG17 real READ ONLY/ROLLBACK — evidencia reproducible

{"pg_version":"17.6","runs":98,"steps":378,"runs_with_steps":91,"after_dp03":0,"new_refs":0,"legacy_refs":167,"tests":12,"passed":12,"failed":[]}. 12/12; pruebas positivas/negativas del clasificador exacto, invariantes del contrato y evidencia presente. No prueba E2E.
```sql
BEGIN READ ONLY;
WITH runs AS MATERIALIZED(SELECT execution_id,target_code,status,started_at FROM public.lf_operation_execution WHERE operation_code='EJECUCION_PERFIL_LF' AND started_at>=timestamptz '2026-11-14 00:00:00+00'),
steps AS MATERIALIZED(SELECT s.execution_id,r.target_code,s.step_order,s.status,s.evidence_payload::text payload FROM runs r JOIN public.lf_operation_execution_steps s USING(execution_id) WHERE s.step_order IN(40,45,50,60,80)),
fixtures(label,source,expected) AS(VALUES ('positive_adapter','{"source_ref":"lf_ops.lf_nucleo_lectura_transicion_v1"}',true),('positive_native','{"source_ref":"lf_ops.nucleo_reglas_efectivas_v1"}',true),('positive_compat','{"source_ref":"lf_ops.v_reglas_compat_v1"}',true),('negative_legacy','{"source_ref":"lf_ops.reglas_pantallas"}',false),('negative_similar','{"source_ref":"lf_ops.v_reglas_compat_v10"}',false),('negative_ig','{"skill":"INPUT_GOVERNANCE_CONTEXT_PACK"}',false)),
checks AS (
 SELECT label, (source ~* '\m(lf_nucleo_lectura_transicion_v1|nucleo_reglas_efectivas_v1|v_reglas_compat_v1)\M')=expected AS ok FROM fixtures
 UNION ALL SELECT 'readonly',current_setting('transaction_read_only')='on'
 UNION ALL SELECT 'native_hash',md5(pg_get_functiondef('lf_ops.nucleo_reglas_efectivas_v1(text,timestamptz)'::regprocedure))='6a7f47636bb1150d650d61214d93152b'
 UNION ALL SELECT 'adapter_hash',md5(pg_get_functiondef('lf_ops.lf_nucleo_lectura_transicion_v1(integer,text,text)'::regprocedure))='8c0e417f6cbc8d5ba3ddd20496067a7a'
 UNION ALL SELECT 'runtime_acl_not_open',NOT has_function_privilege('service_role','lf_ops.lf_nucleo_lectura_transicion_v1(integer,text,text)','EXECUTE') AND NOT has_function_privilege('anon','lf_ops.lf_nucleo_lectura_transicion_v1(integer,text,text)','EXECUTE') AND NOT has_function_privilege('authenticated','lf_ops.lf_nucleo_lectura_transicion_v1(integer,text,text)','EXECUTE')
 UNION ALL SELECT 'legacy_positive_observed',exists(SELECT 1 FROM steps WHERE payload ILIKE '%LF_PRODUCT_CANONICAL_RULE_READ_V1%' AND payload ILIKE '%lf_ops.reglas_pantallas%')
 UNION ALL SELECT 'negative_not_claimed_from_legacy',exists(SELECT 1 FROM steps WHERE payload ILIKE '%lf_ops.reglas_pantallas%' AND payload !~* '\m(lf_nucleo_lectura_transicion_v1|nucleo_reglas_efectivas_v1|v_reglas_compat_v1)\M')
)
SELECT current_setting('server_version') pg_version,(SELECT count(*) FROM runs) runs,(SELECT count(*) FROM steps) steps,(SELECT count(DISTINCT execution_id) FROM steps) runs_with_steps,
(SELECT count(*) FROM runs WHERE started_at>=timestamptz '2026-11-21 17:12:11+00') after_dp03,
(SELECT count(*) FROM steps WHERE payload ~* '\m(lf_nucleo_lectura_transicion_v1|nucleo_reglas_efectivas_v1|v_reglas_compat_v1)\M') new_refs,
(SELECT count(*) FROM steps WHERE payload ILIKE '%lf_ops.reglas_pantallas%') legacy_refs,
count(*) tests,count(*) FILTER(WHERE ok) passed,coalesce(jsonb_agg(label) FILTER(WHERE NOT ok),'[]'::jsonb) failed FROM checks;
ROLLBACK;
```
Consultas complementarias: agrupar public.lf_operation_execution por target_code,status; join public.lf_operation_execution_steps por execution_id; md5(evidence_payload::text); catálogo pg_proc/pg_get_functiondef; public.lf_skill_invocation_v1 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'; programacion.input_readiness_runs ORDER BY id DESC; public.lf_profile_selection_registry_v1 WHERE descriptor_status='CURRENT'; list_edge_functions/get_edge_function y comparación por SHA. No persistir payloads sensibles.
