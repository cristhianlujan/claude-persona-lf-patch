# D-04 · Revisión adversarial propia (NO independiente)

## Defectos comprobados y corregidos

- **F-01 (semántica de propuestas, alto):** `excluded_proposals` contiene 7 referencias, pero únicamente PG-07.C7 no es checkpoint del baseline; los otros seis son propuestas de cambio textual sobre checkpoints obligatorios. La revisión separa `excluded` (referencias) y `excluded_checkpoint_ids` (IDs no incluidos en baseline). Se agregaron regresiones.
- **F-02 (integridad accidental, medio):** el `Inventory` original exponía mappings modificables pese al dataclass frozen. Se encapsularon con `MappingProxyType`, conservando tuplas/frozensets.
- **F-03 (falsa autoridad, crítico):** un consumidor podía construir `provenance='PROVIDER_VERIFIED'` y solicitar `verify_closure(..., operational=True)`, obteniendo un cierre operacional sin autenticación de proveedor. El núcleo puro ahora **bloquea siempre el cierre operacional** (`EXTERNAL_CLOSURE_AUTHORITY_NOT_INTEGRATED`). También bloquea acreditación operacional en transiciones de éxito y N/A hasta que exista una autoridad real ajena al núcleo.
- **F-04 (entrada, medio):** se añadió un límite de tamaño de archivo de 2 MB, validación del formato de canonicalización y tipo de raíz.

## Riesgos futuros NO corregidos deliberadamente (fuera de alcance)

- Recibos son declaraciones estructurales sin firma criptográfica ni readback autorizado; una tupla sintética se puede generar localmente, por eso no existe camino operacional.
- Las decisiones N/A no se verifican mediante fuente externa; el cierre sigue bloqueándolas.
- PG-00 es prerrequisito externo versionado y su certificación sigue nula; cierre operacional imposible en este lote.
- No se define atomicidad de state store, replay, rollback ni materialización de eventos. No hay persistencia ni scheduler.
- El contrato no puede verificar que una cadena `provider_ref` represente un proveedor real; ningún PASS local es evidencia operacional.

## Cobertura adversarial

Inspección de: saltos ilegales, dependencias sin evidence, receipts foreign run/head/context, SKIPPED, N/A, FAILED/BLOCKED, invalidación transitiva, checkpoint duplicate, cierre REQUIRED incompleto, mutación accidental, serialización JSON con claves duplicadas, doble arista, tamaño de entrada y suplantación de provenance. La prueba no reemplaza code review independiente.
