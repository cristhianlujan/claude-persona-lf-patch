# LOTE 28 — Plan de cierre por entorno y responsabilidad

**Estado:** DOCUMENTAL / NO-GO / SIN FIRMAS ACREDITADAS. Supabase actual temporal, producción real futura. No ejecutar SQL, RUN ni cambiar contratos oficiales.
**Origen:** `4c3e376c62a3ae488d1c031ba7043d686919a65d` y documentación L21 intacta.
**Rama:** `lf/issue-3779-lote28-blocker-closure-plan-v1`.

## Tres grupos, ninguno cerrado
| Grupo | IDs exactos | Bloqueos cerrados | Función |
|---|---|---:|---|
| **MOTOR (base temporal)** | B02, B03, B06, B07, B08, B09, B12 | **0/7** | Únicos bloqueos para evaluar GO técnico de Input Governance en base temporal |
| **CONTENIDO** | B01, B04, B05, B10, B11 | **0/5** | IG tramita en paralelo; sus firmas son documentales, no vetan pase de motor |
| **INFRAESTRUCTURA (base final)** | B13, B14 | **0/2** | Backup/PITR/restore de producción real; no son gates de pase del motor temporal |
| **TOTAL L21 preservado** | B01–B14 | **0/14** | Estado general sin cambio |

**G15-MOTOR temporal (propuesta documental, NO DESPLEGADA):** G01, G02, G03, G04, G08, G11, G12 + autoridad de liberación técnica y readback. **G09/G10** pasan a evaluación de Infraestructura final; el G15 original L21 (14/32) no se modifica. No se presume que la ruta oficial admita 7/7 sin cambio gobernado.

## Decisión del dueño en conversación (sin firma)
- El proyecto Supabase actual es **temporal** y se migrará a una base real de producción futura.
- **B13 tiene declaración de evidencia:** panel Supabase señala 7 backups físicos diarios, último el **12-nov-2026 a las 09:37 UTC**. No se adjuntó comprobante verificable del panel ni se contrastaron IDs/checksums/restaurabilidad. **NO SE CIERRA B13**.
- Para cambios en la base temporal se **exige preimagen con hash por cada cambio**, scope, diff y readback, y rollback seguro.
- **No se contrata PITR ni se crea proyecto Supabase de prueba para la base temporal.** Las pruebas de SQL PG18/PG17.6 son en entornos locales/CI aislados, NO proyectos Supabase.
- PITR y **B14 restauración real probada** se evalúan en la **base final**. No afirmar hoy cobertura, política, RPO/RTO, restauración o aprobación de esa futura infraestructura.
- PR **#3803** incluye script inverso en carpeta sandbox, NO migración aplicada automáticamente. El código candidato sigue DRAFT y no autoriza despliegue.

## Dependencias y restricciones
- B02→B03→B09; B06-D→B08→B06-A→B09; B08+B05-baseline→B12→B07→B09.
- Dependencia cruzada B04→B07 = contrato/interfaz verificable; B05→B12 = baseline semántico; B01→B09 si Login = MFA **fail-closed**, sin firma integral de Contenido.
- En la **base final** B13→B14→decisión de migración/despliegue (incluye rerevisión de B07); en la temporal, B07 exige preimagen SHA + rollback probado + evaluación de pérdida, no cierre B14 de base temporal.
- Ninguna regla, pago, MFA o texto legal no aprobado se vuelve publicable por GO técnico del motor.
- Sin fechas inventadas ni plazos comprometidos, sin cambio a 14 plantillas, sin tocar RUN.
- EKB V1.4 candidato parcialmente verificado, contratos/código desplegados prevalecen. Sin identidad Claude ni juez independiente acreditados.

## Índice de entrega
- `01_camino_critico_y_dependencias.md`: dependencias y caminos Motor/Contenido/Infra.
- `02_pedidos_por_responsable.md`: solicitudes por responsable, ninguna enviada.
- `03_decisiones_pendientes_y_permisos.md`: Q01–Q12 sin firma.
- `04_tablero_bloqueos_y_12_etapas.md`: 0/7, 0/5, 0/2 + evidencia PG18 histórica.
- `05_mapeo_go_no_go.md`: 15 criterios clasificados.
- `06_manifest_y_protocolos.md`: trazabilidad y readback.
- `07_separacion_motor_contenido.md`: separación por entorno actualizada.
- `08_readback_live_release_scope.md`: SELECT histórico L28, sin permiso de producción.
- `09_spec_candidata_g15_motor.md`: spec candidata 7/7, no aplicar.
- `10_decision_base_temporal_migracion_y_rollback.md`: nueva decisión pendiente de firma y PR #3803.
- `11_resultado_pr3803_rollback_ci.md`: CI verificado PG18/PG17.6, PASE/clasificación, SHA y límites.
- `recibos/B01...B14`: 14 formularios originales vacíos e intactos.
