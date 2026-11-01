# LF — Dictamen V3 en contexto actual para ejecución de solo lectura

Estado: **candidato gobernado**. Solo entra en vigor al integrar código + migración + despliegue, con readback positivo y negativo.

## Decisión de alcance (usuario propietario, 2026-10-31)
Se permite completar un **diagnóstico de solo lectura** en el mismo contexto que generó el RAW, sin abrir otro chat de revisor. No se denomina revisión independiente. No se aplica a modificaciones de fuente, producción, despliegue de producto, promoción, políticas de seguridad ni a otras operaciones.

## Contrato propuesto de dictamen
- `review_mode: CURRENT_CONTEXT_REVIEW`.
- `verdict: PASS_REVIEWED_CURRENT_CONTEXT` exclusivamente si los 11 controles semánticos aplicables de V3 pasan con fuentes inspeccionadas, y control 11 es `NOT_TESTED / not_applicable / ROUTER_ONLY` en ausencia de una comparación directa auténtica.
- `producer_independence_proven: false`, `reviewer_is_producer: true` y `model_call_count: 0` (ninguna llamada separada a juez). **Nunca falsificar** la identidad del revisor ni afirmar una invocación independiente.
- Dos hashes originales inmutables del `execute_profile` y `input_validate`, refs de fuente realmente inspeccionadas, evidencia contrafactual y `unsupported_claims: []`, `blocking_codes: []` para PASS.
- Si alguna afirmación relevante no está sustentada o falta control de aceptación material, no emitir PASS. El modo no convierte automáticamente un dictamen negativo en positivo.
- La autorización se limita a ejecuciones con manifest `read_only=true`, `no_write=true`, `no_promotion=true`; la ruta `ACT-0001 → Perfil` permanece intacta.

## Ejecución
El dictamen V3 con el nuevo modo se presenta por el canal de continuación **existente** `LF_PROFILE_NATIVE_RESUME_REQUEST_V1` y etiqueta `lf-profile-resume-governed`. `scripts/lf_profile_native_resume.py`, Edge y los RPC de paso 70 y 80 aceptan `PASS_REVIEWED_CURRENT_CONTEXT` solo con procedencia honesta, fuentes y controles reales. El trust validator servidor verifica explícitamente la distinción de modos y rechaza resultados inconsistentes.

La certificación de cierre **siempre** es por lectura en Supabase, según [acreditación oficial](ACREDITACION_JUEZ_V3_SUPABASE_RUTA_GOBERNADA_20261101.md): step70 `STEP_PASS_WITH_EVIDENCE`, step80 `STEP_PASS_WITH_EVIDENCE`, run `COMPLETED`, 11/11 y recibo terminal `READY`.

## Compatibilidad y controles
- El modo `INDEPENDENT_SEMANTIC` y su veredicto histórico `PASS_INDEPENDENT_SEMANTIC` siguen admitidos sin reinterpretar evidencias antiguas.
- Negativos: no marcar `true` en independencia de modo actual; no falsear `model_call_count`; no aceptar 11 controles sin `result=true`; no permitir `unsupported_claims`, `FAIL` o bloqueo de servidor; no aceptar comparación Router/directa inventada.
- Positivos: PASS del modo actual con 11 controles reales, control 11 NA justificado, hashes coincidentes y cierre 70/80 con readback.
- EKB `PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001` conserva `ACTIVE_REMEDIATION` hasta pruebas negativas y positivas reales.
- El documento no sustituye el juez semántico V3 ni concede al Router facultad de invocar perfiles.

## Caso de continuidad
`EXEC-PROFILE-GATE2-FB71EBD7D1A89272BFF20E44` (PR #3438), RAW `f497633c50d83d55b6247474c909f2b075eb531f3c069173698a7972ea4cfb87`, scope `7e8583e01c5dfa833838b73f68f4e08e15019da9b315f6ddabc97468ca066e0d`. Las primeras 9 etapas están registradas, las 70/80 deben ejecutar solo si el nuevo dictamen material de ese RAW es aceptado y el servidor permite la actualización.
