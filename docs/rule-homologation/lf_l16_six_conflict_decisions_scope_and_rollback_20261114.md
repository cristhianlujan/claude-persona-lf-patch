# LF — L16 homologación de seis reglas, owner 2026-11-14
**Alcance SOURCE_FIRST:** único cambio de seis filas `lf_ops.reglas` por migración exacta del PR; sin promoción ni nuevas reglas; estados 4 CANDIDATO / 2 VIGENTE se preservan.
**Fuentes:** L27 Q04; L30 Q01/Q10/Q11/Q12; L35/L36 MFA OTP Brevo perfiles 1–6. Declaración documental, `identity_verified=false`, sin permiso de producción.
| ID | Regla | Cambio | Estado |
|---|---|---|---|
| 438 | B2B-RULE-AUTH-019 | OTP Brevo 1–6; SAML legado eliminado; política19 queda CANDIDATO | CANDIDATO |
| 439 | B2B-RULE-AUTH-020 | DNI, soporte, 2 personas, espera48h, aviso anterior; sin bypass; central20 requiere otro lote | CANDIDATO |
| 532 | REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001 | no gracia Q04; corte Lima; estado EN_PROCESO no se fuerza a VENCIDA | VIGENTE |
| 235 | REG_B2B_005 | carta 2 formatos, permisos de reenvío y SLA según convenio, elimina promesa 48h sin firma | VIGENTE |
| 440 | B2B-RULE-AUTH-021 | valor 5 sin sujeto/control/unidad; no modificar política numérica | CANDIDATO |
| 577 | B2B-RULE-AUTH-047 | faltante PASSWORD_ATTEMPT_POLICY; no reinterpretar 5 IP_USER como contraseñas fallidas | CANDIDATO |

Prueba fixture exacto de 6 filas respaldadas por SELECT; PostgreSQL **17.6/18.7** PASS, dry-run SQL bajo BEGIN/ROLLBACK y alteración de preimagen -> FAIL CLOSED. Referencia de pruebas: `test_owner_l16_rule_homologation_pgdual_v1.py`.
**No resuelto:** integración, QA/Legal, políticas centrales 19/20/22 y aprobación productiva. Sin SQL directo sobre base viva.
**R17 global anterior:** error ajeno por ruta antigua de migración #3887 corregida en PR #3899 (MERGED). Este archivo registra necesidad de nuevo CI exact HEAD contra main posterior.
