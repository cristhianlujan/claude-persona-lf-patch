# SALY / LF Creative F3 — plan ejecutable de compilación y transporte

Fecha: 2026-11-28  
Alcance: F3-A compilación + F3-B transporte. Solo plan verificable; no implementación, diseño, claims ni cambios de BD.

## Dependencias de entrada

- PR2 LF F1 enablement desplegado por Merge Train y readback de funciones/ACL.
- PR3 semantic QA del ítem 27 desplegado después de PR2.
- Contrato semántico del ítem 27 con 5 checks LF_SEM_* y hash de original_messages `78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40`.
- Contexto, fuentes y hashes resueltos por la ruta gobernada.
- HOST01/HOST02 se consideran PENDIENTES hasta prueba real; no se infiere PASS desde SQL.

## F3-A — Compilación

**Objetivo medible:** producir un handoff sellado y determinista a partir del pedido gobernado, sin perder significado ni introducir campos contractuales ad hoc.

### Secuencia

1. Leer el item/work packet admitido y su semantic_qa.
2. Compilar el prompt usando el contrato vigente y las fuentes congeladas.
3. Calcular `prompt_sha256` sobre los bytes UTF-8 exactos que se van a transportar.
4. Vincular el prompt al `contract_sha256`/snapshot vigente ya existente.
5. Ejecutar preflight determinista y revisión semántica independiente.
6. Entregar al transporte solo si no existe bloqueo.

### Criterios de aceptación

| ID | Evidencia ejecutable | PASS |
|---|---|---|
| F3A-01 | Compilación del ítem 27 | prompt no vacío y hash SHA-256 válido |
| F3A-02 | Dos compilaciones con el mismo input | bytes y `prompt_sha256` idénticos |
| F3A-03 | Cobertura LF_SEM_* | los 5 checks quedan evaluables contra el prompt/artefacto; ninguno omitido |
| F3A-04 | Significado de montos | S/ 189.00 = cuota mensual, 12 meses, S/ 2,268.00 = total; cero cifras nuevas |
| F3A-05 | Transferencia | permanece `Tu deuda de BBVA pasa a Finanty` |
| F3A-06 | Carta | permanece condicionada a cerrar la deuda y visible antes del CTA |
| F3A-07 | Acción | CTA exacto `Cerrar mi deuda y recibir mi carta ahora` |
| F3A-08 | Integridad | alterar 1 byte del prompt después del sellado bloquea por hash |
| F3A-09 | Repetibilidad | misma evidencia en PG17 y sin escribir producción |
| F3A-10 | Contrato | no se agregan campos de contrato nuevos para resolver diagnóstico |

**Gate F3-A:** 10/10 PASS. Cualquier omisión semántica o hash distinto = BLOCKED.

## F3-B — Transporte nativo

**Objetivo medible:** transportar exactamente el prompt y los adjuntos autorizados; el host debe verificar bytes antes de cualquier transmisión.

### HOST01 — checksum positivo

Definición vigente: **los bytes efectivos descargados deben coincidir con el checksum oficial**.

Prueba:
1. El envelope entrega referencia + SHA-256 esperado.
2. El host descarga los bytes exactos de la fuente.
3. Calcula SHA-256 local.
4. Compara hash local vs hash oficial antes de construir/enviar el request.
5. Solo con igualdad puede avanzar.

PASS observable:
- `downloaded_sha256 == expected_sha256`.
- El archivo transmitido es exactamente el archivo cuyo hash fue validado.
- La evidencia conserva referencia, hash esperado, hash calculado y tamaño de bytes.
- No existe sustitución silenciosa de archivo.

### HOST02 — checksum negativo / fail closed

Definición vigente: **si los bytes son incorrectos, debe impedirse la transmisión**.

Prueba:
1. Sustituir el archivo por bytes diferentes manteniendo la misma referencia lógica.
2. El host calcula un SHA-256 distinto.
3. Debe abortar antes de invocar al proveedor.

PASS observable:
- `downloaded_sha256 != expected_sha256`.
- contador de llamadas al proveedor = 0;
- `native_transmitted=false`;
- no receipt de proveedor ni estado DONE;
- error explícito de integridad y evidencia del hash divergente.

### Criterios adicionales de transporte

| ID | Evidencia ejecutable | PASS |
|---|---|---|
| F3B-01 | HOST01 | checksum correcto habilita la siguiente etapa |
| F3B-02 | HOST02 | checksum incorrecto bloquea antes de transmitir |
| F3B-03 | Prompt | hash de bytes enviados = `prompt_sha256` sellado |
| F3B-04 | Adjuntos | cada adjunto tiene hash verificado antes del envío |
| F3B-05 | Provider call | una sola llamada por attempt autorizado; idempotencia verificable |
| F3B-06 | Receipt | receipt real se vincula a run/attempt/contract/prompt/artifact |
| F3B-07 | Fallo provider | no produce DONE ni PASS semántico |
| F3B-08 | ACL | el host usa la autoridad mínima existente; cero grants nuevos por defecto |
| F3B-09 | Trazabilidad | request/response se registran sin secretos ni bytes sensibles en logs |
| F3B-10 | Separación | compilar, transmitir, recibir artefacto y aprobar siguen siendo gates distintos |

**Gate F3-B:** HOST01 + HOST02 + F3B-03..10 = 10/10 PASS. HOST01/02 no pueden cerrarse por inspección estática.

## Orden de ejecución

`PR2 deploy/readback → PR3 deploy/readback → F3-A 10/10 → HOST01 → HOST02 → F3-B 10/10 → transporte habilitable`

## Evidencia mínima de cierre

- SHA de commit y workflow run PG17.
- hashes de prompt/contrato y checks semánticos evaluados.
- prueba HOST01 con hash igual.
- prueba HOST02 con hash distinto y **0 llamadas** al proveedor.
- readback de ACL y ausencia de grants nuevos.
- EKB actualizado si aparece un error, falso PASS o diferencia local/producción.

Mientras falte cualquiera de esos elementos el estado es **NO PROBADO**, no PASS.
