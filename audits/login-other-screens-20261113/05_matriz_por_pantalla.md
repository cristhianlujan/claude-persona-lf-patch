# Auditoría PR #3847 — decisiones dueño 22:03 Lima (solo propuesta)
**Autoridad**: documental, identity_verified=false; ninguna migración ni Supabase DML. EKB 1.4 consultada. Los 344 vínculos de origen siguen congelados como preimagen.
## Matriz por pantalla — regla | ajuste | texto nuevo
| Pantalla | Regla | Ajuste documental |
|---|---|---|
| B2B-AUTH-002 | AUTH-028/042 + RECOVERY-ALTERNATE-CONTACT | Solicitud soporte, no inicia espera; 48h solo tras aprobaciones requeridas y aviso ENTREGADO; rebote bloquea/pausa; alternos no aprobados |
| B2B-AUTH-003 | AUTH-029 + RECOVERY-SUPPORT | PASSWORD_UPDATE_ONLY solo por clave temporal de uso único después de los 48h elegibles; no MFA ni sesión |
| B2B-AUTH-004 | nuevo RECOVERY-MFA-SEPARATION (CANDIDATO) | Recuperación y avisos no satisfacen MFA; mantener reglas protegidas OTP correo Brevo sin cambios |
| B2B-AUTH-005 | ninguna | REEMPLAZADO/inactiva, 21 vínculos a reglas VIGENTE históricos sin ejecutar aquí |
| B2B-AUTH-006 | AUTH-029/037/038 + RECOVERY-ALTERNATE-CONTACT | Vigilar estado DELIVERED real del aviso previo, aprobaciones política 20, 48h + pausa/bloqueo en rebote |
| ONB_001 | ninguna | Sin cambio; no inventar autorización por OTP del celular actual |
| ONB_002 | UI_STATES + SMS_SUPPORT_GATE | SMS Intico solo contingencia aprobada por soporte; OTP actual no inicia 48h Q11; sin selfie |
| REC_001 | IDV_STEPUP/IDV_OUTCOME/PHONE_CONTROL/REBIND_ATOMIC + SUPPORT_Q11 + ALTERNATE_CONTACT | Dos personas distintas, aviso ENTREGADO tanto al celular como al correo anterior, 48h de reloj gobernado; selfie NO, IDV por elegir |
## Decisiones humanas abiertas
Proveedor IDV H02; H04A/B quién puede sustituir al contacto anterior cuando ningún canal histórico alcanza DELIVERED. El bloqueo/pausa y no liberación ya son decisión del dueño, NO se reabren.
## Riesgos y límites
`lf_ops.politicas_seguridad` política 20 todavía es CANDIDATO y no presenta `approvers_required` en SELECT; referenciarlo aquí no lo implementa. Reglas #3844/#3846, políticas 19/20/23/25, AUTH_LOGIN_FAILED_PASSWORD, contratos compartidos AUTH-041/044/045, REG_ALR_003 y REG_UNI_002 quedan intocados. Por cada mutación propuesta test aislado PG17.6/18.7 con SHA antes/dentro/tras rollback; NO-GO producción.
