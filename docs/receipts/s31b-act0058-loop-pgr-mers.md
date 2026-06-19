# S31B — ACT-0058 LOOP_CONTROLADO

Evento Supabase: lf_eventos.id = 496.

Ajuste: una falla por URL no detiene todo el ciclo.

Guardrails:
- PGR: gobierno, fuente vigente, readback y cierre.
- MERS: error por URL, retry y continuidad.

Paradas del ciclo:
- MCP no disponible.
- Router no verificable.
- Fuente operativa no verificable.
- Error SQL/schema.

No detienen el ciclo:
- Falla de captura web por URL.
- URL sin evidencia suficiente.

Acción por URL fallida: marcar FALLIDO y continuar.
