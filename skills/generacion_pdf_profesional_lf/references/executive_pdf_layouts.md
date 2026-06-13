# Executive PDF Layouts — LF

## Principio

Un PDF ejecutivo LF debe verse como decision aid, no como dump de texto.

## Formato recomendado

- 16:9 landscape para directorio, flujo, onboarding, propuesta y brandbook.
- A4/Letter solo para informe formal largo.
- Margen seguro minimo: 0.5 pulgadas.
- Titulo: 34-44pt.
- Subtitulo/seccion: 20-24pt.
- Cuerpo: 13-16pt.
- Nota/footer: 9-11pt.

## Paleta base LF ejecutiva

| Token | Uso |
|---|---|
| navy | fondo portada, titulos, barras |
| slate | texto secundario |
| warm_neutral | fondos de pagina |
| white | cards |
| green | positivo / avance |
| amber | observacion |
| red | bloqueo |

No usar todos los colores con el mismo peso. Un color domina 60-70%, 1-2 soportan y 1 acento destaca.

## Layouts obligatorios disponibles

### L1 Cover ejecutivo

Uso: primera pagina.

Debe contener:
- titulo fuerte;
- subtitulo;
- estado;
- fecha/version;
- 3 chips maximo: fuente, riesgo, estado.

Bloquear si parece portada de documento Word.

### L2 Resumen operativo

Uso: pagina 2.

Estructura:
- 4 cards KPI arriba;
- bloque veredicto;
- 3 riesgos principales;
- siguiente accion.

### L3 Flow map horizontal

Uso: onboarding/journey.

Reglas:
- maximo 7 nodos por pagina;
- si hay mas, dividir en fases;
- cada nodo: numero, nombre, accion, estado;
- usar colores por estado: activo, revision, archivado, bloqueo.

### L4 Matriz de pantallas

Uso: detalle de pantallas.

Reglas:
- maximo 6 pantallas por pagina;
- cada card debe mostrar: pantalla, objetivo, CTA, riesgo, validaciones clave;
- no meter JSON completo.

### L5 Riesgos y controles

Uso: riesgos ALTO/CRITICO.

Estructura:
- tabla de maximo 6 filas;
- columnas: riesgo, severidad, pantalla, control esperado;
- si hay mas riesgos, anexo.

### L6 Legales / integraciones

Uso: dependencias externas.

Estructura:
- dos columnas: integraciones y documentos legales;
- badges por estado;
- nota de no produccion.

### L7 Decision board

Uso: recomendaciones.

Estructura:
- objetivo;
- contexto minimo;
- opciones;
- riesgos;
- recomendacion;
- siguiente accion.

## Densidad maxima

| Elemento | Maximo por pagina |
|---|---:|
| Cards | 6 |
| Filas de tabla | 8 |
| Nodos de flujo | 7 |
| Palabras por bloque | 90 |
| Niveles de bullets | 2 |

Si el contenido excede: crear otra pagina o anexo.

## Bloqueos visuales

- Texto menor a 9pt.
- Tabla que ocupa toda la pagina sin jerarquia.
- Flujo con nodos apretados.
- Cards pegadas a bordes.
- Mas de 3 estilos visuales en una pagina.
- Pagina sin elemento visual.
- Portada sin jerarquia.

Veredicto si ocurre: `FAIL_VISUAL_QUALITY`.