# IG Niubiz — decisiones V2 secuenciales y alta CANDIDATO

**Objeto único:** crear tres reglas de correo Niubiz con `public.lf_ig_rule_owner_decide_v2`, sin DML directo sobre `lf_ops.reglas`, sin promoción ni producción.

**Fuentes:** PR #4106 propuesta parametrizada (20/20 PASS); PR #4141 context budget reparado con hard gate intacto, Train 44426052068 SUCCESS; PR #4143 prueba real PG17 8/8 + CREATE 6/6, Train 44428506420 SUCCESS, event_id=22001, head `da56ce40d67a635a004247aeb9ed524690f6de64`, receipt_sha `b43fa737b3fc80969aabc464c2f460632af31c613eeea859b67d2669d514a525`, archivo 14484483531.

| Regla | RUN padre nuevo | Patch SHA256 Step50 | Variable referenciada | Estado objetivo |
|---|---|---|---|---|
| REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001 | EXEC-PROFILE-GATE2-DCE01AEE24CF00F0362D3E01 | b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa | PAGOS/NIUBIZ_EMAIL_TEMPLATE; PAGOS/NIUBIZ_EMAIL_DOMAIN | CANDIDATO |
| REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001 | EXEC-PROFILE-GATE2-FEC6C217064FA241227B715D | 4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4 | Ambas, solo para separar el identificador técnico del correo real de recibos | CANDIDATO |
| REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001 | EXEC-PROFILE-GATE2-9D48CA261787E2E9F3A7CB31 | b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c | Ambas, solo para identificar correo técnico y tolerar rebotes posteriores a aceptación | CANDIDATO |

**Reroute oficial 18/11:** Issues #4145-#4147 (Router Context V2 -> Product Director); #4148-#4150 (selección pantalla), #4154 (reintento por cancelación #4149), #4151-#4152 (RAW con proponente). Solo se reutilizan los SHA de `governed_rule_patch`, no los RAW ni los execution_id históricos. El RAW nuevo debe tener `product_decision.proposed_by=PERFIL-PRODUCT-DIRECTOR-LF`, diferente de quien decide V2.\n\n**Verificación obligatoria por regla:**

1. Readback de padre Product Director `IN_PROGRESS`, screen scoped correcto, Step50/60 `STEP_PASS_WITH_EVIDENCE`, RAW gobernado con SHA exacto.
2. `lf_ig_functional_train_evidence_v1` alimentada únicamente por recibo Train auténtico, hash de log PG17, readback y manifest efectivamente ejecutados; se valida `RULE_CONTRACT_LEVEL` y SHA de propuesta.
3. `lf_ig_step70_functional_train_auto_v1` retorna PASS, bridge oficial registra Step70. Antes de cada decisión owner V2 se ejecuta el escritor real `RULE_CREATE_APPLY` bajo subtransacción y se fuerza rollback con sentinel, verificando fuente intacta.
4. Una decisión `{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}` por regla, siempre vía `lf_ig_rule_owner_decide_v2`, que invoca y comprueba hijo 7/7, estado `CANDIDATO`, `pendiente_decision=true`, cero promociones. **Todas las decisiones se ejecutan secuencialmente dentro de una transacción atómica; si alguna falla, ninguna queda aplicada.**
5. Readback SQL 583→586 y 145→148 candidatos; md5 idéntico de todas las reglas preexistentes y 46 filas de `lf_global_config`. No tocar objetos de chat 8 ni protect-main.

**No afirmar:** Niubiz sandbox guion aceptado (NOT_TESTED), existencia de buzón técnico, recibo efectivamente entregado, QA E2E o producción.
