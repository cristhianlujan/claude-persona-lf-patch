# PROGRAMMING_ANALYSIS_LF — Skill única de Análisis

**Registro verificado:** `public.lf_activos` ID **414**, `tipo_activo=SKILL`, `CANDIDATO / READ_ONLY / CANDIDATE_READ_ONLY`, ejecución `EXEC-DB-TRAIN-PR3589-20261105010000-R41963330970`. **Runtime NO habilitado.**

## Consumo
El perfil del Agente de Programación debe seleccionar y consumir **una sola skill** `PROGRAMMING_ANALYSIS_LF`; nunca A1 o A2 como skills separadas. El Router solo encamina, el perfil conserva autorización e identidad y el ejecutor autorizado es responsable de transporte/registro/readback. No incorporar motor paralelo ni servicio alternativo.

## Etapas internas y mejora incremental
- **A1:** `steps/a1/validators/run.py` normaliza solicitud y contexto `REQUEST_CONTEXT_V1`. Módulo candidato, no calificado operacionalmente. Interpretación en lenguaje natural espera un productor externo y un juez independiente con recibos reales.
- **A2:** `steps/a2/validators/run.py` consume un resultado A1 válido y señales tipadas aportadas externamente; **proyecta** las reglas L1/L2/L3 del contrato canónico `analysis_change_classification_contract_v1.json`, sin pesos ni heurística nueva. Devuelve candidato `ANALYSIS_CHANGE_CLASSIFICATION_V1`; `source_attested=false`, `next_step=null`. No resuelve identidad de especialista por su cuenta.
- **Puente local A1→A2:** `adapters/a1_a2_candidate_bridge_v1.py` permite pruebas determinísticas de continuidad, **sin** invocar el perfil, Router, juez o runtime. No equivale a transición operativa acreditada.
- **A3–A9:** contratos de investigación, impacto, decisión, implementabilidad, frentes, STOP y handoff referenciados; sin módulos conectados todavía.
- **A10–A15:** campañas de evaluación, adversariales, benchmark, remediación, holdout y freeze. Son **gates de calificación**, no pasos a ejecutar automáticamente en cada solicitud.

## Contratos y fronteras
El manifiesto de 15 pasos está en `contracts/analysis_skill_manifest_v1.json`. Las fuentes A1–A9 siguen siendo canónicas en `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_procedure_v1.json`. El puente A1→A2 solo trabaja con entradas estructuradas sin interpretación semántica pendiente. Si A1 devuelve `REQUIRES_SEMANTIC_REVIEW`, A2 se bloquea.

La profundidad L1/L2/L3 **no es permiso de ejecución**. Ausencia/contradicción de evidencia nunca autoriza READY ni A3. El perfil recibirá `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` con `PROGRAMMING_CONTEXT_SNAPSHOT_V1` solo tras integración/calificación de A1–A9, fuentes CURRENT, juez y recibos correspondientes.

## Bloqueos
- El registro de activo no demuestra runtime. Prohibido declarar `SKILL_READY`, `ANALYSIS_READY`, `SKILL_INTEGRATED` o efectos.
- A1/A2 son implementaciones locales candidatas; A2 no puede atestar la procedencia de señales por sí mismo ni autoproclamar juez independiente.
- A3–A15 aún no están conectados. A10–A15 conservan `requires=null` con `NOT_RECONCILED_FROM_CANONICAL_VALIDATION_SOURCE`: null significa **pendiente**, nunca que no haya requisitos.
- Reutilizar `EJECUCION_SKILL_LF`, políticas/Router y autoridad server-side existentes. No usar `supabase_read_only_user` para escritura ni `lf_record_creacion_skill_step_v1` para invocar pasos.

## Verificación
Pruebas del paquete: `python -m unittest discover -s skills/programming_analysis/evals -p 'test_*.py' -v`; A1: `steps/a1/evals`; A2: `steps/a2/evals`. No afirmar PASS de la nueva revisión hasta obtener evidencia CI o ejecución local real.
