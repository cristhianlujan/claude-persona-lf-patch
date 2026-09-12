# Bad Report Antipatterns

Usar para bloquear PDFs pobres.

## Antipatrones que fallan

1. PDF tipo memo: muchas lineas de texto y sin estructura visual.
2. Una tabla gigante ocupa toda la pagina.
3. Flujo completo comprimido en una sola pagina.
4. Cards sin jerarquia o pegadas al borde.
5. Texto menor a 10 pt.
6. Footer invade contenido.
7. Colores sin semantica.
8. Sin portada profesional.
9. Sin fuente editable.
10. Sin imagenes de paginas para QA.
11. Sin lista de issues visuales.
12. Sin fix and verify.

## Veredicto obligatorio

- PDF plano: FAIL_VISUAL_QUALITY.
- Sin pipeline: RETURN_TO_WORKER.
- Sin fuente editable: RETURN_TO_WORKER.
- Sin render a imagen: BLOCKED.
- Sin readback: BLOCKED.

## Regla de seguridad

Si el PDF parece generado rapido solo para cumplir entrega, no pasa.