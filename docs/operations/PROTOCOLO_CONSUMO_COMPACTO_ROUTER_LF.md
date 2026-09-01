# PROTOCOLO DE CONSUMO COMPACTO — ROUTER ACT-0001

Estado del documento: PROMOVIDO v1.0
Router rector: ACT-0001
Consumidores: Claude y GPT
Alcance de modo: solo `distribution_mode = 'ROUTER'`

## 1. Objetivo

Reducir el contexto que el Router propaga al modelo sin alterar discovery, bloqueos, operación, contratos, pasos, adapters ni obligaciones de Input Governance. Se mide en bytes; los tokens se registran por modelo/tokenizador cuando estén disponibles.

## 2. Entrada obligatoria

Este documento describe qué hacer con el resultado del Router **después** de haber entrado por él. No autoriza ni sustituye la entrada.

```text
ACT-0001 Router -> v_lf_fuente_operativa_busqueda -> activo canónico vigente
-> adapter si aplica -> Input Governance preflight si metadata lo exige
-> operación -> verificación -> cierre
```

ACT-0001 sigue siendo rector. No entrar directo por profiles, skills, cards, adapters, prompts ni checklists. Supabase es la fuente operativa principal. Sin verificación de Supabase o sin readback del activo vigente: bloquear.

Toda resolución entra por `public.lf_router_resolve_v1`. Cada llamada pasa `action_hint` explícito y omite por completo `target_hint`.

## 3. Proyección canónica

Ocho campos de nivel superior. Ninguno es opcional.

1. `status`
2. `blocking_code`
3. `asset_code`
4. `asset_type`
5. `action_code`
6. `operation_code`
7. `operation_payload`
8. `adapter_payload`

`operation_payload` usa `operation_code` como clave y contiene `operation_status`, `step_count`, `distribution_mode`, `cache_hit`, `steps`, `contracts` y `policies`; en hit omite los bloques cacheados. `adapter_payload` usa `asset_code` como clave y contiene `cache_hit` y `adapters`; en hit omite solo el bloque cacheable de adapters. Cuando el Router devuelve `input_governance`, `adapter_payload` conserva siempre ese objeto completo y `downstream_execution_allowed`: el receipt es por resolución y nunca entra en caché.

La normalización toma `asset_code` de `coalesce(raw.asset_code, raw.asset.codigo_activo)` y `asset_type` de `coalesce(raw.asset_type, raw.asset.tipo_activo)`. Las resoluciones listas anidan la identidad en `asset`; omitir ese fallback impide reutilizar la caché de adapters.

### Por qué `operation_status` se conserva dentro de `operation_payload`

Es el semáforo de gobernanza de la resolución y **no es constante**. Medido el 2026-08-29 en modo ROUTER: las operaciones de perfil devuelven `PRODUCCION_CONTROLADA_READ_ONLY`, mientras que `ACTUALIZACION_PERFIL_LF` devuelve `PRODUCCION_CONTROLADA`. Omitirlo hace que el consumidor no sepa si está en modo lectura o en producción controlada.

### Por qué `step_count` se conserva dentro de `operation_payload`

Es el control de integridad contra rehidratación truncada: permite detectar que la caché devolvió menos pasos de los que la operación declara.

### Por qué `distribution_mode` se conserva dentro de `operation_payload`

`policies` depende del modo, no solo de `operation_code`. Probado: con un modo fuera de la lista de un binding activo, el Router excluye la policy y una rehidratación que ignore el modo la incluiría, mostrando como requerida una policy que el Router descartó. Este protocolo fija `'ROUTER'` y lo transporta explícito para que la clave de caché y la rehidratación sean verificables.

## 4. Excepciones

- Si `status` no es `READY_TO_EXECUTE`, consumir el crudo. Esto incluye `INPUT_GOVERNANCE_REQUIRED`, `HUMAN_DECISION_REQUIRED` y `BLOCKED`; ninguno autoriza ejecución downstream.
- Si el compacto pesa igual o más que el crudo, consumir el crudo.
- Una resolución sin `operation_code` se cuenta como solo-enrutar y no genera hit de operación.

## 5. Caché y rehidratación

- `steps` y `contracts`: caché por `operation_code`.
- `adapters`: caché por `asset_code`.
- `policies`: caché por `operation_code` más `distribution_mode`.
- En miss se carga el bloque una sola vez. En hit se conserva solo la referencia.
- El ejecutor rehidrata desde caché únicamente el bloque requerido por el paso actual.
- `input_governance` y `governance_receipt` no son cacheables. Un hit de adapters no demuestra currentness ni sustituye la revisión `LIVE_CURRENT` del Router.

Consultas de rehidratación verificadas por `md5` contra la salida real del Router:

```sql
-- contracts
select coalesce(jsonb_agg(to_jsonb(c) order by c.contract_code),'[]'::jsonb)
from public.lf_operation_contracts c
where c.operation_code = :operation_code
  and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');

-- steps
select coalesce(jsonb_agg(jsonb_build_object(
   'step_id',s.step_id,'step_order',s.step_order,'execution_order',s.execution_order,
   'contract_code',s.contract_code,'purpose',s.purpose,
   'blocking_code',s.blocking_code,'status',s.status)
 order by coalesce(s.execution_order,s.step_order), s.step_id),'[]'::jsonb)
from public.lf_operation_step_contracts s
where s.operation_code = :operation_code
  and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');

-- adapters
select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
from public.v_lf_router_adapter_bindings x
where x.target_asset_code = :asset_code;

-- policies
select coalesce(jsonb_agg(to_jsonb(p) order by p.policy_role, p.policy_code),'[]'::jsonb)
from public.v_lf_operation_policy_snapshot p
where p.operation_code = :operation_code
  and :distribution_mode = any(p.distribution_modes);
```

## 6. Prohibición de `target_hint`

`target_hint` anula por completo el texto de la solicitud: el que llama pasa a decidir el activo y el Router deja de resolverlo. Probado el 2026-08-29: la frase "sistema de misiones y recompensas" con `target_hint='PERFIL-QUALITY-PACK'` resolvió Quality Pack, y "revise visualmente esta pantalla" con `target_hint='PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'` resolvió Evidence Lineage.

Usarlo para estabilizar la clave de caché anula el discovery por capacidad, contradice que ACT-0001 sea rector y elimina el fail-closed por ambigüedad. `action_hint` sí; `target_hint` no, ni siquiera como `NULL`.

## 7. Métricas de cierre

- `ahorro_real_pct = 100 * (raw_bytes - effective_bytes) / raw_bytes`.
- `operation_code_repetition_rate = operation_cache_hits / total_resolutions`.
- Reportar juntos: resoluciones, `operation_code` distintos, `cache_hits`, bloqueados y solo-enrutar.
- Si la repetición es menor a 0.5, el lote no ejercita la caché y no se concluye sobre el protocolo.
- Si el ahorro es mayor o igual a 50% y la repetición mayor o igual a 0.5, proponer cierre de backlog 85/86 y promoción.

## 8. Validación controlada 2026-08-29

Lote principal: 13 resoluciones, 4 `operation_code` distintos, 8 cache hits, repetición 0.6154, 84 633 bytes crudos y 23 904 bytes efectivos. Ahorro real 71.76%. Resultado: 1 bloqueado, 0 solo-enrutar, campos verificados y rehidratación íntegra.

Control bloqueado: `Crear nuevamente la skill ACT-0052` con `action_hint='SKILL_CREATE'` resolvió `BLOCK_TARGET_ALREADY_EXISTS`; crudo 171 bytes, compacto 257 bytes, consumo final en crudo.

Segundo canario (`PERFIL-PRODUCT-DIRECTOR-LF`): 7 resoluciones, 2 `operation_code` distintos, 4 cache hits, repetición 0.5714, 53 874 bytes crudos y 13 677 bytes efectivos. Ahorro real 74.61%.

Gate de dos perfiles: PASS sobre `PERFIL-UI-ARCHITECT` y `PERFIL-PRODUCT-DIRECTOR-LF`.

Canario de cierre v1.0: 4 resoluciones, 2 `operation_code` distintos, 2 cache hits, repetición 0.5000, 21 894 bytes crudos y 10 813 bytes efectivos. Ahorro real 50.61%, 0 bloqueados, 0 solo-enrutar y ocho campos superiores verificados. El cálculo normaliza la identidad anidada del activo antes de aplicar la caché de adapters.

### Verificación histórica del delta introducido en v0.2

Agregar `operation_status`, `step_count` y `distribution_mode` a la proyección cuesta 96 a 105 bytes por resolución. Medido en modo ROUTER sobre seis resoluciones:

| Caso | Crudo | Proyección v0.1 | Proyección v0.2 | Delta | Ahorro v0.1 | Ahorro v0.2 |
|---|---|---|---|---|---|---|
| UI Architect | 7408 | 333 | 438 | +105 | 95.50% | 94.09% |
| Product Director | 7443 | 347 | 452 | +105 | 95.34% | 93.93% |
| Gamification | 7493 | 367 | 472 | +105 | 95.10% | 93.70% |
| Quality Pack | 4455 | 333 | 438 | +105 | 92.53% | 90.17% |
| Evidence Lineage | 4503 | 365 | 470 | +105 | 91.89% | 89.56% |
| Actualización perfil | 11810 | 338 | 434 | +96 | 97.14% | 96.33% |

El costo observado fue de 1.4 a 2.4 puntos porcentuales de ahorro. La v1.0 conserva esos tres valores dentro de `operation_payload`, sin ampliar los ocho campos superiores. Las cifras de la sección 8 se mantienen por encima del umbral de promoción.

Rehidratación del payload completo desde la proyección v0.2, comparada por `md5` contra la salida real del Router en modo ROUTER: 6 de 6 idénticas, ninguna clave distinta.

## 9. Resolución canónica

### 9.1 Regla de invocación

Pasar `action_hint` explícito y omitir completamente el argumento `target_hint`.

### 9.2 Helper SQL de resolución

```sql
select public.lf_router_resolve_v1(
  p_request_text => :request_text,
  p_action_hint => :action_hint,
  p_asset_type_hint => :asset_type_hint,
  p_distribution_mode => 'ROUTER'
) as router_result;
```

### 9.3 Continuación gobernada

Si un adapter resuelto declara `input_governance_receipt_required=true`, el consumidor obedece el estado del Router:

1. `INPUT_GOVERNANCE_REQUIRED`: invocar `input-governance-agent-v1` con el `pantalla_id` y `consumer` entregados en `input_governance.dispatch`.
2. Volver a resolver por `public.lf_router_resolve_v1`; no continuar con el resultado anterior.
3. Continuar solo con `READY_TO_EXECUTE`, `input_governance.status=READY`, `decision=PASS`, `continuation_allowed=true` y un `governance_receipt` vigente.
4. Persistir el receipt con la ejecución del perfil/adapter. Cualquier otro estado bloquea sin llamada al perfil.

Queda prohibido rehidratar adapters directamente para saltar este preflight o considerar un run histórico como receipt vigente.

## 10. EKB y eventos

Ejecutar PRE_EKB_GATE. Las resoluciones quedan en `lf_eventos`; cada error o aprendizaje distinto y generalizable se registra enriquecido en EKB y se verifica con readback completo.

## 11. Límites conocidos

- El ahorro depende de la tasa de repetición de `operation_code` y `asset_code` dentro de la sesión, y el Router no la garantiza porque es sensible al fraseo. Ese es el patrón registrado en EKB `GOV-038`.
- Este protocolo solo está validado en modo ROUTER. Cualquier otro `distribution_mode` requiere volver a verificar la rehidratación de `policies`.
- Las mediciones son en bytes, no en tokens facturados.
- No se midió latencia ni número de llamadas.

## 12. Cierre de promoción

- Backlog 85 `COMPACT-ROUTER-PADDING-001`: criterio de cierre cumplido; guardrail de tamaño incorporado en la sección 4.
- Backlog 86 `COMPACT-ROUTER-CACHEKEY-002`: criterio de cierre cumplido; caché y prohibición de `target_hint` incorporadas en las secciones 5 y 6.
- EKB `GOV-039`: resuelto por la publicación canónica en `docs/operations/` y el localizador compatible en `claude/`.
