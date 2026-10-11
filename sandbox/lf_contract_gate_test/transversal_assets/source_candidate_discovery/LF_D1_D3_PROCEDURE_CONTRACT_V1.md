# LF — Procedimiento transversal de investigación por fuentes D1–D3 (v1)

**Estado:** construido como capacidades de preparación; **NO** activado en el runtime de Hetzner y **NO** admitido para lecturas empresariales. Los casos de negocio y benchmark quedan fuera de esta fase. Autoridad: Supabase; GitHub mantiene migrations/artefactos fuente. Excel no es estado ni fuente normativa.

## Único proceso (sin motores paralelos)

1. **D1 · Descubrir**: `private.fn_lf_d1_inventory_candidates_v1` consulta `inventory.fn_lookup_v3` (índice canónico) y `private.fn_lf_d1_inventory_neighbors_v1` consulta relaciones `inventory.dependencies`. No hay nombres físicos por tarea en el algoritmo. El descubrimiento solo propone `db://schema.object` y no autoriza consultas.
2. **D2 · Admitir fuente estructuralmente**: `private.fn_lf_d2_binding_readback_v1` busca en `public.lf_activos` el mismo `canonical_source_ref`, exige binding singular VIGENTE, policy SHA activa, huella real `pg_catalog`, columnas y filtros permitidos, límite, fachada `SECURITY INVOKER` y paso de operación. Usa `inventory.fn_lookup_v3` para vigencia en vez de leer `inventory.objects.currentness` directamente. Resultado favorable **solo estructural**; NO concede `SELECT` ni acceso a datos B2B.
3. **Planificador existente**: `public.lf_targeted_evidence_acquisition_plan_v1`. Ninguna fuente sin admisión real se entrega como `available=true`. `STOP_NO_DECISION_CHANGING_EVIDENCE` significa únicamente agotamiento de los candidatos **locales** recibidos, nunca de toda D1.
4. **D3 · Decidir siguiente paso**: `private.fn_lf_d3_investigation_decision_v1` recibe el estado estructurado y propone acciones; no ejecuta efectos. Una observación de lectura proporcionada como JSON siempre requiere readback **independiente y canónico** de fachada/usuario/empresa/RLS en Supabase. Reglas genéricas: cero coincidencias dentro de un alcance ≠ inexistencia global; búsqueda incompleta → continuar; una coincidencia → investigar su estado; varias → pedir el identificador mínimo; evidencia antigua → refrescar; denegación/ausencia de binding → bloquear o conseguir evidencia autorizada.
5. **Coordinación de preparación**: `private.fn_lf_source_investigation_prepare_v1` compone D1, D2, el planificador existente y D3, por metadatos. No hace SELECT sobre filas empresariales, no pide datos del cliente ni despliega un agente. Salidas `runtime_dispatched=false`, `rows_accessed=false`, `business_data_read_authorized=false`, `final_business_answer_allowed=false`.

## Contratos y barreras de seguridad

- Solo rol `service_role` tiene EXECUTE sobre funciones privadas de **preparación**, sin permisos de negocio agregados. `anon`/`authenticated` no reciben EXECUTE. No usar `SECURITY DEFINER` para superar RLS.
- Modelo/GPT nunca suministra: estado de binding, SHA de policy, identidad JWT, permiso de empresa, autorizaciones `ALLOW/DENY` o evidencia de lectura. El adaptador de runtime deberá obtenerlos directamente de Supabase y verificar firmas/versiones actuales.
- Binding real debe apuntar a una fachada autorizada con identidad real, empresa explícita, DENY prioritario, `FORCE RLS` donde aplique, consulta parametrizada, filtro por empresa, columnas acotadas, presupuesto y recibo verificable. Hasta entonces no hay ejecución empresarial.
- No se admiten porcentajes de desempeño ni resultados E2E a partir de pruebas sintéticas. Registro de benchmark y evidencia viven solo en Supabase.
- El inventario global `LF_GLOBAL_TECHNICAL_INVENTORY_V1` aún figura `CANDIDATE_PENDING_QUALIFICATION`; la comprobación técnica solo cubrió el alcance gestionado `DATABASE_AND_REGISTRIES`. Fuentes Git/edge y admisión global no están probadas.
- El prototipo Python local del D2 no es una segunda autoridad ni ruta de ejecución: el validador Supabase es el candidato de integración.

## Estado verificable de esta entrega

Migraciones fuente: `20261011033000` D2, `20261011034000` D3, `20261011035000` coordinador. Pruebas **técnicas y reversibles**: D2 4 casos; D3 18 casos (incluye incompleto/antiguo/0/1/varios y entradas malformadas); coordinación 4 escenarios, todos sin lecturas de negocio. No se ejecutó ningún caso empresarial real.

## Fases que permanecen abiertas

- **D2 DATA PLANE:** resolver/governar `read_facade_ref` y binding VIGENTE; no fabricar asignaciones empresariales. Verificar identidad real y pertenencia; lecturas propias positivas y rechazo entre empresas; recibo y readback.
- **D3 DATA EVIDENCE:** consumir solo recibos de fachadas autenticadas verificados en Supabase antes de permitir conclusiones factuales. El camino actual es de planificación únicamente.
- **D4 RUNTIME:** adaptar dispatcher/worker Hetzner mediante gobernanza, fallback/errores, límites y observabilidad. No activar mientras falten autorizaciones.
- **D5 PRUEBA FINAL:** benchmark ciego pareado, casos reales representativos, degradaciones críticas cero, latencia/costo/calidad y aprobación de admisión.

No se debe interpretar el cierre de la construcción *de preparación* como cierre de autonomía integral.

## Currentness/rollback regression

The coordinator queries **both** existing currentness systems: the managed-snapshot
qualification and `inventory.v_managed_currentness_v1` (the clock used by
`fn_lookup_v3`). If an inventory refresh occurs inside the same SQL transaction,
the managed qualifier may see a new snapshot using `clock_timestamp()` while
v3's `now()` (transaction start) does not. The coordinator now returns
`BLOCK_INVENTORY_LOOKUP_CURRENTNESS_UNSTABLE`, **not** `NO_MATCH_IN_SCOPE`.
A reversible SQL test confirmed this block with no global exhaustion. Post-merge,
the normal metadata probes must run in a **new** transaction after the canonical
inventory refresh is committed; this is not a workaround to bypass currentness.
