# CARD: NO_HOMOLOGATION · NO_INSIGHT · NO_ALERT

> Owner: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Tipo: Card específica del dominio · Bloqueos permanentes
> Estado: CANDIDATO_READ_ONLY · Lote 20B

---

## Propósito

Declarar explícitamente qué no puede hacer este vertical slice,
para evitar confusión en operadores humanos y agentes.

---

## Bloqueos permanentes en este paquete

```
FUTURE_BLOCKED_NO_HOMOLOGATION:
  No puede homologar registros.
  No puede promover contenido a KB final.
  No puede cambiar estado de un activo a APROBADO o VALIDATED.
  Homologación requiere proceso separado con juez, evidencia y aprobación
  explícita del operador de gobernanza.

FUTURE_BLOCKED_NO_INSIGHT:
  No genera insights automáticos.
  No interpreta patrones entre registros.
  No produce análisis derivados.
  El contenido capturado es evidencia cruda — no conclusión.

FUTURE_BLOCKED_NO_ALERT:
  No dispara alertas automáticas.
  No notifica por ningún canal.
  No evalúa umbrales ni condiciones.

FUTURE_BLOCKED_NO_N8N:
  No conecta a n8n en ningún modo.
  No activa workflows automáticos.
  No invoca webhooks.

FUTURE_BLOCKED_ADMIN_OVERRIDE:
  ADMIN_OVERRIDE está bloqueado por defecto.
  Solo puede proponerse como modo futuro con:
    - actor admin identificado
    - motivo documentado
    - evidencia registrada
    - log WEB_EXTRACTION_ADMIN_OVERRIDE obligatorio
    - sin bypass de GATE_00 ni GATE_13
    - sin producción
```

---

## Qué SÍ puede hacer este vertical slice

```
✅ Capturar contenido literal de URLs catalogadas
✅ Persistir en lf_capture_records (sandbox autorizado)
✅ Registrar trazabilidad en lf_log_operativo
✅ Entregar evidencia estructurada para revisión posterior (humana)
✅ Verificar duplicados contra hashes reales en BD
✅ Detectar y registrar prompt injection (sin actuar sobre la instrucción)
✅ Ejecutar DRY_RUN para validar sin escribir
```

---

## Cuándo se revisarán estos bloqueos

Cuando el adapter pase sus evals (evals.yaml) y el judge (judge.yaml)
con evidencia real en sandbox, y el operador de gobernanza apruebe
explícitamente la remoción de un bloqueo específico.

Hasta entonces: **FUTURE_BLOCKED** es el estado de todos los modos listados arriba.
