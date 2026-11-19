# IG Niubiz — tres contratos RULE_CONTRACT_LEVEL (solo evidencia)

**Estado:** PR de prueba, no realiza altas de reglas ni decisiones del dueño.

Fuentes existentes: PR #4106 textos y 20 tests; PR #4141 contexto Producto compactado, Merge Train 44426052068 SUCCESS, tres RUN reales con Step50/60 PASS.

| Regla | RUN padre | SHA-256 de patch Step50 | Variable referenciada |
|---|---|---|---|
| REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001 | EXEC-PROFILE-GATE2-8A32C42D5DE64233CB4ABE3E | b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa | PAGOS/NIUBIZ_EMAIL_TEMPLATE; PAGOS/NIUBIZ_EMAIL_DOMAIN |
| REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001 | EXEC-PROFILE-GATE2-C1988A78EEC630B2C7D3348A | 4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4 | Ambos; solo identifica el correo técnico distinto al real |
| REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001 | EXEC-PROFILE-GATE2-447657D25F743AE8121267AC | b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c | Ambos; identificador técnico que puede rebotar |

La migración proof-only valida las 3 firmas sobre el RAW original en Supabase, presencia de parámetros TEXT/REAL, scope de checkout y que las nuevas reglas no existan. **No inserta reglas, evidencia, decisiones ni cambia producción.** Real PG17 sintético en CI comprueba los contratos y hashes con 8 checks, casos negativos, BEGIN/ROLLBACK y readback en sesión independiente. También se reejecuta el gate genérico CREATE CANDIDATO de chat 8 con 6 checks.

Después de que el PR salga por el Merge Train, la siguiente migración separada deberá vincular la evidencia PG17 real al recibo del Train autenticado y al SHA exacto de cada patch, registrar Step70 a través de bridge oficial y llamar `lf_ig_rule_owner_decide_v2` por cada regla con `usuario=Cristhian Lujan`. Todo bajo condiciones y readback independiente; en ausencia de coincidencia bloquear. Los tres deben permanecer **CANDIDATO** con promoción y producción no autorizadas.

**Riesgo externo:** Niubiz puede rechazar el guion del identificador técnico; sandbox Niubiz **NOT_TESTED**. Los rebotes son aceptables pero nunca confirman un pago.
