# IG M10.7 — A3 candidato: reutilización de vínculos efectivos de reglas por sentencia

## Finalidad y legitimidad
Cambio interno del agente de Input Governance de LF, sobre repositorio autorizado. El objetivo es eliminar resoluciones repetidas **sin suprimir** controles de SECURITY, reglas, jueces ni decisiones. No se solicita omitir controles del proveedor ni elevar permisos; se usa GitHub y LF Migration Train bajo su contrato existente. El rechazo anterior de `create_branch` provino del control de herramienta, sin respuesta HTTP GitHub, y no se interpreta como vulnerabilidad ni falso positivo confirmado.

## Objeto acotado
Instalar solo `programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text)`. El canónico `programacion.fn_input_subject_depth_expected_v510(integer,text)` conserva su definición y permisos.

Revisión de fuente: **17 sitios de llamada** a `fn_input_effective_rule_links_v1` están *exclusivamente* en la rama `SECURITY`, NO `DESIGN_SYSTEM`. Dentro de la sentencia de la rama SECURITY, `WITH effective_links AS MATERIALIZED (... fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') ...), subjects AS ..., checks AS ...` reemplaza esos 17 sitios con la relación común. Se consulta el selector gobernado una vez por sentencia, sin modificarlo, fijar reglas en código ni persistir caché. Todas las comprobaciones siguen ejecutándose con sus condiciones originales, incluidas variantes sensibles PASSWORD_INPUT, OTP_INPUT, QR_DISPLAY, GENERATED_SECRET y TOTP_CODE_INPUT.

## Riesgos y límites
El resolvedor es STABLE, pero el entorno usa READ COMMITTED. El CTE solo se comparte **dentro de una misma sentencia**; no se reutiliza entre transacciones, chunks, pantallas ni familias. Cambios de autoridad externa y G2B de dos sesiones continúan sin certificar. No compartir veredictos de Curator ni Validator.

## Gate de candidato
Preflight MD5 canónico `83c6b61cd23cc0c57abbd8ee4831f8b5`, ausencia de candidato, EKB-first `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `IG-M107-ALL-STAGES-QUERY-INVENTORY-007`, `IG-M107-A2-INCALL-PROMOTION-014`.
Una migración, sin EXECUTE PUBLIC. Pruebas positivas/negativas: igualdad JSONB exacta y SHA para familia SECURITY sobre pantallas 1,43,53,55,58; control no-regresión DESIGN_SYSTEM; negativo pantalla inexistente; verificación de status de checks, receipt y tiempos alternados. No declarar mejora del Validator ni avance CP3 sin ensayo integral.

Promoción canónica (si procede) en PR separado, tras microbenchmark favorable y equivalencia comprobada por Train, ledger/readback EKB. Ningún cambio de triggers/reglas.
