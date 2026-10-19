# PE10 — Procedimiento individual para alcanzar DONE (32 métodos)

El procedimiento canónico se almacena en `programacion.engineering_plan_units.unit_metadata.done_procedures_v1.<PE10_Mxx>` y en el paquete de entrada del mismo checkpoint. Contrato: `PE10_METHOD_V1`. No modifica los resultados ni la evaluación posterior.

**Secuencia invariable:** resolver ID/contrato → revisar o reejecutar solo el método → aplicar sus algoritmos → conservar SQL literal y respuestas → negativos/causalidad → congelar RAW y SHA → materializar verificación canónica → PR/PASE/Migration Merge Train → readback de DONE.

Para brazo B: 5 roles con RAW distintos y un sintetizador; un solo coordinador es válido, pero no se inventan sesiones independientes. M01/M02 conservarán sus originales; M03 está DONE y no se recertifica. Un fallo 42501 es de permisos, no funcional. Un fallo de Train se repara por el mismo circuito, sin SQL directo ni gates desactivados.

| Checkpoint | Brazo | Algoritmos | Modo de entrada |
|---|---|---|---|
| PE10_M01 | A | SRCR base | VALIDATE_EXISTING_ORIGINAL_FIRST |
| PE10_M02 | A | D | VALIDATE_EXISTING_ORIGINAL_FIRST |
| PE10_M03 | A | M | VERIFY_IMMUTABLE_DONE_ONLY |
| PE10_M04 | A | D+M | RESEARCH_THEN_CERTIFY |
| PE10_M05 | A | C | RESEARCH_THEN_CERTIFY |
| PE10_M06 | A | D+C | RESEARCH_THEN_CERTIFY |
| PE10_M07 | A | M+C | RESEARCH_THEN_CERTIFY |
| PE10_M08 | A | D+M+C | RESEARCH_THEN_CERTIFY |
| PE10_M09 | A | E | RESEARCH_THEN_CERTIFY |
| PE10_M10 | A | D+E | RESEARCH_THEN_CERTIFY |
| PE10_M11 | A | M+E | RESEARCH_THEN_CERTIFY |
| PE10_M12 | A | D+M+E | RESEARCH_THEN_CERTIFY |
| PE10_M13 | A | C+E | RESEARCH_THEN_CERTIFY |
| PE10_M14 | A | D+C+E | RESEARCH_THEN_CERTIFY |
| PE10_M15 | A | M+C+E | RESEARCH_THEN_CERTIFY |
| PE10_M16 | A | D+M+C+E | RESEARCH_THEN_CERTIFY |
| PE10_M17 | B | SRCR base | RESEARCH_THEN_CERTIFY |
| PE10_M18 | B | D | RESEARCH_THEN_CERTIFY |
| PE10_M19 | B | M | RESEARCH_THEN_CERTIFY |
| PE10_M20 | B | D+M | RESEARCH_THEN_CERTIFY |
| PE10_M21 | B | C | RESEARCH_THEN_CERTIFY |
| PE10_M22 | B | D+C | RESEARCH_THEN_CERTIFY |
| PE10_M23 | B | M+C | RESEARCH_THEN_CERTIFY |
| PE10_M24 | B | D+M+C | RESEARCH_THEN_CERTIFY |
| PE10_M25 | B | E | RESEARCH_THEN_CERTIFY |
| PE10_M26 | B | D+E | RESEARCH_THEN_CERTIFY |
| PE10_M27 | B | M+E | RESEARCH_THEN_CERTIFY |
| PE10_M28 | B | D+M+E | RESEARCH_THEN_CERTIFY |
| PE10_M29 | B | C+E | RESEARCH_THEN_CERTIFY |
| PE10_M30 | B | D+C+E | RESEARCH_THEN_CERTIFY |
| PE10_M31 | B | M+C+E | RESEARCH_THEN_CERTIFY |
| PE10_M32 | B | D+M+C+E | RESEARCH_THEN_CERTIFY |

Detalles completos por checkpoint: [procedures manifest](./PE10_32_DONE_PROCEDURES_V1.json). Los 32 contratos se recuperan desde Supabase en `done_procedures_v1` y `source_pack_v2.checkpoint_inputs`. No confiar en una copia de Git hasta confirmar versión aplicada en Train y readback en DB.
