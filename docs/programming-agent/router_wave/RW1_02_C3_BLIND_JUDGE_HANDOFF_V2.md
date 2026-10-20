# RW1-02_C3 — Handoff independiente V2

## Identidad
- Plan: `LF_ROUTER_ARCHITECTURE_WAVE_V1`
- Unidad: `RW1-02`
- Checkpoint: `RW1-02_C3`
- Work item: `1128`
- Asset: `ACT-0001`

## Freeze V2
Usar como fuente congelada:
- main: `fa6e679fc3df5ff2f9d67338aec4901a78c023c1`
- C1 baseline: `docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md`
- competencia V2: `docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json`
- validador V2: `sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v2.py`
- resultado productor V2: `docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V2.json`

Antes de RAW1 no abrir el resultado productor V2 ni el REVISE C3 anterior.

## Ejecución
1. Verificar blobs del freeze.
2. Recomputar desde competencia V2 + validador V2, sin usar el resultado productor.
3. Confirmar 36 casos, N01–N12, 4 candidatos y 3 elegibles.
4. Ejecutar al menos 24 mutaciones adversariales:
   - >=6 contra A;
   - >=6 contra C;
   - >=4 contra selección/tiebreak;
   - incluir B, D, neutralidad, autoridad, currentness, continuidad y no-claims;
   - >=2 falsificadores novedosos.
5. Distinguir:
   - paquetes semánticamente inválidos: deben ser rechazados;
   - variantes estructuralmente válidas: pueden cambiar hard-pass o ganador y deben aceptarse si el resultado se recomputa exactamente.
6. Congelar RAW1.
7. Solo después abrir resultado productor V2 y evidencia C3 anterior; generar RAW2 sin alterar RAW1.

## PASS
PASS requiere:
- freeze correcto;
- recomputación independiente;
- 36 casos y N01–N12;
- 4 candidatos / 3 elegibles;
- >=24 adversariales, >=6 A, >=6 C, >=4 selección, >=2 novedosos;
- cero paquetes semánticamente inválidos aceptados;
- cero variantes válidas rechazadas por un ganador/hard-pass hardcodeado;
- capacidades y métricas trazables al contrato estructurado;
- selección final sustentada;
- cero bloqueadores materiales;
- RAW1 intacto;
- sin inventar latencia/costo;
- sin claim de Router runtime ni producción.

Si existe defecto material reproducible: `REVISE`.
