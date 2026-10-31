# Análisis — RUN canónico A1–A9 con contexto de negocio (source-only)

Estado: **CANDIDATE / NOT_WIRED / NO_RUNTIME_ACTIVATION**. Rama aislada, sin SQL, despliegue ni autorización PG-01. Los cambios del PR solo afectan al binding candidato LF y al preflight; no habilitan SALY. Alcance aprobado: reutilizar el RUN de EJECUCION_PERFIL_LF e identificar cómo conservar la evidencia de Análisis.

## Autoridad y flujo

1. ACT-0001 clasifica y emite un handoff válido; **no reserva un RUN en cada consulta**.
2. \`public.lf_profile_execution_begin_from_handoff_v1\` valida handoff y delega en \`public.lf_profile_execution_begin_v1\`, que llama \`public.fn_lf_operation_reserve_execution_v1\`. La clave idempotente hace \`RESERVED_NEW_EXECUTION\` o \`REPLAY_EXISTING_EXECUTION\`.
3. Se conservan los once pasos transversales: \`init_execution, router, profile_resolve, profile_source_read, input_validate, context_admission, research_baseline_freeze, execute_profile, output_validate, semantic_judge, report_output\`.
4. El paso \`input_validate\` invoca Input Governance **solo cuando aplica**; puede reutilizar un RUN IG vigente o generar uno propio, referenciado desde el \`execution_id\` principal. No hay reingreso al Router por recuración.
5. Los pasos funcionales internos **A1–A9** pertenecen al perfil Análisis, no al Router ni a la definición transversal de once pasos. Deben producir recibos persistidos por la operación o su recorder autorizado, vinculados con el **mismo** \`execution_id\` y \`request_sha256\`.
6. \`stage_trace\` declarado por el LLM en el JSON final **no equivale** a nueve pasos materialmente recorridos. Un recibo propio del modelo jamás satisface por sí solo el paso.
7. Contrastar recibos por etapa, SHA exactos de la fuente A1–A9, currentness, RAW, juez independiente y eventual readback PG-01 antes de declarar cualquier READY.

## Parámetro obligatorio de negocio (`business`)

- **Variable canónica**: `business`, provista por ACT-0001 en `router_profile_handoff.business` y vinculada al mismo `execution_id`; **sin valor por defecto** y sin deducirla de palabras sueltas o tablas.
- El RUN conserva `business` en su manifest/contexto; las evidencias A1–A9 y RAW deben ser congruentes con el negocio del handoff. El preflight acepta la identidad exacta `execution.business == router_handoff.business == binding.business == stage_readback[].business == model_readback.business`.
- **LF (configuración del PR)**: el contrato candidato `profiles/programming_analysis_lf/contracts/analysis_source_binding.json` declara `business=LF` y `business_source_namespace=lf_ops`. Esto es un límite de alcance, no una autorización runtime. Las fuentes de pantalla/reglas se resuelven únicamente desde autoridades LF vigentes.
- **SALY (fuera del alcance de activación)**: Supabase contiene esquema `saly`, pero sus tablas/consultas/autoridades aplicables a Análisis **no están verificadas ni vinculadas** al Router/profile runtime actual. El preflight rechaza SALY cuando se le pasa binding LF o binding SALY sin estado de autoridad `CURRENT_RELEASED`; no consulta ni interpreta `lf_ops` como respaldo.
- El Router `public.lf_router_profile_execution_handoff_v1` verificado en vivo actualmente exige `p_business='LF'`; **este PR no cambia esa política**. Para SALY futuro, el owner del Router deberá proporcionar soporte gobernado, manifest/authority de negocio y perfil/capacidad aplicable antes de iniciar RUN.
- Las funciones SQL, selecciones de pantallas y consultas son responsabilidad de los resolvers/adapters canónicos específicos del negocio; nunca `if business=='SALY': usar tabla inventada`. No introducir segundo Router, segundo RUN, lógica global acoplada a `lf_ops`, ni fallback cruzado.

**Control negativo obligatorio**: petición SALY + binding LF, consulta/table source LF, `business` perdido o alterado durante el recorrido, o binding SALY sin currentness/autorización: `BLOCKED` antes de inferencia, sin declarar READY.

## Dos numeraciones diferentes

| RUN externo \`EJECUCION_PERFIL_LF\` | Interno Análisis |
|---|---|
| 00 init_execution; 10 router; 20 profile_resolve; 30 profile_source_read | A1 / paso funcional 10 (comprensión) |
| 40 input_validate; 45 context_admission; 47 research_baseline_freeze | A2–A8 / pasos funcionales 20–80 |
| 50 execute_profile | A1–A9, materializados y trazados bajo este RUN; no nueve RUN nuevos |
| 60 output_validate; 70 semantic_judge; 80 report_output | A9 / paso funcional 90 (handoff; no PG-01 automático) |

## Preflight de contrato — NO es una integración

\`profiles/programming_analysis_lf/evals/analysis_stage_receipt_preflight_v1.py\` verifica estructura y vínculo interno de un **paquete armado de readbacks**. \`test_analysis_stage_receipt_preflight_v1.py\` contiene controles positivos y negativos. Incluso un positivo devuelve solo \`STRUCTURAL_CANDIDATE_ONLY\` y \`operational_ready=false\`: referencias autodeclaradas no son autoridad independiente.

## Evidencia de fuentes, 31-10-2026

Git \`main\` inspeccionado: \`7b9cf78fbccfea5992174cd66d311858f9cb5af1\`. Los nueve Git blob SHA de \`contracts/analysis_source_binding.json\` coinciden 9/9 con las fuentes de main. **Existencia y coincidencia de blob NO prueban currentness externo, consumo del modelo ni RUN operativo.**

EKB: \`PROGRAMMING-ANALYSIS-STAGE-SOURCE-ATTESTATION-GAP-001\`, \`PROFILE-RUNTIME-GOVERNED-STEP-BYPASS-001\`, \`PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001\`, \`PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001\`.

## Pendientes de implementación en su dueño canónico

- Registrar/autorizar el activo \`PERFIL-PROGRAMMING-ANALYSIS-LF\` en las capas gobernadas, sin activarlo en producción.
- Conectar **un recorder existente** a cada checkpoint A1–A9; investigar el soporte de readback preciso antes de elegir almacenamiento. No insertar falsos recibos ni sobrecargar el RUN transversal con pasos universales A1–A9.
- Corregir vínculo real Router/run/modelo de la cola que hoy puede omitir la operación gobernada; readback antes de inferencia.
- Implementar un comprobador independiente que lea cada recibo desde su fuente (no solo acepte URIs), verifique currentness/issuer/identidad/digest y evalúe utilidad del resultado.
- Ejecutar 3 casos reales en no-producción con positivos y negativos, y PG-01 solo cuando corresponda. No declarar A16Q_C2/C3 DONE por un test local.

No merge ni paso a producción hasta revisión de los contratos, tests y prueba del consumidor real.