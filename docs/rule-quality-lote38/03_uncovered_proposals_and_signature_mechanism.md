# L38 — Estado y decisiones sin cubrir (solo documentos)

**Confirmación del dueño reportada:** viernes 2026-11-13 08:31 Lima / 13:31 UTC (precisión minuto), frase literal del L37. Se recibió esa afirmación en el mensaje actual; **no se obtuvo ID o lectura independiente del chat del arquitecto**. `identity_mode=UNVERIFIED_CHAT_DECLARATION`; `identity_verified=false`. Recibo L38 **no equivale** a firma autenticada.

## Cobertura

- **24/24 identificadores** del manifiesto L37, hash exacto `ae43acb08d1783859607921ca54d58d60da89a8dff55ee38e9da37113712e9c7`, incluidos 23 anteriormente `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` y `PROP-RIESGO-RECIBOS-DUENO-001` que antes era propuesta de aceptación.
- Todos ahora `DECIDIDA_CONFIRMADA_EN_BLOQUE_NO_VERIFICADA` **solo en el overlay L38**. La fuente L37 sigue inmutable para que su SHA no se invalide. La conformidad de riesgos R01–R05 es documental, no evidencia de mitigación.
- SHA-256 frase exacta, sin salto final: `a77ef1688ca7679980d807a96177fa3e6cbd2ef3f9f43fa50efee244c48b0475`.
- **0 firmas verificadas, 0 RUN modificados, 0 writers invocados, 0 operaciones Supabase, 0/14 bloqueos cerrados.**

## No cubiertas por el bloque y su siguiente autoridad

| ID fuera del bloque | Evidencia documental | Pendiente real |
|---|---|---|
| `B2B-RULE-AUTH-018` | L29 `docs/rule-quality-lote29/09_matriz_humana_51.md` registra contradicción MFA siempre / perfiles. | Dueño/Seguridad: decidir **patch exacto** y disparadores adicionales MFA; política central 3 y prueba semántica. Q01 es dirección temática, no aprobación de este SHA de propuesta. |
| `B2B-RULE-AUTH-020` | L29 identifica recuperación Q11, política 20 y binding incompleto. | Dueño + Seguridad/Soporte: delimitar alcance de recuperación, IDV/operación, aprobar propuesta concreta; Q11 no autoriza por sí sola el patch V2 ni la publicación. |
| `B2B-RULE-AUTH-033` | L29 contradicción dispositivo reconocido vs MFA condicional; L33 Login solo preparó handoff Gate2 hacia pantalla 54 `B2B-AUTH-004`, sin RUN. | Dueño/Producto/Seguridad: reglas de dispositivo reconocido/no reconocido, segundo factor y política 25; RUN gobernado, propuesta SHA, juez y evaluación. |
| `B2B-RULE-AUTH-002/003/040` | L33 Login tiene tres patches documentales preparados, no decisiones individuales del dueño. | Reconciliar fuente VIGENTE/CANDIDATO, estado y contrato aplicable; no inferir aprobación por Q01. |
| Otras 20 decisiones L19/L21 | L30 declara 20 fuera de las 12 Q conversadas, sin decisiones firmadas. | Decisión del dueño caso por caso o un nuevo paquete de firma **después** de que existan decisiones explícitas y SHA de texto exacto. |
| Otras nuevas no registradas en L30/L33/L35/L36/L37 | No hay fuente exacta que permita enumerarlas desde este lote. | Operaciones/Gobernanza: cotejar contra un inventario actualizado de decisiones y abrir nuevo scope; no incorporar silenciosamente a este bloque. |

**Sustituidas (no revivir):** opción C FIDO2 de L34 por L35 y extensión L36; subasunto método Admin LF pendiente L30 sustituido por L36.

## Qué falta para convertir la declaración en firma verificada

1. **IAM/Seguridad:** identificar actor humano real con `sub` comprobable mediante autenticación válida (Supabase Auth u otro IdP formal) y asociar rol/competencia de dueño; no usar un `owner_sub` placeholder como si fuera identidad autenticada.
2. **Registrador oficial / Arquitectura:** definir el contrato de **firma documental de bloque** (no existe evidencia de que V2 acepte la frase grupal). Debe vincular actor autenticado, momento servidor, ID de bloque, manifest SHA, 24 IDs, frase y SHA, riesgos R01–R05, nonce/anti-replay, consentimiento expreso y firmas/recibos verificables.
3. **Writer oficial de firma (futuro, no invocado):** persistir mediante carril oficial, no SQL manual, un recibo inmutable y verificable, con algoritmo, issuer, clave pública/verificación y readback segregado; conservar anexo fuente.
4. **Auditor independiente:** verificar autenticación, integridad, fuente literal, 24/24, no duplicado/alteración, custodia y segregación. Si no existe mecanismo de firma, estado debe permanecer **NO_VERIFICADA**.
5. **V2 por regla:** `lf_ig_rule_owner_decide_v2` exige seis campos individuales, parent RUN, patch SHA específico y `PASS_INDEPENDENT_SEMANTIC`; un `APROBAR` puede activar escritor/promoción. **No invocar** con la firma en bloque; riesgo B09 mismo LLM no acredita juez independiente.

La aceptación del dueño **no suplanta** los recibos emitidos por Operaciones/DBA/auditor ni las pruebas de G01/G02. B07 padre/hija y G15 de solo siete gates son criterios de diseño/alcance aún sujetos a contrato y evidencia; producción permanece **NO-GO**.

## Procedencia

EKB V1.4 revisado (documento adjunto, candidato parcialmente verificado), manifiesto y frase L37 leídos desde GitHub, L29 y L33 contrastados. Este lote registra **el reporte** de una conversación externa; no se le adjudica recibo firmado de aquella conversación ni timestamp comprobado por servidor de ese chat.
