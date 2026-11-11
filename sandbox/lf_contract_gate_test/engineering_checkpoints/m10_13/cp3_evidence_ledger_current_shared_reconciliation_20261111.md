# IG M10.13 / CP3 — Reconciliar EVIDENCE_LEDGER sin reemplazar autoridad

## Hallazgo de fuentes, 11-nov-2026
- Evidencia M10.10 `public.lf_eventos#20193`: `public.fn_lf_evidence_ledger_anchor_v1` figura como `LEGACY_REFERENCED`, con razón histórica `ACTIVE_ONLY_VIA_UNUSED` (“no path from a current live root”).
- M10.4 congeló exactamente el cuerpo MD5 `730d37e8698885335228c91d00231b1f` y sus 26 funciones; NO modificar baseline ni cuerpos.
- Autoridad canónica ACTUAL: `public.lf_activos.id=136` `EVIDENCE_LEDGER` `ACTIVO/VIGENTE`, propietario `LF_GOVERNANCE`; capacidad `EVIDENCE_LEDGER ACTIVE v1.1.0`, manifest SHA `b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982`.
- 79 recibos canónicos en `private.lf_evidence_ledger_v1` a fecha de lectura, sin mutación ni borrado.
- Cuatro referencias SQL exactas desde funciones no congeladas, incluido `lf_record_independent_review_step_v3`. El recorrido desde los siete roots IG alcanza este anchor.
- Decisión vigente de retiro por el owner: NO LOCALIZADA. `RETIRO_ACTIVO_LF` es `CANDIDATO_READ_ONLY`; prohibido invocar como escritor.

## Alcance de ejecución
Una anotación de reconciliación actual en `programacion.engineering_plan_units M10.13.unit_metadata` y recibo `public.lf_eventos`, utilizando la operación y el Train existentes. No editar M10.4, contratos ejecutables, activos, capabilities, ledger, routers, perfiles, ACL, ni checkpoints.

Clasificar `EVIDENCE_LEDGER` como `CURRENT_SHARED_OBSERVED`, con la discrepancia M10.10 preservada. No computar “0 callers legacy” ni clausurar M10.13. Reconciliación definitiva/retirement requiere decisión LF_GOVERNANCE/SUPER_ADMIN.

## Condiciones
Pin de cuatro caller signatures y hashes, capacidad ACTIVA y manifiesto, asset VIGENTE, anchor MD5 y freeze 26/26. Confirmar 15 aristas frozen→frozen y cuatro externas, ningún caller externo desconocido. Escribir solo si preestado exacto, registrar execution_id real y hacer readback. Guardar CP3 PENDING, negativa a clasificar una futura referencia legacy como CURRENT solo por coincidir con un prefijo.

EKB: GOV-ASSET-RETIREMENT-GOVERNANCE-V1-001, IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001, IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001.
