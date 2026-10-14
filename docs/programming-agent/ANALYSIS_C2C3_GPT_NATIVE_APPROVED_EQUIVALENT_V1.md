# Equivalente aprobado GPT Native en chat para C2/C3 del análisis (V1)

Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Alcance: checkpoints `A1Q_C2..A15Q_C2` y `A1Q_C3..A15Q_C3`.

## Decisión del propietario

El propietario (Cristhian) indicó que el productor y el revisor deben ser únicamente GPT Native en chat, sin otro modelo ni API de pago. Ante la definición propuesta del "equivalente aprobado", respondió "ok conforme" (2026-10-13, 21:56 America/Lima).

Esta decisión define un **nivel de evidencia propio**, `OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT`. No sustituye ni equivale a `REAL_EXECUTION_RECEIPT`.

## Qué es el nivel

- **C2 (productor):** salida RAW de GPT Native en una conversación de chat, ligada por hash al input congelado (`input_sha256`), a la solicitud (`request_sha256`) y a la salida (`raw_output_sha256`), con referencia y hash de la transcripción del chat.
- **C3 (revisor):** otra conversación GPT Native, separada, que recibe un paquete ciego (sin el veredicto ni el chat del productor), ligada al `raw_output_sha256` revisado.
- Verificación determinista: `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_gpt_native_equivalent_v1.py` (pruebas en el `test_` homónimo).

## Qué NO es (límites que viajan en todo registro)

- `provider_attested = false`. La transcripción sellada es copia de lo que dijo el chat; no es evidencia del proveedor.
- `real_execution_receipt = false`. Los campos `governed_execution_id`, `router_dispatch_receipt_id`, `provider_response_id_attested_by_transport` y `evidence_ledger_verified_ref` solo los emite el runtime gobernado. Presentarlos en una captura de chat se bloquea como `FORGED_GOVERNED_FIELD`.
- `independent_assurance_admitted = false`. No satisface `INDEPENDENT_ASSURANCE@2.0.1` ni `lf_independent_review_begin_v3`.
- No se puede demostrar con código que GPT produjo el RAW ni que la segunda conversación fue ciega.
- Claude no produce ni revisa C2/C3.

## Alcance de este cambio

Solo código y registro. **No** cambia la política activa `POL-PROFILE-UPDATE-PASS` (v1.1), el catálogo, los `action_specs_v1`, ningún checkpoint ni la base. A15Q_C1 sigue bloqueado por su requisito de refreeze independiente.

## Para cerrar un checkpoint bajo este nivel

1. Generar el paquete congelado de la unidad (input, perfil, contrato) y su `request_sha256`.
2. Ejecutarlo en GPT Native y traer el RAW y el enlace de la conversación.
3. Verificar con `attest_c2`; para C3, repetir en una conversación separada con paquete ciego y verificar con `attest_c3`.
4. Una migración propia por el Train registra la aserción con el nivel y sus límites (`provider_attested=false`), como se hizo en C1. Requiere que el `pass_when` de esa unidad acepte este nivel, y eso es una decisión por unidad.

Mientras no exista una captura real, C2/C3 permanecen PENDING.
