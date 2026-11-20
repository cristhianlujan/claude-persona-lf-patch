# Contrato de auditoría profunda V1

## Entradas

Exigir repository, base_commit, objective, read_scope, write_scope, entrypoints,
consumer_targets, authority_refs, acceptance_criteria y evidence_destination.
Distinguir autoridad declarada y verificada. El handoff autoriza este candidato,
sus pruebas y PR; no reparaciones funcionales reales, catálogo ni promociones.

## Comportamiento

Ejecutar seis fases. Conservar inventario, grafo de dependencias, tabla de
estados, mapa de campos y ledger de evidencia. Seguir cada campo origen →
transformación → transporte → consumidor → decisión. No adivinar fuente de datos
faltantes. Schema y documentación no sustituyen al consumidor real.

La auditoría combina modelo nativo y pruebas; las ayudas AST generan candidatos
acotados hasta que evidencia completa los confirme. Separar defecto de mejora
opcional. No convertir un fallo de contenido en bloqueo del transporte válido.

## Estados

CONFIRMED: defecto demostrado mediante reproducción o prueba estática completa
con consumidor y fuentes resueltas. HYPOTHESIS: indicio con incertidumbre.
NOT_VERIFIED: prueba/fuente no disponible. FIX_VERIFIED: before/after real,
negativos y readback del alcance probado. Fixture corregida no significa LF
reparado. `kind=OPTIMIZATION` identifica una mejora opcional.

## Autoridad

Esta ejecución mantiene promotion_authorized=false. Una auditoría futura deriva
la decisión de la autoridad verificada, no de flags del caller. Validez,
independencia y permiso de efecto son independientes entre sí. El pase contextual
vale donde la política lo acepte; aislamiento verificado del mismo modelo puede
acreditar independencia. No inventar contextos, llamadas, recibos ni permisos.

## Salida y cierre

Cumplir schemas/output.schema.json. Entregar al siguiente actor causa, archivos,
funciones, datos, corrección, impacto, prueba y acción autorizada. No trasladar
investigación que ya era posible. Exigir diez pares defectuoso/correcto,
negativos de frescura/identidad/sha/tenant, piloto Paso70 sin efectos, prueba de
generalización sin revelar respuestas, suite, PR y CI exact-head. Si falta algo,
registrarlo pendiente; no cerrar solo por existencia de archivos.
