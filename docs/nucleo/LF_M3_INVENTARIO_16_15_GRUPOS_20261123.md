# M3 FINANCIAL_INTEGRITY_RECONCILIATION — 16 legadas / 15 grupos
Corte fuente: 23/11/2026 Lima. Fuentes del proyecto, EKB focal y LF_resguardos_construccion.md releídos antes de modificar. Query real: `lf_ops.nucleo_regla_familia JOIN lf_ops.v_reglas_compat_v1 ON regla_id=id`, familia FINANCIAL_INTEGRITY_RECONCILIATION, **16 filas**. El inventario JSON `sandbox/lf_contract_gate_test/nucleo_ci/m3_inventory_16_15groups.json` conserva mapping 1:1 de cada fuente en 15 grupos. `PALABRA_CLAVE` con validación pendiente NO garantiza pertenencia semántica a familia financiera.
## Estado por grupo y fuentes originales
| Grupo | Obligación | Fuente legada / ID / estado | Estado | Motivo |
|---|---|---|---|---|
| M3-G01 | Redondeo de cuotas y conciliación del plan | REG_CUO_005 / 161 (VIGENTE), B2B-RULE-INSTALLMENT-001 / 422 (CANDIDATO) | REQUIERE_DECISION | REG_CUO_005 exige ceiling a entero; B2B-RULE-INSTALLMENT-001 exige normalizar dos decimales, residuo solo última cuota si Asistente, rechazo diferencia Excel. Reconciliar semántica antes de migrar. |
| M3-G02 | Formato monetario en Cliente | REG_DAT_002 / 163 (VIGENTE) | FALTA_MIGRAR | Obligación de presentación y moneda; fuente por PALABRA_CLAVE. No integridad ni conciliación financiera. |
| M3-G03 | Estado transitorio de checkout recuperable | REG_CHK_024 / 314 (VIGENTE) | DEPENDE_PAULO | Backend/adaptador y prueba de recuperación de estado; no afirmar dependencia de ventana del navegador. |
| M3-G04 | Referencia de operación canónica | REG_CHK_027 / 317 (VIGENTE) | MIGRAR | Bloquear presentar referencia técnica inventada; omisión en estado transitorio no bloquea UI. |
| M3-G05 | Cancelación completa por deuda según ledger | REG_CLIENT_DEBT_SETTLEMENT_STATUS_001 / 533 (VIGENTE) | MIGRAR | No confirmar deuda liquidada con pago parcial/pendiente ni sin settlement requerido; hechos lógicos sin binding. |
| M3-G06 | Carta de no adeudo sin promesa anticipada | REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001 / 548 (VIGENTE) | MIGRAR | Un claim de carta disponible exige deuda confirmada liquidada y carta elegible; publicidad universal queda pendiente copy. |
| M3-G07 | Aprenda antes de decidir, no copy paralelo | REG_CLIENT_HOME_LEARN_DECIDE_001 / 552 (VIGENTE) | FALTA_MIGRAR | Coincidencia léxica; contenido educativo y fuentes compartidas, fuera de conciliación transaccional. |
| M3-G08 | Stepper onboarding con fuente consistente | REG_ONB003_STEPPER_4_001 / 575 (VIGENTE) | FALTA_MIGRAR | Coincidencia léxica; UI onboarding, no integridad financiera. |
| M3-G09 | Dashboard B2B con cifras autoritativas | B2B-RULE-DASHBOARD-001 / 603 (CANDIDATO) | DEPENDE_PAULO | Datos financieros de dashboard y KPIs, sin fabricar saldos o ratios. |
| M3-G10 | Pago B2B únicamente confirmado y atribuido | B2B-RULE-PAYMENT-FLOW-001 / 604 (CANDIDATO) | MIGRAR | Solo PAYMENT_CONFIRMED habilita exposición B2B como pagado; atribución por deuda/oferta y empresa verificada. |
| M3-G11 | Ledger canónico entre Cliente y B2B | B2B-RULE-PAYMENT-LEDGER-001 / 605 (CANDIDATO) | DEPENDE_PAULO | No hay contrato físico del ledger fuente confirmado; no dibujar tablas ni vistas ficticias. |
| M3-G12 | Liquidación B2B rastreable a pagos/ajustes | B2B-RULE-SETTLEMENT-001 / 606 (CANDIDATO) | DEPENDE_PAULO | Operaciones componentes, ajustes autorizados y neto backend pendiente. |
| M3-G13 | Conciliación con evidencia externa independiente | B2B-RULE-RECONCILIATION-001 / 607 (CANDIDATO) | MIGRAR | No marcar conciliado sin contraste proveedor/banco/canal y sin excepción trazable. |
| M3-G14 | Árbol funcional Portal Empresa | B2B-RULE-PORTAL-TREE-001 / 608 (CANDIDATO) | FALTA_MIGRAR | Navegación B2B, clasificación PALABRA_CLAVE ajena a integridad financiera. |
| M3-G15 | Detalle de carga con auditoría | B2B-RULE-LOAD-DETAIL-001 / 652 (CANDIDATO) | DEPENDE_PAULO | Enlace de carga, timeline y conciliación de lote; fuente técnica pendiente. |
**Clasificación:** cinco grupos MIGRAR, cinco DEPENDE_PAULO, cuatro FALTA_MIGRAR y uno REQUIERE_DECISION. **CUBIERTO: cero** acreditados por equivalencia total; coexistencia no implica absorción. El caso REG_CUO_005 (ceiling entero) y B2B-RULE-INSTALLMENT-001 (dos decimales y ajuste residuo por última cuota) no se homologa sin criterio del dueño.
## M3 candidatas (solo sin nueva decisión de producto)
| Nueva | Grupo fuente | Guard fail-closed | Residual técnico |
|---|---|---|---|
| M3-C01 | G04 / REG_CHK_027 | Intento de mostrar referencia + referencia no canónica → BLOQUEAR | Ledger, emisor/reserva y origen Paulo |
| M3-C02 | G05 / REG_CLIENT_DEBT_SETTLEMENT_STATUS_001 | Intento SETTLED_CONFIRMED + confirmación incompleta → BLOQUEAR | Ledger, acuerdo y settlement externo Paulo |
| M3-C03 | G06 / REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001 | Intento de anunciar carta disponible sin elegibilidad → BLOQUEAR | Estado carta y ajuste copy de HOME |
| M3-C04 | G10 / B2B-RULE-PAYMENT-FLOW-001 | Intento presentar/liquidar pago B2B sin confirmación y atribución → BLOQUEAR | Normalización y atribución ledger Paulo |
| M3-C05 | G13 / B2B-RULE-RECONCILIATION-001 | Intento marcar conciliado sin evidencia independiente/contraste → BLOQUEAR | Evidencia banco/proveedor y excepciones Paulo |
Todas nacen CANDIDATA, por puerta `lf_ops.nucleo_regla_proponer_v1`, pruebas PG17 aislado y sin declaración de cumplimiento real. Sus hechos son lógicos y están tipados; binding y tabla/columna ausentes hasta entrega de Paulo. Sin juez independiente no publicar. Para las fuentes CANDIDATO no se modifica su ciclo legada.
## Decisiones para Cristhian (máximo cinco)
1. **Redondeo de cuotas G01:** REG_CUO_005 exige ceiling a entero, mientras B2B-RULE-INSTALLMENT-001 exige conciliación a dos decimales, residuo solo última cuota. Recomendación: priorizar conciliación contractual exacta a dos decimales, separar **formato visual** del **importe financiero**; validar explícitamente antes de migrar.
2. **Liquidación de deuda / carta G05–G06:** ¿claim visual «Carta incluida» puede mostrarse aun cuando todavía no es emitible? Recomendación: si persiste, aclarar que se gestiona solo tras SETTLED_CONFIRMED y elegibilidad; no prometer entrega inmediata.
3. **Conciliación B2B G11–G13:** ¿qué evidencia externa y momento autorizan CONCILIADO? Recomendación: banco/proveedor como contraste independiente y trazabilidad de excepciones; no considerar prueba en sandbox como cierre financiero.
4. **Dashboard y liquidaciones G09/G12:** ¿cuáles indicadores son obligatorios en piloto? Recomendación: incluir solo importes y estados que Paulo pueda respaldar desde ledger, sin agregados inferidos en UI.
5. **Clasificación léxica G07/G08/G14:** ¿sacar de M3 contenido educativo, stepper y navegación, manteniendo reglas legadas intactas? Recomendación: corregir taxonomía en lote de clasificación posterior sin mover registros ahora.
Estas son solicitudes de decisión, no declaraciones de que Cristhian ya las aprobó. Los contratos de Paulo siguen pendientes, y no se inventó estructura física.
## M2 — siete grupos FALTA_MIGRAR para lote 2
| Grupo | Pendiente | Fuente(s) |
|---|---|---|
| M2-G05 | Identidad deuda, oferta y modalidad | 146, 147 |
| M2-G09 | Mostrar más planes solo si existen | 157 |
| M2-G13 | Estados visuales de cards | 171 |
| M2-G14 | Copy de ofertas no seleccionadas | 172 |
| M2-G16 | Modal de planes conserva estado | 238 |
| M2-G18 | Primera cuota destacada | 244 |
| M2-G25 | Texto Home no simula ofertas inexistentes | 382 |
Se mantiene M2 inventariado, sin cambios en este lote. Priorizar G09, G14, G16 y G18 por cobertura observable de UI; G05 requiere disciplina de modelado, G13/G25 cobertura de estado/copy.
## Evidencia y cierre
Migración `supabase/migrations/20261123174500_lf_nucleo_m3_financial_candidatas_v1.sql`; `sandbox/lf_contract_gate_test/nucleo_ci/m3_5_candidatas_v1.json`; pruebas sintéticas 22 casos, 5 mutantes de guard, PG17 BEGIN/ROLLBACK exact snapshot; ciclo de vida candidatas sin publicación. EKB nueva por error de asociación de PALABRA_CLAVE M3.
No declarar fusionado/aplicado hasta CI exact-head + Merge Train + readback Supabase. No editar legadas, M1/M2, REG_CHK_007 ni deprecaciones.
