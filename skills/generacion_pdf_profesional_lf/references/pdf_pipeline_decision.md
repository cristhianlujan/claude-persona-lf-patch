# PDF Pipeline Decision — LF

## Objetivo

Evitar que un PDF profesional se genere con el motor incorrecto.

## Regla dura

| Tipo de entrega | Pipeline permitido | Bloqueo |
|---|---|---|
| Ejecutivo / directorio / propuesta | PPTX 16:9 -> PDF | Bloquear si se usa reporte plano |
| Flujo / onboarding / journey | PPTX 16:9 o HTML/CSS premium paginado -> PDF | Bloquear si todo el flujo entra comprimido en 1 pagina |
| Brandbook / design system | HTML/CSS premium o PPTX visual -> PDF | Bloquear si no hay tokens, componentes ni ejemplos |
| Informe formal largo | Markdown/DOCX -> PDF | Bloquear si no hay estilos, indice o tablas legibles |
| PDF basico existente | Extraer -> reconstruir editable -> rediseñar -> PDF | Bloquear si solo se maquilla el PDF existente |
| Tabla extensa / anexo tecnico | DOCX o HTML paginado -> PDF | Bloquear si la tabla se corta o baja de 9pt |

## Decision obligatoria antes de escribir

Completar esta matriz:

| Campo | Valor |
|---|---|
| audiencia | owner / directorio / cliente / equipo / auditoria |
| tipo_pdf | ejecutivo / flujo / brandbook / informe / anexo |
| fuente | Supabase / Drive / GitHub / texto / PDF existente |
| pipeline_elegido | PPTX / HTML-CSS / DOCX / ReportLab / reconstruccion |
| motivo | razon concreta |
| pipeline_descartado | opcion descartada |
| riesgo | riesgo si se usa mal pipeline |

## Reglas de seleccion

1. Si hay storytelling visual, usar PPTX 16:9.
2. Si hay muchas paginas con componentes repetibles, usar HTML/CSS premium paginado.
3. Si hay texto largo formal, usar DOCX/Markdown.
4. Si hay calculo o tablas, usar HTML/DOCX y dividir tablas.
5. ReportLab solo se permite cuando el layout sea simple, tabular o tecnico, nunca como default ejecutivo.
6. Si el entregable es visual y se ve como memo, devolver `RETURN_TO_WORKER`.

## Criterios anti-error

- No mezclar mas de 3 niveles jerarquicos por pagina.
- No poner mas de 6 cards por pagina.
- No poner mas de 8 filas de tabla por pagina sin anexo.
- No poner mas de 90 palabras continuas en un bloque.
- No usar cuerpo menor a 10pt en PDF final.
- No usar footer que choque con contenido.

## Veredicto

Si el pipeline no esta justificado por esta matriz, el cierre obligatorio es:

```text
BLOCKED_PIPELINE_DECISION_MISSING
```