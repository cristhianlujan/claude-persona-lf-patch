# Decisión del propietario: aceptar la revisión GPT Native en chat separado para C3 del análisis (V1)

Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`. Alcance: checkpoints `A1Q_C3..A14Q_C3`.

## Decisión

El propietario (Cristhian) respondió "Sí, aceptar para C3" el 2026-10-14 a esta pregunta: ¿aceptas que la revisión GPT Native en un chat separado, con paquete ciego y `provider_attested=false`, cuente como evidencia para cerrar C3 de A1Q–A14Q, igual que hiciste con C2? Su "si" anterior no cubría C3.

La decisión reemplaza, para C3 de A1Q–A14Q, la clase de evidencia esperada de revisión independiente por `OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT`, definida en `ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md`.

## Condiciones que siguen vigentes

- La revisión ocurre en un chat distinto al del productor de C2. El paquete es ciego: criterio, tres chequeos, entrada literal y dos ítems (la salida real y un señuelo) en orden determinista, sin cadena del productor ni veredicto.
- Cada unidad exige su propio paquete ligado por hash. La captura se verifica contra la captura C2 almacenada de la misma unidad.
- Si la salida real no pasa los tres chequeos, o el señuelo no falla, C3 queda PENDING.
- Todo cierre registra `provider_attested=false`, `real_execution_receipt=false` e `independent_review=false`.
- No cubre A15Q_C3 ni A15Q_C1.
- Los criterios C3 no medibles de A9, A12 y A13 requieren una enmienda aprobada aparte antes de cerrarse.
- Reversible hacia adelante: un recibo real del proveedor puede reemplazar este nivel.
