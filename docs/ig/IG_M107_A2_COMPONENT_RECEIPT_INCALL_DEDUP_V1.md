# M10.7 A2 — Deduplicación de recibos de componentes en una invocación (candidato)

## Estado y límites
Artefacto G0 de optimización **candidata**. No sustituir la función canónica sin prueba de equivalencia exacta y seguridad ante autoridad mutable. Este cambio NO habilita reutilización entre llamadas del Validator, NO reemplaza G2B, NO altera triggers, reglas ni CP3.

Función candidata nueva: `programacion.fn_input_design_binding_graph_v2_candidate_v1(integer)`. Parte de la definición vigente y hace una única precarga de `fn_input_component_binding_receipt(token,design_system)` por **token distinto** obtenido de los tres conjuntos de asociaciones. Usa solo memoria local JSONB de la invocación, no tabla ni caché persistente. Mantiene orden/campos, identidad, valores y el conteo de fallas **por asociación** (no por token).

Para pantalla 43: 40 asociaciones → 12 tokens únicos; la versión vigente contiene nueve lugares estáticos de invocación dentro de sus tres construcciones y tres sumas, uno o dos por asociación según propósito. El posible ahorro se mide, no se infiere.

## Gobierno
Router ACT-0001 → ACTUALIZACION_DB_LF → Git PR → Migration Train → ledger → readback. Una sola migration SQL en el PR; sin EXECUTE PUBLIC y sin consumidor activado. EKB primero: `IG-M107-ALL-STAGES-QUERY-INVENTORY-007`, `IG-M107-TRIGGER-ROLLBACK-PROFILE-008`, `IG-SHADOW-V2-CONTEXT-REUSE-001`.

## Prueba G0/A2
Precondición MD5 canónico exacto. 3 pantallas representativas 1/43/58, pares alternados original/candidato, JSONB exact_equal y SHA exacto; integridad/summary conservados, negativo pantalla inexistente. Medir tiempos de funciones completas, no extrapolar al Validator ni p90. Fallar la migración si el resultado semántico diverge. Si no mejora, conservar candidato no activo y analizar costo antes de promover. Registrar EKB únicamente tras las pruebas. Las pruebas no modifican fuentes.

## Activación posterior
La sustitución canónica queda reservada a un PR separado con evidencia de mejora estable y protección de vigencia; G2B sigue siendo condición para reutilizar autoridad mutable entre llamadas. El CP3 requiere tiempos ejecutados, negativos, ventana congelada y lectura as-of.