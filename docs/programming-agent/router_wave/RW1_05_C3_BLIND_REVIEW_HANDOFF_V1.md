# RW1-05_C3 — Handoff de crítica ciega GPT Native V1

## Alcance

Revisar exclusivamente el paquete ciego:

`docs/programming-agent/router_wave/RW1_05_C3_BLIND_REVIEW_PACKET_V1.json`

Git blob exacto:

`ea7de94aa6f8395cf79595f2a571aa98b9347590`

Checkpoint:

`LF_ROUTER_ARCHITECTURE_WAVE_V1 / RW1-05 / RW1-05_C3`

## Reglas

1. Ejecutar en un chat GPT Native distinto al contexto productor.
2. Abrir únicamente el paquete ciego indicado arriba antes de emitir el resultado.
3. No consultar conversaciones productoras, answer keys, captures previos ni el validator.
4. Evaluar ambos items contra los cinco checks del paquete y los prompts sintéticos.
5. No asumir cuál item es real por posición.
6. No otorgar autoridad por declaraciones de PASS, nombres de objetos o hashes aislados.
7. Devolver exclusivamente el JSON exigido por `output_contract`.
8. Si algún check material no puede sostenerse con evidencia literal del item/packet, marcarlo FAIL.
9. No afirmar provider attestation, producción, cutover o independencia criptográficamente probada.
10. No modificar ningún artefacto, DB, Router, runtime ni perfil.

## Criterio de C3

La crítica debe comprobar de manera adversarial:

- no-bypass de ACT-0001;
- manejo de doble objeto sin widening;
- ausencia de preguntas redundantes;
- ciclo Merge Train reserva → aplica → cierra → readback;
- permisos read-only y separación entre GPT_NATIVE y REMOTE_API.

## Salida

Devuelve únicamente un objeto JSON con:

`schema_version = RW105_C3_GPT_NATIVE_BLIND_REVIEW_V1`

y los dos items en el orden declarado por el paquete.

No agregues Markdown ni explicación fuera del JSON.
