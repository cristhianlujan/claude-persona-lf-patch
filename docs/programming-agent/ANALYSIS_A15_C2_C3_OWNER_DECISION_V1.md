# Decisión del owner — A15Q_C2 y A15Q_C3

Fecha: 2026-10-14 (conforme dado en el chat de trabajo).

## 1. A15Q_C2 — reconciliación real Git–Supabase
Criterio vigente (sin modificar): «Reconciliación Git-Supabase/juez/PG-01 con huellas actuales».

El owner aprueba cerrar A15Q_C2 con una reconciliación real ejecutada dentro de la transacción de cierre contra el estado vivo de Supabase, comparada con huellas recalculadas desde los bytes actuales de Git:

- A1Q–A14Q: los 42 checkpoints en DONE y los 45 registros del plan presentes.
- C1 de cada unidad: el sha256 de la fuente canónica guardado en Supabase es igual al recalculado desde Git.
- C2 y C3 de cada unidad: el `raw_sha256` del recibo es igual al sha256 del texto capturado y guardado en `unit_metadata`.
- A15Q_C1: el sha256 del manifiesto de freeze en el recibo es igual al del archivo actual.
- PG-01: el contrato de entrada de Programming coincide con el blob del paquete congelado, y la huella de `fn_analysis_pg01_exact_receipt_guard_v1` en Supabase coincide con la esperada.
- Juez: el dossier en Git declara 45 checkpoints y 0 calificados.

Clase de evidencia: reconciliación ejecutada en base de datos al aplicar. No es ejecución de modelo, ni atestación de proveedor, ni revisión independiente.

## 2. A15Q_C3 — extensión de la aceptación del tier GPT Native
El owner extiende la aceptación de `ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1.md` (A1Q–A14Q) a A15Q_C3: la aprobación independiente del freeze la emite GPT Native en un chat nuevo, con handoff por evento de Supabase, captura por hash y verificador determinista. Se ejecuta solo después de cerrar A15Q_C2. provider_attested=false, independent_review=false.
