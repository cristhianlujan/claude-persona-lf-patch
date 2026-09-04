# MATRIZ DE OPCIONES OCR/CV — P0

Escala cualitativa basada en capacidad declarada/documentada. No equivale a resultado LF.

| Opción | Texto | Boxes/layout | UI/iconos | Offline | Riesgo principal | Decisión |
|---|---|---|---|---|---|---|
| Tesseract + OpenCV actual | Sí | Básico/custom | Parcial/custom | Sí | grouping/atomicidad depende de heurísticas | BASELINE |
| PaddleOCR / PP-Structure | Sí | Fuerte | Parcial | Sí | document-centric; validar screenshots | BENCHMARK |
| docTR | Sí | Word-level | No especializado UI | Sí | requiere capa adicional de screen parsing | BENCHMARK OCR |
| OmniParser | usa OCR + detector | Sí | Fuerte, interactables + semantics | Sí, según stack/modelos | integración/model weights + benchmark LF | BENCHMARK UI PRIORITARIO |
| ScreenAI-class | Fuerte multimodal | Fuerte | Fuerte | depende del modelo disponible | integración más pesada; no asumir disponibilidad productiva | REFERENCIA/CANDIDATO |
| ScreenParse/ScreenVLM-class | texto + parsing denso | Muy fuerte para screen parsing | Fuerte | depende de artefactos/modelos | tecnología reciente; validar madurez | REFERENCIA 2026 |
| Google Cloud Vision | Sí | Sí | No parser UI especializado | No | costo/dependencia cloud y semántica UI insuficiente | BENCHMARK COMERCIAL |
| Azure Vision / Document Intelligence | Sí | Sí | No parser UI puro | Cloud/containers según servicio | seleccionar modo correcto screenshot vs documento | BENCHMARK COMERCIAL |
| AWS Textract | Sí | Sí + relaciones documentales | No parser UI puro | No | orientación documental | BENCHMARK SECUNDARIO |

## Regla de selección

No existe ganador declarado al 2026-08-12.

Un candidato solo reemplaza baseline si, sobre el mismo corpus y configuración fijada:

- reduce una métrica crítica o mejora cobertura;
- no introduce regresión en omisión, contaminación, atomicidad ni evidence ownership;
- es reproducible con versión/model hash/config fijados;
- mantiene trazabilidad por elemento;
- pasa holdout no usado para ajustar reglas.

Si hay empate funcional, se conserva baseline y costo/latencia decide únicamente después.

<!-- S28_SANDBOX_ACTUAL_PUSH_FAST_CANARY_20260904: temporal -->
