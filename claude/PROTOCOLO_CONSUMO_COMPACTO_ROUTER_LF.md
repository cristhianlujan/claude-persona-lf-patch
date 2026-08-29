# PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF

Estado: CANDIDATO v0.1  
Router rector: ACT-0001  
Consumidores: Claude y GPT

## 1. Objetivo

Reducir tiempo y consumo de contexto del Router sin alterar discovery, bloqueos, operación, contratos, pasos ni adapters. Los bytes y el tiempo son métricas comunes; los tokens se registran por modelo/tokenizador cuando estén disponibles.

## 2. Entrada obligatoria

Toda resolución entra por `public.lf_router_resolve_v1`. Cada llamada pasa `action_hint` explícito y omite por completo `target_hint`.

## 3. Proyección de ocho campos

1. `status`
2. `blocking_code`
3. `asset_code`
4. `asset_type`
5. `action_code`
6. `operation_code`
7. `operation_payload`
8. `adapter_payload`

`operation_payload` usa `operation_code` como clave y contiene `cache_hit`, `steps` y `contracts`; en hit omite los bloques. `adapter_payload` usa `asset_code` como clave y contiene `cache_hit` y `adapters`; en hit omite el bloque.

## 4. Excepciones

- Si `status='BLOCKED'`, consumir el crudo.
- Si el compacto pesa igual o más que el crudo, consumir el crudo.
- Una resolución sin `operation_code` se cuenta como solo-enrutar y no genera hit de operación.

## 5. Caché y rehidratación

- `steps` y `contracts`: caché por `operation_code`.
- `adapters`: caché por `asset_code`.
- En miss se carga el bloque una sola vez.
- En hit se conserva solo la referencia.
- El ejecutor rehidrata desde caché únicamente el bloque requerido por el paso actual.

## 6. Métricas de cierre

- `ahorro_real_pct = 100 * (raw_bytes - effective_bytes) / raw_bytes`.
- `operation_code_repetition_rate = operation_cache_hits / total_resolutions`.
- Reportar juntos resoluciones, `operation_code` distintos, `cache_hits`, BLOCKED y solo-enrutar.
- Si repetición `< 0.5`, el lote no ejercita la caché y no se concluye sobre el protocolo.
- Si ahorro `>= 50%` y repetición `>= 0.5`, proponer cierre de backlog 85/86 y promoción.

## 7. EKB y eventos

Ejecutar PRE_EKB_GATE. Las resoluciones quedan en `lf_eventos`; cada error o aprendizaje distinto y generalizable se registra enriquecido en EKB y se verifica con readback completo.

## 8. Validación controlada 2026-08-29

Lote total: 13 resoluciones, 4 `operation_code` distintos, 8 cache hits, repetición 0.6154, 84,633 bytes crudos y 23,904 bytes efectivos. Ahorro real: 71.76%. Resultado: 1 BLOCKED, 0 solo-enrutar, 8/8 campos verificados y rehidratación íntegra.

Control BLOCKED: `Crear nuevamente la skill ACT-0052`, con `action_hint='SKILL_CREATE'`, resolvió `BLOCK_TARGET_ALREADY_EXISTS`; crudo 171 bytes, compacto 257 bytes y consumo final RAW.

Segundo canario (`PERFIL-PRODUCT-DIRECTOR-LF`): 7 resoluciones, 2 `operation_code` distintos, 4 cache hits, repetición 0.5714, 53,874 bytes crudos y 13,677 bytes efectivos. Ahorro real: 74.61%. Resultado: 1 BLOCKED consumido RAW, 0 solo-enrutar, 8/8 campos verificados y rehidratación íntegra en las resoluciones compactas no bloqueadas.

Gate de dos perfiles: PASS (`PERFIL-UI-ARCHITECT-LF` y `PERFIL-PRODUCT-DIRECTOR-LF`). La propuesta de promoción y cierre de backlog 85/86 queda condicionada al review y merge del PR del protocolo.

## 9.2 Helper SQL de resolución

```sql
select public.lf_router_resolve_v1(
  p_request_text => :request_text,
  p_action_hint => :action_hint,
  p_asset_type_hint => :asset_type_hint,
  p_distribution_mode => 'ROUTER'
) as router_result;
```

`p_target_hint` no se envía, ni siquiera como `NULL`.

