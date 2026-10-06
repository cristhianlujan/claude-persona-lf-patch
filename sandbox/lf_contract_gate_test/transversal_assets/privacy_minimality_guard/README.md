# PRIVACY_MINIMALITY_GUARD

Capacidad transversal LF para decidir, de forma determinista y fail-closed, si una operación de datos respeta necesidad declarada, autoridad demostrada y minimalidad.

## Propósito

Evita que un consumer capture, lea, almacene, use, comparta o trackee más información de la necesaria.

No decide la base legal, no administra consentimiento, no concede permisos de base de datos y no sustituye controles de acceso.

## Ownership y alcance

- Capability: `PRIVACY_MINIMALITY_GUARD`
- Owner: `SUPER_ADMIN`
- Versión inicial: `1.0.0`
- Tipo: `TRANSVERSAL`
- IG: consumer, no owner
- Entry guard: `ORCHESTRATOR_EXECUTION_GUARD_V1`
- T-PRIVACY checkpoint: `GENERIC_CONTRACT`
- Runtime/production activation: fuera de alcance

## Contrato

Entrada:

```json
{
  "consumer_ref": "OPAQUE_CONSUMER_ID",
  "operation": "COLLECT|READ|STORE|USE|SHARE|TRACK|PROCESS",
  "need": {
    "state": "DECLARED|NOT_DECLARED|UNKNOWN",
    "ref": "need://..."
  },
  "authority": {
    "state": "VALID|INVALID|UNKNOWN",
    "ref": "authority://...",
    "context_ref": "decision-context://..."
  },
  "requested_items": ["canonical_item_a"],
  "necessary_items": ["canonical_item_a", "canonical_item_b"]
}
```

Salida: `PASS | BLOCK | UNKNOWN`.

### PASS

Solo ocurre cuando:

1. `need.state=DECLARED` y existe `need.ref`.
2. `authority.state=VALID` y existe `authority.ref`.
3. Todos los `requested_items` están incluidos en `necessary_items`.

### BLOCK

- `NEED_NOT_DECLARED`: no existe necesidad declarada.
- `AUTHORITY_INVALID`: la autoridad suministrada por el caller es inválida.
- `OVERTRACKING`: hay elementos solicitados que no son necesarios.

El resultado incluye `excess_items` para hacer accionable el bloqueo.

### UNKNOWN

Falta información suficiente o una autoridad/need está en estado desconocido. `UNKNOWN` nunca autoriza ejecución: `authorized_to_proceed=false`.

## Límites deliberados

La capability **no determina** si una base legal o consentimiento es correcto. Ese juicio debe venir de la autoridad correspondiente y se consume como evidencia.

Tampoco reemplaza:

- `DECISION_CONTEXT_ASOF`: conserva el contexto/autoridad de una decisión.
- `CURRENTNESS_AUTHORITY`: verifica vigencia.
- `TYPED_EVIDENCE_REGISTRY`: tipa/valida evidencia.
- `TYPED_DATA_ACCESS`: aplica límites técnicos de acceso/overfetch.

Estas capacidades son complementarias; `PRIVACY_MINIMALITY_GUARD` cubre la decisión que faltaba: **need + authority + minimality**.

## Negativos obligatorios

La migración prueba fail-fast:

- tracking sin need declarado => `BLOCK/NEED_NOT_DECLARED`
- autoridad inválida => `BLOCK/AUTHORITY_INVALID`
- autoridad desconocida => `UNKNOWN` y no autoriza
- requested > necessary => `BLOCK/OVERTRACKING`
- requested subset necessary => `PASS`

## Fuentes

- `supabase/migrations/20261006133051_t_privacy_minimality_guard_v1.sql`
- `public.lf_privacy_minimality_guard_evaluate_v1(jsonb)`
- `public.lf_privacy_minimality_guard_result_valid_v1(jsonb)`
- `supabase/migrations/20261006134500_t_privacy_action_spec_current_reconcile_v1.sql` — reconcilia el checkpoint `GENERIC_CONTRACT` contra la capability CURRENT; no recrea ni promueve la capability.
