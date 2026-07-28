# Protocolo normativo de descomposicion de pantallas

Juez asociado: `J02_SCREEN_DECOMPOSITION`.

## Secuencia obligatoria

1. Recuperar pantalla, modulo, version y estado.
2. Recuperar perfiles y permisos.
3. Recuperar campos y contextos.
4. Recuperar reglas.
5. Recuperar estados y transiciones.
6. Recuperar mensajes y tokens.
7. Recuperar pantallas relacionadas.
8. Recuperar decisiones pendientes.
9. Definir la responsabilidad principal de la pantalla.
10. Crear inventario funcional.
11. Separar por contextos.
12. Crear unidades funcionales.
13. Decidir que unidades generan historia.
14. Agrupar unidades coherentes.
15. Separar unidades con distinto actor, permiso, resultado, estado, riesgo o recurso.
16. Clasificar elementos transversales como parte del Story Pack.
17. Construir matriz de cobertura.
18. Ejecutar el juez de descomposicion.

## Decisiones permitidas por unidad

```text
CREATE_STORY
MERGE_WITH
CROSS_CUTTING
OUT_OF_SCOPE
PENDING_DECISION
DUPLICATE
RELATED_SCREEN
```

Cada decision exige justificacion y referencia a la fuente. Una decision sin
`source_ref` no puede clasificarse como CONFIRMED.

## Criterio de separacion

Separa cuando cambie al menos uno de: actor, permiso requerido, resultado de
negocio observable, estado afectado, nivel de riesgo, recurso persistido.

Agrupa cuando el mismo actor obtiene un unico resultado de negocio mediante
pasos que no tienen valor por separado.

## Regla contra fragmentacion artificial

No crear historias independientes solo para responsive, accesibilidad,
analytics, logging, correlation ID, auditoria tecnica, uso de tokens,
enmascaramiento o manejo generico de errores. Estos elementos acompanan cada
historia dentro del Story Pack, salvo que representen una capacidad funcional
para un actor real.

## Matriz de cobertura

Debe demostrar, con conteos, que cada contexto, permiso y transicion de la
fuente esta mapeado o justificado. `unmapped_count = 0` y
`unjustified_count = 0` son condiciones de paso.
