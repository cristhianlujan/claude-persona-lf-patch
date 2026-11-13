# L28 — Separación actualizada por entorno (decisión sin firma)

## ENMIENDA PRIORITARIA L28 — decisión del dueño, PENDIENTE DE FIRMA

**Solo base temporal.** B08 ya no exige verificar identidad humana vía Supabase Auth/JWT/MFA: toda decisión humana se **atribuye documentalmente** a `Cristhian Luján` con `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, frase, fecha, proponente, hashes y readback. No es identidad física comprobada ni firma. IAM humano real queda como requisito al migrar a la base de producción final. **B06**: el owner canónico de activos es `LF_GOVERNANCE` (distinto del decisor humano), guard en PR #3804 y backfill de **155** en PR #3806; ambos sujetos a PR #3803 vía Train. Los tres PR están sin readback de aplicación.

**Migraciones:** decisión solicitada «por Merge Train directamente, sin Router»; **no se debe llamar al Router manualmente antes de enviar una migración**. Se detectó conflicto con la implementación del Train y los PR, que aún exigen `ACTUALIZACION_DB_LF` y `router_authority_receipt`. No crear esos recibos ficticios ni retirar guardas: **reconciliación oficial pendiente**. La entrada ACT-0001 para *perfiles* y el Step70/Step80 EKB no cambian.

**PR #3803:** Train run `43373800126` falló por `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2`; sin apply/merge exitoso. En último HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028` hay bootstrap candidato, pero R17 run `43376438216` FAIL (un SELECT de test mal tipado y replay sin Train RUN exacto); PASE y clasificación PASS. #3804 DRAFT/mergeable=false y #3806 DRAFT/test aislado PASS, no aplicados. **0/7 Motor, 0/5 Contenido y 0/2 Infra final, todos abiertos.** Pruebas exactas y fuentes: `12_criterios_cierre_motor_7.md`; `13_readback_pr3803_3804_3806_train.md`.

| Grupo | Bloqueos | Estado | Función |
|---|---|---|---|
| Motor temporal | **B02, B03, B06, B07, B08, B09, B12** | 0/7 | G15-MOTOR, único GO técnico IG en base actual |
| Contenido paralelo | **B01, B04, B05, B10, B11** | 0/5 | IG registra dictámenes/firma documental; no veta GO Motor |
| Infraestructura final | **B13, B14** | 0/2 | backup/PITR y restore real antes de migrar/operar producción final |

**Base temporal:** no PITR contratado; no proyecto Supabase de prueba; backup físico de panel descrito por el dueño (7 copias diarias, última 12-nov-2026 09:37 UTC) **sin comprobación independiente ni firma**. La preimagen de cada cambio con SHA y un rollback ensayado es condición para modificar de forma gobernada; si existe riesgo de perder registros o revertir sin garantías, detener. B13 no se declara cerrado y B14 no tiene ensayo actual.

**Base final:** B13→B14→autorización de migración; PITR y restore aislado se prueban allí y no son requisitos del pase del Motor temporal. Se conserva la protección de fuentes al releer/migrar B07 en destino.

**GO Motor temporal:** siete gates G01,G02,G03,G04,G08,G11,G12 + G15-MOTOR con autoridad real, sin aprobar funciones de Contenido. B01→B09 cuando Login implica prueba fail-closed; B04→B07 interfaz; B05→B12 baseline contractual. Las decisiones Q01–Q12 y otras de Contenido siguen pendientes de firma, no autorizan promoción. Las firmas de autoridad de Motor, preimagen y pruebas sí siguen bloqueantes donde corresponda.

**G15 original L21:** sigue diciendo 14 recibos/32 firmas; no se modificó L21 ni el runtime. G15-MOTOR 7/7 es especificación de alcance L28, **no control ejecutable declarado**.

**Invariantes históricos:** 15/36 REAL_EN_SANDBOX PG18 (41,7%), 14/36 SINTÉTICO, 7/36 NO_PROBADO, E2E productivo acreditado 0/36 en L18/L20. Cuatro MD5 PG18 documentados (apply 86b0494984edf95cf0f9c0a0df67000b; capture_record 89cbfac4162dbc9f8ecca59f2c3ab4c3; citation_verify 773a62783baa5edbe967200cac66b8c3; l8_guard 522d12f0843be1da3c785cef3c0bf3fc), no reejecutados aquí.
