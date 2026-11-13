# L32 — Decisión del dueño para B02/G01 y B03/G02 (solo documento)

**ESTADO: PROPUESTA / NO FIRMADA / NO GO.** Nada en este documento autoriza reintentar, modificar, compensar, cerrar o reanudar RUN. No se realizó escritura en Supabase ni ejecución de escritor oficial.

## Qué está probado y qué no
- Fuente normativa: L28 `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md`, blob Git `130d474921e0ad010e94a645a8f350f3ca86e611`; tablero L28: Motor 0/7, Contenido 0/5, Infra final 0/2; total 0/14. Esos cierres siguen **NO VERIFICADOS**.
- L31 `11_informe_ejecutado_b02_b03.md` y `12_manifest_sha_readback.md`, commit `91eed67ec8d25ebb8eb4a2fbc7d6664f19c202af`: al corte canónico B02 `2026-11-13T07:32:11.933662+00:00` había 234 RUN `IN_PROGRESS`. Los 232 IDs históricos y el TOP32 propuesto existen; luego hubo lecturas con 235 y otra de 234. **No hay cohorte firmada**.
- SHA-256 del JSONB canónico B02 en origen: `d14568937e82995b0c141cd8be75bc7091fb0076164933209e0c616b1d564acc`. **No es automáticamente el SHA de la lista sola de IDs ni una firma.** SHA de B03: `ec233aa608d66167f9a0206cac3f4db9d0e40167fbf6daf15437b06e8ea3b60f`.
- B03: 234 RUN con preimagen; 8 leases vencidos, 0 vigentes; 204 con idempotency key sin duplicados observados; 29 pasos github_write positivos; 29/29 referencias GitHub existentes pero **sin atribución causal comprobada**. CI PG18.7 #43386747597 fue 16/16 PASS **sobre copia**, no gate live.
- PR #3803 reportó 61 RUN, pero falta **lista de IDs, SQL/filtro, as_of y versión**. No inferir que 61 sea subconjunto o equivalente a 234.

## Objetivo de la decisión
Definir un perímetro cerrado para **inventario/reconciliación solo lectura**, sin eludir RUN antiguos ni mezclar nuevas altas. La firma de alcance **no** autoriza recuperación operativa ni GO.

## Opciones
| Criterio | 32 prioritarios | Universo completo al corte |
|---|---|---|
| Trabajo inicial | Menor | Mayor |
| RUN fuera del alcance | Muchos sin certificación B03 | Ninguno de la foto congelada |
| Riesgo de efecto no detectado | Alto fuera de los 32 | Menor, sujeto a verificar sinks/identidad |
| Uso correcto | Orden de revisión, nunca denominador completo | Alcance G01/G02 recomendado |
| Nuevas altas | Se ignoran si no se controla el delta | Fuera del snapshot; se reportan separadas |

**Recomendación: AUTORIZAR `COHORTE_COMPLETA_AS_OF`.** Operaciones debe producir **un nuevo corte transaccional solo lectura** con `as_of`, snapshot MVCC, CSV literal ordenado, conteo y SHA del manifiesto. La foto L31 de 234 IDs es referencia verificable para comparar; **no imponer 234 como conteo futuro**. Dentro de esa cohorte, programar primero los 32 de L19 como **prioridad**, no como exclusión. Cualquier RUN posterior o cambiado se cataloga `FUERA_DE_CORTE/DELTA` y requiere conciliación explícita; no se incorpora silenciosamente.

**Riesgos residuales:** (1) el total puede superar 234 en un nuevo corte; (2) una clave de idempotencia sin duplicados no prueba inexistencia de efecto; (3) un lease vencido no demuestra muerte del worker; (4) GitHub commit existente no acredita causalidad; (5) una fecha `as_of` por sí sola **no recrea** versiones históricas en PostgreSQL, por lo que la lista literal firmada y su readback son obligatorios. Identidad humana temporal: una atribución en chat con `identity_verified=false` no equivale a firma autenticada.

## Decisión que se solicita al dueño — NO SELECCIONADA
- [ ] **Opción A, recomendada:** autorizar que Operaciones congele el universo completo `IN_PROGRESS` mediante snapshot transaccional **en el Supabase temporal**, con `as_of`, lista literal y SHA; 32 de L19 solo como prioridad de trabajo; ninguna exclusión silenciosa.
- [ ] **Opción B, excepción:** permitir trabajar primero los 32 IDs literales L19 y declarar explícitamente que **G01/G02 del universo completo siguen ABIERTOS** hasta cubrir los restantes y reconciliar los 61 de #3803.
- [ ] No autorizar ninguna de las dos.

**Campos de ratificación pendientes:** `decision_literal`, `decision_at_utc`, `owner_decisor`, `identity_mode`, `identity_verified`, `owner_approval_receipt_ref`, `authorized_scope_manifest_sha256`, `authorization_method`, `restrictions`. **Sin completar ni fingir firma.** El dueño decide la política y la cobertura; Operaciones ejecuta la captura; auditor verifica. Si el mecanismo temporal no permite verificar identidad humana, conservar `UNVERIFIED_CHAT_DECLARATION` y **no declarar firma ni G01 aceptado**.

## Cadena de entrega sin microaprobaciones
1. **Dueño:** decisión de cobertura A/B y condiciones, con mecanismo de autenticación realmente disponible. No cambia contratos ni RUN.
2. **Operaciones:** freeze SQL de `05_freeze_cohorte_asof_readonly.sql`; CSV RAW y hash, G01 candidato; mantener todas las altas posteriores como delta.
3. **DBA / Merge Train #3803:** entregar sus 61 IDs literal, filtro, `as_of`, commit/snapshot; comparar por conjuntos: `intersección`, `solo_61`, `solo_cohorte`. Nunca por conteos.
4. **Custodios de cada sink/worker:** un `EFFECT_RECON_RECEIPT` y liveness por RUN del alcance; priorizar 8 leases, 29 github_write, guards, direct sinks. Nada de replay.
5. **Auditor independiente/registrador oficial:** cotejar negativos, firma/competencia, RAW y hashes; recién entonces decidir G01 y G02.

**Condición de bloqueo:** cualquier ID omitido, recibo no auténtico, efecto inconcluso, contradicción del scope, lease sin aclarar, o falta de los 61 IDs mantiene **NO-GO**. El presente paquete no modifica recibos anteriores ni tablero L28.
