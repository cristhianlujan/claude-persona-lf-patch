# LF — Interruptores independientes PG-01→PG-14 (laboratorio)

**Alcance:** exclusivamente pruebas sintéticas aisladas, en la misma pila draft de Programación. No se modifica `main`, Supabase, Análisis, Testing real, controles de GitHub ni autoridad SUPER_ADMIN.

## Usar el panel

Abra `lf_pg_switchboard_v1.html` en su navegador. Cada etapa PG-01…PG-14 y cada uno de los **78 C1…Cn visibles** tiene su propio selector.

- `ON`: **simular** la evaluación del checkpoint con el fixture SOL-TEST-001; nunca equivale a un PASS real.
- `OFF`: **omitir** exactamente ese checkpoint en modo diagnóstico; registra `BYPASSED_DIAGNOSTIC` (nunca `PASS`) y deja explorar etapas posteriores sintéticas.
- `FAULT`: inyectar una falla artificial `BLOCKED_SYNTHETIC`; los siguientes quedan `NOT_REACHED`.
- El selector de checkpoint prevalece sobre el de etapa. «Todos ON» y «Todos OFF» son **atajos opcionales**, no un switch global obligatorio.
- Exportar/importar JSON de switches y exportar traza con todos los checkpoints.

El panel HTML es independiente y visual; **no ejecuta Python ni módulos del agente**. Su objetivo es jugar con combinaciones de estados para visualizar el camino y los bloqueos.

## CLI reproducible del sandbox

Desde la carpeta `switchboard`:

```bash
python3 lf_pg_switchboard_v1.py --stage PG-08=OFF --checkpoint PG-09_C1=ON --output trace.json
python3 lf_pg_switchboard_v1.py --checkpoint PG-11_C3=FAULT --output trace_fault.json
python3 lf_pg_switchboard_v1.py --all OFF --checkpoint PG-14_C3=ON
python3 lf_pg_switchboard_v1.py --config lf_switchboard_config.json --output trace.json
python3 -m unittest -v test_lf_pg_switchboard_v1.py
```

### Segunda capa opcional de tests existentes

Para lanzar las pruebas de productores candidatos que ya existen en el checkout de GitHub **solo para etapas completamente ON**:

```bash
# desde la raíz del checkout de LF
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/switchboard/lf_pg_switchboard_v1.py \
  --stage PG-08=OFF --run-tests --repo-root . --output /tmp/lf_switchboard_trace.json
```

Para PG-04…PG-14 el runner reconoce las suites existentes por carpeta; si falta la suite o se ha apagado cualquier Cx de la etapa, la reporta `NOT_RUN`. PG-01…PG-03 aún no tienen suite conectada **a este switchboard**. Los tests candidatos pueden reconstruir fixtures de sus predecesores aunque su etapa previa esté OFF: ese hecho no valida retrospectivamente la etapa omitida. Esta opción **no ejecuta** los scripts opt-in de PostgreSQL ni el mutador de Git, y **no es** un E2E gobernado.

## Reglas de seguridad / semántica

1. Toda salida tiene `production_authority=false`, `handoff_allowed=false`, `checkpoint_closure_allowed=false` y `testing_real_invoked=false`.
2. Se rechaza el modo `REAL_GOVERNED` y cualquier fixture con `analysis_ready_authentic=true`.
3. Un bypass solo afecta a la simulación. Nunca desactiva una guardia del runtime ni de la rama principal.
4. Los SHA-256 de traza sirven para comparar configuraciones; no representan recibos oficiales, firma de juez ni persistencia auténtica.
5. **78 interruptores visuales** son C1…Cn derivados de la ruta técnica, no los **89 registros de Supabase**.
6. El estado PG-01→PG-14 técnico de los PRs existentes no se modifica. Este laboratorio es una capa nueva aislada.

## Criterio de auditoría

La suite `test_lf_pg_switchboard_v1.py` contiene 10 casos, entre ellos: etapa OFF+continuación, checkpoint ON dentro de etapa OFF, FAULT+stop, todo OFF sin autoridad, bloqueo de modo real y rechazo de estado falso de Análisis.

**Estado del nuevo PR:** código y tests preparados. La calificación independiente del nuevo HEAD aún está pendiente, aunque el prototipo local equivalente ya se ejercitó con 9/9 checks; no confundirlos con los 10 tests publicados aquí.
