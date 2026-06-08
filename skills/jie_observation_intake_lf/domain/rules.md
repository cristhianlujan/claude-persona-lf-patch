# REGLAS OPERATIVAS — JIE Observation Intake LF

> Estado: CANDIDATO_READ_ONLY · Lote 20B

---

## Reglas de dominio (no negociables)

```
RULE_D01: No inferir campos no visibles en el texto.
          Campo no visible → NOT_FOUND. Nunca completar.

RULE_D02: No setear claims_json[].verificado_fuente_primaria = true.
          El adapter nunca accede a fuentes primarias.

RULE_D03: No declarar extraction_successful=true sin readback confirmado (GATE_13).

RULE_D04: flow_terminated=true en todos los caminos. Sin excepción.

RULE_D05: Anti-duplicado obligatorio antes de cualquier INSERT (GATE_07).
          Hashes fixture en fixtures/antiduplicate_hashes.yaml.

RULE_D06: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY es el único modo
          que escribe en BD. Solo en sandbox autorizado.

RULE_D07: ADMIN_OVERRIDE bloqueado por defecto.
          Solo puede habilitarse como modo futuro con actor, motivo,
          evidencia, log y sin bypass de gates críticos.

RULE_D08: Toda escritura queda en lf_capture_runs + lf_capture_records.
          No escribir en lf_capture_judge_results ni en producción.

RULE_D09: Todo log usa log_key registrado en lf_log_config (GATE_10).
          No loguear con log_key no controlado.

RULE_D10: No homologar. No generar insight. No generar alert.
          No conectar n8n. No actualizar KB final.
          Cualquier referencia a esto → FUTURE_BLOCKED_NO_HOMOLOGATION.
```

---

## Reglas de arquitectura

```
RULE_A01: El dominio vive limpio. Sin infraestructura en domain/.

RULE_A02: Commands para operaciones con posible escritura.
          Queries para lectura, readback y verificación.

RULE_A03: El adapter web_article_capture vive como hijo de esta skill.
          No como adapter global huérfano.

RULE_A04: Cards específicas viven en cards/.
          Cards genéricas van a learning_cards/ (fuera de este paquete).

RULE_A05: Shared solo para lo realmente reutilizable entre skills.
          En este paquete no hay shared.

RULE_A06: GitHub legible sin necesidad de volver a Supabase
          para entender ownership. El path declara la pertenencia.
```

---

## Reglas de trazabilidad

```
RULE_T01: Todo event se registra en lf_eventos con entidad_codigo del activo.

RULE_T02: Supabase es la fuente operativa e índice rector.
          GitHub es la fuente autora de los archivos.

RULE_T03: No declarar estados que no están en states.md.

RULE_T04: Evidencia requerida por gate definida en commands/capture_web_article/gates.md.
```
