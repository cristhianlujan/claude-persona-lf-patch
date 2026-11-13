# L28 — Separación actualizada por entorno (decisión sin firma)

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
