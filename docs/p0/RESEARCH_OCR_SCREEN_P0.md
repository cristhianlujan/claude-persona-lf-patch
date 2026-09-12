# RESEARCH OCR / SCREEN PARSING — P0

Fecha: 2026-08-12
Estado: RESEARCH_COMPLETE / ENGINE_PROMOTION_BLOCKED_REAL_EVIDENCE

## Conclusión ejecutiva

El defecto dominante en screenshots UI no es solamente OCR. Es la combinación de:

1. detección/recognition de texto;
2. segmentación atómica de unidades UI;
3. detección de iconos/controles no textuales;
4. agrupación semántica sin overmerge;
5. cobertura independiente que no permita que un elemento cubra dos unidades materiales distintas.

Por eso no se recomienda sustituir Tesseract por otro OCR aislado. La arquitectura candidata debe separar `OCR` de `screen parsing` y medirse contra el mismo corpus.

## Fuentes primarias revisadas

| Fuente | Aporte relevante para LF | Lectura operativa |
|---|---|---|
| Microsoft OmniParser — arXiv:2408.00203 + repo microsoft/OmniParser | Detecta regiones interactuables y aporta semántica de elementos en screenshots | Candidato directo para iconos/controles y grounding UI |
| Google ScreenAI — arXiv:2402.04615 | Entrena anotación de tipo + localización de elementos UI | Evidencia fuerte de que el problema debe modelarse como screen understanding, no OCR plano |
| ScreenParse/ScreenVLM — arXiv:2602.14276 | Supervisión densa de pantallas completas; boxes, tipos y texto | Referencia 2026 para cobertura completa y evaluación de parsing denso |
| PaddlePaddle/PaddleOCR | OCR multilenguaje + PP-Structure / parsing estructurado | Candidato OCR/layout open-source; requiere benchmark específico en screenshots LF |
| mindee/doctr | Pipeline explícito detección de texto → reconocimiento | Buen baseline alternativo para aislar errores de detection vs recognition |
| Google Cloud Vision OCR | TEXT_DETECTION y DOCUMENT_TEXT_DETECTION con palabras y bounding boxes | Benchmark comercial OCR; no resuelve por sí solo atomicidad UI |
| Microsoft Azure Vision / Document Intelligence | OCR para imágenes/screenshot y layout para estructura documental | Benchmark comercial; separar modo imagen de modo documento |
| Amazon Textract | Líneas, palabras, geometría y relaciones/layout documental | Benchmark comercial adicional; orientado a documentos, no screen parsing puro |

## Diagnóstico aplicado a LF

El PR #138 identificó un falso PASS por overmerge atómico: etiquetas/valores independientes podían compartir una sola unidad OCR y aun satisfacer cobertura. Ese patrón coincide con la literatura de screen parsing: una lectura textual correcta no demuestra una representación estructural correcta.

El PR #138 contiene ideas aprovechables (`_split_atomic_columns`, corroboración multi-PSM, `ATOMIC_ELEMENT_OVERMERGE`), pero su rama está divergida respecto de `main` actual. Debe tratarse como candidato técnico y no como parche mergeable directo.

## Decisión

- Mantener baseline gobernado actual mientras no exista benchmark real suficiente.
- Evaluar por capas: Tesseract actual, PaddleOCR, docTR y al menos un parser UI especializado (OmniParser/ScreenParse-class).
- No promover un motor por reputación, paper, estrellas o una sola pantalla.
- Una mejora de OCR que empeore atomicidad, contaminación o cobertura material se considera regresión.

## Bloqueo vigente

Corpus real disponible/verificado: 1 pantalla.
Mínimo de gobernanza heredado: 10 pantallas reales + 5 pantallas nuevas/holdout sin escapes para autonomía.

Resultado: `BLOCKED_REAL_EVIDENCE` para declarar un motor OCR/CV superior o habilitar aceptación autónoma.
