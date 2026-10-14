# Decisión del propietario: aceptar el nivel GPT Native en chat para C2 del análisis (V1)

Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Alcance: checkpoints `A1Q_C2..A15Q_C2`.

## Decisión

El propietario (Cristhian) respondió "si" el 2026-10-13 a las 22:46 (America/Lima) a esta pregunta: ¿aceptas que el nivel de GPT Native en chat cuente como evidencia para cerrar todo C2, con sus límites a la vista (`provider_attested=false`)?

La decisión cubre C2 y reemplaza, para ese checkpoint, la clase de evidencia esperada `REAL_EXECUTION_RECEIPT` por `OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT`. Está definida en `ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md`.

## Condiciones que siguen vigentes

- Cada unidad exige su propia captura de GPT Native ligada por hash a su paquete congelado, verificada por el verificador del nivel. Una captura de otra unidad no sirve.
- Todo cierre registra `provider_attested=false`, `real_execution_receipt=false` e `independent_review=false`. Nunca se presenta como recibo del proveedor.
- Los campos que solo emite el runtime gobernado se siguen rechazando en una captura de chat.
- **No cubre C3.** La revisión independiente exige otra conversación con paquete ciego y no se admite por esta decisión.
- No cubre A15Q_C1, que mantiene su requisito de refreeze independiente.
- La decisión es reversible hacia adelante: un recibo real del proveedor puede reemplazar este nivel en cualquier unidad.
