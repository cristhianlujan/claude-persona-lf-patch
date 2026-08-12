# MAPA DE BRECHAS OCR/CV — P0

| Brecha | Riesgo | Control requerido | Estado |
|---|---|---|---|
| Texto visible omitido | Historia incompleta | barrido independiente + recall material | CUBIERTO, requiere más corpus |
| Dos campos UI fusionados | falso PASS aunque el texto exista | invariante de atomicidad + ownership exclusivo de evidencia | DISEÑADO / benchmark pendiente |
| Una frase fragmentada sin justificación | cardinalidad falsa | recomposición geométrica controlada + prueba negativa | CANDIDATO PR #138, no portado |
| Token corto real descartado | omisión de labels/valores | corroboración lexical/multi-pass | CANDIDATO PR #138, no portado |
| Fragmento OCR espurio aceptado | contaminación | corroboración cruzada + materialidad | CANDIDATO PR #138, no portado |
| Icono/control sin texto ignorado | funcionalidad omitida | parser UI / detector visual independiente | PARCIAL |
| OCR correcto pero semántica errónea | regla/historia equivocada | screen parsing + evidencia visual vinculada | PARCIAL |
| Mismo evidence token asignado a dos elementos | evidencia tautológica | ownership 1:1 para PASS | IMPLEMENTADO EN SUPABASE |
| PASS sin receipt/manifest/source/config/audit | cierre no reconstruible | artefactos mínimos obligatorios | IMPLEMENTADO EN SUPABASE |
| PASS con validación FAIL | contradicción de estado | fail-close de validations | IMPLEMENTADO EN SUPABASE |
| PASS de loop invalidado | evidencia obsoleta | registry de loop versions invalidadas | IMPLEMENTADO EN SUPABASE |
| Retry crea duplicados | auditoría ambigua | fingerprint + idempotent replay | IMPLEMENTADO Y PROBADO |
| Corrección borra evidencia previa | pérdida de trazabilidad | append-only + supersession | IMPLEMENTADO EN SUPABASE |

## Prioridad

1. P0: persistencia verificable e invariantes fail-closed.
2. P0: atomicidad y cobertura estructural.
3. P0: benchmark multi-engine sobre corpus real.
4. P1: optimización de latencia/costo luego de equivalencia funcional.
