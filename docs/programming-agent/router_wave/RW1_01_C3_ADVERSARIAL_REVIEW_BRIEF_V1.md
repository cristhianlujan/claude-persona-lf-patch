# RW1-01_C3 — Paquete de revisión adversarial (PREPARADO, NO INDEPENDIENTE, NO DONE)

**OLA:** `LF_ROUTER_ARCHITECTURE_WAVE_V1` · `RW1-01_C3` · 2026-10-17.  
**Autoría:** revisión de preparación por el mismo agente que asistió C2; **no constituye juicio independiente** ni satisface el requisito de separación de evaluador.  
**Fuentes congeladas:** C1 `89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d`, C2 `58884d37d74f1c784dfb5920ed2ac548781bfe18`, validador C2 `2605fc675448104f69deef8a27210fc0047ea6fb`, todas verificadas en `main`. Fuente de autoridad de C1/C2: Supabase checkpoint 1607/1608 DONE; C3 1609 PENDING.

## Pregunta de C3, sin suponer que C2 falló

¿Es suficiente la matriz de necesidades y sus oráculos para comparar diseños futuros sin favorecer una solución, crear falsos READY, olvidar exclusiones/contextos o confundir forma con ejecución? C2 fue una validación **del artefacto y de sus 15 negativos del verificador**, no de las 30 rutas del Router. No se reabre C2 ni se cambia el baseline aprobado sin decisión de C3.

## Riesgos reproducibles que deben refutarse

El archivo `sandbox/lf_contract_gate_test/router_wave/validate_rw101_c3_adversarial_gaps_v1.py` importa el **validador Python exacto de C2** y construye nueve respuestas que admiten forma correcta pese a información ausente. La ejecución en CI del test separa `REPRODUCED_SHAPE_LIMITATIONS` de un PASS del Router: demostrar que el verificador admite una respuesta insuficiente **no significa** que el Router haya emitido esa respuesta.

| Falsificador | Casos | Qué falta acreditar | Cambio de diseño que **no** queda autorizado |
|---|---|---|---|
| F01 / F02 | R07 y R09 | «sin tocar autenticación» y «no cambies permisos» como exclusiones **estructuradas**, no mera cadena literal | Parser de palabras clave específico por frase |
| F03 | R04 | Que la simulación permanezca sin efecto antes de cualquier consumidor, incluso si aparece target positivo | Prohibir DEMOS o simulaciones |
| F04 | R17 | Que el contexto anterior pertinente haya sido efectivamente recuperado/ligado | Preguntar de nuevo datos disponibles |
| F05 / F06 | R20 y R22 | Coherencia entre fixture de capacidad no resuelta y permiso de `DERIVE`/`COMPOSE` | Obligar todo tipo futuro a un solo ejecutor |
| F07 | R10 | Responsabilidad material para **regla y skill**, no solo etiquetas de dos objetivos | Crear segundo Router o ejecución multi-agente siempre |
| F08 | R27 | Identidad del competente para **verificar** permiso, separada de activación en producción | Prohibir investigar o preguntar sobre producción |
| F09 | R08 | `authority_evidence_ref` verificado contra autoridad/currentness real; texto arbitrario no es recibo | Hacer que el Router ejecute comprobación de todo el dominio |

Además falta evaluar realmente N11: R30 etiqueta «misma fuente/snapshot», pero `check_result()` no compara dos ejecuciones, hash ni decisión posterior; N12 solo está enlazada a casos, sin métrica de complejidad/rendimiento. Esto **no implica** que estas medidas deban migrar al Router; hay que decidir quién mide cada frontera.

## Criterio de refutación del evaluador independiente

Un juez separado del productor debe:
1. Revisar **primero** C1 y corpus C2 congelados, más su rúbrica, **sin leer la presente tabla de hallazgos ni la preinvestigación #2880**. Registrar su primera lista RAW y referencias SHA, para evitar inducir la crítica.
2. Intentar demostrar que se cubren realmente N01–N12, clasificar cada requisito **testable/exploratory/ambiguous/unsupported**, distinguiendo el contrato del Router (derivar) y el contrato del ejecutor (efecto).
3. Proponer al menos un holdout **nuevo no usado en C1/C2**, sus restricciones y oráculos falsables, sin reutilizar códigos o frases de los 30; no elegir arquitectura A/B/C/D.
4. Revisar luego este informe, contrastar los hallazgos F01–F09 con ejecución Python y rechazar los que confundan ausencia de autoridad en un fixture con obligación de autoridad dentro del Router.
5. Emitir `PASS`, `REVISE` o `INSUFFICIENT_EVIDENCE` con defectos materiales y remediación **transversal mínima**, no parche por caso. Guardar autor/ejecución/RAW/procedencia y un recibo independiente separado del productor.
6. **C3 no puede cerrarse** con autodeclaración de independencia, texto sintético, `fixture://`, un resultado `shape_only`, o un archivo creado por el mismo productor. La transición canónica exige evidencia de autoridad, condición positiva y negativa y readback después de Merge Train.

## Separación de expectativas

- La matriz C2 seguirá siendo baseline congelado para comparar arquitecturas; hallazgos se mantienen en registro C3 aparte.
- C3 critica sesgos/omisiones, **no** exige que ACT-0001 ya apruebe 30 casos ni consumer E2E (eso es RW1-05/06).
- No crear un segundo juez/motor persistente. Un GPT Native en conversación realmente distinta o juez humano competente debe ver el paquete ciego; si esa separación no puede verificarse, dejar `INDEPENDENCE_NOT_PROVEN`.
- El programa mantiene RW1-01_C3 como PENDING hasta recibir y validar el juicio externo; RW1-02 solo puede conservar preinvestigación no oficial mientras no exista su dependencia.
