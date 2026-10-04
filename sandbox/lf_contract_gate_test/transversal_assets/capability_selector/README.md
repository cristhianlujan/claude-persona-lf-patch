# CAPABILITY_SELECTOR v1.0.0

Capability transversal, domain-agnostic y propiedad de `SUPER_ADMIN`.

## Contrato

Entrada: `signals`, `catalog`, `policy`.

Salida exacta: `selected_capabilities`, `reasons`, `fallback_state`.

Estados deterministas: `CLEAR`, `MULTI`, `NO_SIGNAL`, `CONTRADICTORY`, `CAPABILITY_FAILURE`.

## Límites

- Multi-label está permitido.
- Solo selecciona por `signal_type` tipado; no conoce dominios, pantallas, familias, métodos ni modelos.
- `NO_SIGNAL`, contradicción y fallo retornan el `safe_fallback` configurado por el consumer.
- `rank` y `confidence` no autorizan ejecución.
- No decide admisión ni permiso. `SAFE_CHANGE_ADMISSION` es una responsabilidad separada.
- No vuelve a calcular tipado ni vigencia: consume señales tipadas por `TYPED_EVIDENCE_REGISTRY` y estado de catálogo derivado de `CURRENTNESS_AUTHORITY`.

## Consumers de prueba

- No-IG: `non_ig_consumer_fixture_v1.json`.
- IG: `ig_m5_4_selector_binding_v1.json`; contiene solo binding/policy del consumer y mantiene la lógica genérica fuera de M5.4.

## Verificación

`python test_capability_selector_v1.py`

Resultado esperado: `PASS_T_SELECT_CAPABILITY_SELECTOR_V1 checks=9`.

La entrega es repository-bound y no activa runtime, producción ni permisos de ejecución.
