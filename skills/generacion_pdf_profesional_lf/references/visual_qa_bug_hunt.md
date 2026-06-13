# Visual QA Bug Hunt — LF

## Objetivo

Evitar QA complaciente. El primer render casi nunca esta listo.

## Regla dura

El QA visual no confirma. El QA busca errores.

Si el primer QA no encuentra nada, ejecutar una segunda revision con mas severidad. Cero issues en primer render sin segunda revision = `BLOCKED_QA_CONFIRMATION_BIAS`.

## Preparacion

1. Renderizar PDF.
2. Convertir paginas clave a imagen PNG/JPG.
3. Revisar minimo: portada, resumen, pagina con flujo, pagina con tabla, pagina de cierre.
4. Si el PDF tiene menos de 8 paginas, revisar todas.

## Checklist por pagina

| Criterio | PASS | FAIL |
|---|---|---|
| Margen seguro | >= 0.5 pulgadas visuales | elementos pegados al borde |
| Jerarquia | titulo, subtitulo y cuerpo claros | todo pesa igual |
| Densidad | una idea principal | saturacion o texto largo |
| Contraste | texto legible | gris claro o bajo contraste |
| Overflow | nada cortado | texto o cards cortadas |
| Solape | sin cruces | texto sobre shapes o footer |
| Tabla | filas legibles | tabla comprimida o rota |
| Flujo | nodos claros | nodos apretados o ilegibles |
| Footer | no invade contenido | colisiona con tabla/cards |
| Visual | hay componente visual | pagina solo texto |

## Bug hunt obligatorio

Para cada pagina escribir:

```yaml
page: 1
expected: portada ejecutiva
issues_found:
  - tipo: margen|contraste|overflow|densidad|jerarquia|tabla|flujo|footer|otro
    severidad: alta|media|baja
    evidencia: descripcion concreta
fix_required: true|false
```

## Fix-and-verify

1. Listar issues.
2. Corregir fuente editable.
3. Re-renderizar.
4. Revisar paginas afectadas.
5. Registrar resultado.

No cerrar si no existe al menos un ciclo de verificacion despues de cambios cuando hubo cualquier issue.

## Bloqueos inmediatos

- Texto cortado.
- Elementos solapados.
- Tabla ilegible.
- Flujo ilegible.
- PDF parece memo plano cuando era ejecutivo.
- Fuente editable no existe.
- No hay screenshots/readback visual.

## Veredictos

| Caso | Veredicto |
|---|---|
| Sin issues despues de fix-and-verify | PASS_CANDIDATO_READ_ONLY |
| Issues menores listados | PASS_WITH_OBSERVATIONS_CANDIDATO_READ_ONLY |
| Requiere rediseño | RETURN_TO_WORKER |
| Se ve basico o roto | FAIL_VISUAL_QUALITY |
| Falta evidencia | BLOCKED |