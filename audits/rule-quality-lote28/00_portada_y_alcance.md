# LOTE 28 — Plan documental de cierre: Motor de Input Governance y Contenido

**Clasificación:** PLAN / SUGERENCIA / REQUIERE_REVISION_SEMANTICA. **No es ejecución ni aprobación.**
**Base fija:** commit `4c3e376c62a3ae488d1c031ba7043d686919a65d`, repo `cristhianlujan/claude-persona-lf-patch`.
**Rama aislada:** `lf/issue-3779-lote28-blocker-closure-plan-v1`.
**Fuentes primarias:** `audits/rule-quality-lote21/02_matriz_bloqueos_produccion.md` y `04_go_no_go_firmable.md`, más `03_tablero_12_etapas.md`, `01_registro_unico_decisiones.md` y `07_manifest.md` del mismo lote.

## Separación de alcance acordada para el plan L28 (no cambio al L21)
- **Motor / gate de pase a producción de IG: 9 bloqueos** — `B02_RUN_SCOPE`, `B03_RUN_EFFECTS`, `B06_OWNER`, `B07_SCHEMA`, `B08_IDENTITY`, `B09_E2E`, `B12_LEGACY`, `B13_BACKUP`, `B14_RESTORE`. **Estado actual 0/9 cerrados**.
- **Contenido / avance gobernado paralelo por IG: 5 bloqueos** — `B01_MFA`, `B04_FAMILY`, `B05_RULES`, `B10_BUSINESS`, `B11_LEGAL`. **Estado actual 0/5 cerrados**. Sus decisiones/firma son registro documental, **no condición del GO técnico del motor**; tampoco autorizan habilitar esas funcionalidades en producción.
- **GO técnico de IG**: nueve gates Motor (`G01,G02,G03,G04,G08,G09,G10,G11,G12`) más evaluación/autorización específica `G15-MOTOR`; sin arrastrar cierre formal de Contenido (`G05,G06,G07,G13,G14`) ni las firmas de Contenido.
- **Dependencias cruzadas técnicas intactas y expresas:** B04→B07 (interfaz/modelo familias), B05→B12 (baseline/regresión), B01→B09 (control fail-closed cuando el ensayo afecte Login). Se exige la **evidencia técnica del contrato o fallback seguro**, no la aprobación/cierre integral del bloqueo de Contenido. Si la prueba falla, se bloquea el gate Motor correspondiente; nunca se elude auth, RLS o seguridad.
- Este alcance modifica **el plan L28**, no la fuente firmable L21 ni los contratos desplegados. Si algún control oficial exige todavía 14/14, su ajuste requiere una operación gobernada separada. Ver `07_separacion_motor_contenido.md`.

## Resultado esperado — NO resultado acreditado
1. Orden y dependencias reales de B01–B14, incluidas dependencias de permisos y proveedores.
2. Siete solicitudes **listas para copiar y enviar** (IG, dueño, Producto/QA, Legal, Seguridad, Operaciones e Infra); **ninguna enviada**.
3. Catorce plantillas individuales **vacías**, sin firma, evidencias ni veredictos.
4. Tableros **Motor 0/9**, **Contenido 0/5**, global histórico **0/14**, y 12 etapas × 3 escenarios del L21.
5. Partición clara: IG / decisión del dueño / terceros y áreas externas.
6. Mapeo íntegro G01–G15 → bloqueos, separación de gates Motor/Contenido y G15 de release técnico.

## Límites explícitos
- Solo documentos dentro de `audits/rule-quality-lote28/`. Ningún SQL ejecutado, DML/DDL, cambio en Supabase, permiso, política, regla, perfil, función o RUN; ninguna operación de producción, cambio de fuente oficial ni merge.
- `NO-GO` técnico de IG actualmente (Motor **0/9**). Contenido **0/5**; agregados históricos **0/14** y **0/15** gates acreditados; **0/32** firmas L21 en las fuentes leídas. Las decisiones conversadas Q01–Q12 están en estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`; no equivalen a APROBADO/VIGENTE ni autorizan escritores. El total 0/32 es trazabilidad documental, NO fórmula del GO de Motor.
- Los 4 permisos nuevos citados por el dueño son una **brecha reportada por el usuario**, aún sin SELECT/readback propio de `lf_ops.permisos`; se tratan como **ausentes a validar**, nunca como permisos otorgados.
- Evidencia PG18 L18/L20 **REAL_EN_SANDBOX 15/36 (41,7%)**; `SINTETICO 14/36`; `NO_PROBADO 7/36`. E2E productivo acreditado **0/36** (no implica 0% de implementación).
- Los cuatro gates MD5 de PG18 deben permanecer inalterados: apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8_guard `522d12f0843be1da3c785cef3c0bf3fc`. Son **readbacks documentados en L21**, no MD5 medidos de nuevo en este lote.
- El EKB V1.4 provisto es `CANDIDATO VERIFICADO PARCIALMENTE`. Contratos y código desplegados tienen prioridad. Arquitectura objetivo: Usuario → ACT-0001 → Perfil → RUN → pasos → IG si aplica → validación → juez → registro → cierre.
- Autoría de este lote: asistencia GPT-6; **no se acredita identidad de Claude ni juez independiente**.

## Índice documental
- `01_camino_critico_y_dependencias.md` — grafo, gates y rutas en paralelo.
- `02_pedidos_por_responsable.md` — 7 comunicaciones no enviadas con retorno exigible.
- `03_decisiones_pendientes_y_permisos.md` — Q01–Q12 conversadas sin firma y faltantes.
- `04_tablero_bloqueos_y_12_etapas.md` — 14 bloqueos y tablero reproducido L21.
- `05_mapeo_go_no_go.md` — G01–G15 sin marcar.
- `06_manifest_y_protocolos.md` — trazabilidad y criterios de uso de plantillas.
- `07_separacion_motor_contenido.md` — alcance de GO de IG y dependencias técnicas cruzadas, sin alterar fuentes L21.
- `08_readback_live_release_scope.md` — lectura SELECT de contratos vivos y límites de G15.
- `09_spec_candidata_g15_motor.md` — especificación futura y 12 regresiones negativas/positivas; NO_APLICAR.
- `recibos/B01_...md` hasta `recibos/B14_...md` — formularios vacíos.

