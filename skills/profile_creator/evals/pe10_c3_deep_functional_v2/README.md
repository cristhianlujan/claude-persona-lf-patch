# PE10_C3 — V2: calidad funcional y valor incremental demostrado

## Estado
**Diseño de 12 casos + fixtures + oráculo congelado. NO se ejecutaron los productores
GPT Native, NO se realizaron 24 respuestas, NO existe un veredicto independiente
nuevo y NO se activaron perfiles de producción.**

Antecedente: el benchmark V1 tuvo 30/30 tanto en ORIGINAL como en SHADOW.
El problema fue de discriminación de calidad: exigía requisitos básicos que
el original ya resolvía. V2 no altera V1 ni sus respuestas.

## Casos / perfiles
- QUALITY_PACK: 201 reconciliación SQL multitabla; 202 permisos revocados y
  exportación asíncrona; 203 webhook duplicado con efectos no monetarios;
  204 caso de control donde PASS limitado es correcto.
- UI_ARCHITECT: 205 respuesta asíncrona obsoleta entre dos cargas; 206
  rechazo, doble envío, foco y timeout; 207 token disabled y soporte
  dinámico stale; 208 titular original/actual divergente entre web/print/mobile.
- PRODUCT_DIRECTOR_LF: 209 paradoja de Simpson por mezcla de segmentos;
  210 incertidumbre del guardrail de quejas; 211 expectativa de recaudación
  frente a restricción inviolable; 212 decisión realmente secuencial por
  titularidad y mandato limitado, entregando una etapa por turno.

## Cómo se demuestra valor y no extensión
A y D reciben el **mismo** prompt, mismas fuentes, herramientas, tiempo y
datos. Los originales usan solo su perfil original, los evolucionados solo
su perfil shadow correspondiente; comprobar la **proyección física** de cada
contexto al modelo antes de ejecutar. No entregar el oráculo al productor.

El revisor distinto, ciego a A/D, revisa el resultado final, logs de
herramientas y material de los fixtures. Para cada salida:
- Cumplimiento material del pedido (0–4).
- **Valor adicional pertinente** (0–4):
  0 ninguna mejora; 1 observación corta útil; 2 riesgo, causa o prueba
  que aporta nueva decisión; 3 evita daño material o cambia una decisión;
  4 hallazgo sistémico u oportunidad significativa **demostrada**.
- Evidencia y honestidad operativa (0–2).
- Regresiones críticas: registrarlas por separado y descontarlas en la
  preferencia; no promover salida insegura por más texto.

Una observación de dos líneas puede ganar 1–4 puntos si es valiosa y
fundamentada. No se premian número de párrafos, longitud, número de joins
ni afirmaciones hipotéticas vendidas como hechos. Puede reconocerse
un hallazgo **no anticipado por el oráculo** si un juez independiente lo
verifica con datos. No obligar a hallar problemas inexistentes: 204 comprueba
criterio para cerrar y no inventar trabajo. Si ambas respuestas son iguales
se marca TIE; NO forzar ganador. Si un resultado es peor se marca REGRESSION.
No diseñar a posteriori una barrera porcentual para forzar PASS/FAIL.

## Ejecución de datos
Fixture 201: SQLite SQL sintético, nunca Supabase productivo.
Cargar en DB local efímera:
~~~bash
python3 - <<'PY'
import sqlite3
from pathlib import Path
sql=Path('skills/profile_creator/evals/pe10_c3_deep_functional_v2/fixtures/case_201_seed.sql').read_text()
db=sqlite3.connect(':memory:'); db.executescript(sql)
print(db.execute("SELECT SUM(monto) FROM pagos WHERE estado='CONFIRMED' AND fecha LIKE '2026-10%'").fetchone())
print(db.execute("SELECT SUM(monto) FROM liquidaciones WHERE fecha LIKE '2026-10%'").fetchone())
PY
~~~
El oráculo demuestra C2/P2/G2 mal referenciado en octubre y otra anomalía
C3/P3/G3 en septiembre. El productor ve el fixture y, si investiga,
puede descubrir esto; el prompt no lo revela. El revisor no admite
"SQL ejecutado" sin una ejecución observada o artefacto de tool.

Caso 212: revelar exclusivamente stage_1 al productor; después de obtener
respuesta completa de ese turno, revelar stage_2; después, stage_3.
Las decisiones 1,2,3 se juzgan juntas para adaptación real; no mostrar
el archivo siguiente antes de recibir la respuesta previa.

## Ceguera y congelación
1. Antes de correr, inmovilizar commit SHA de este paquete y contexto
   de cada perfil. Guardar hash de entrada y proyección exacta.
2. Un chat GPT Native productor por brazo; para evitar contaminación,
   no leer evaluaciones, el oráculo ni el otro brazo.
3. Capturar para los doce casos outputs originales completos por brazo;
   caso 212 incluye tres respuestas por brazo con referencias de turno.
4. Separar identificadores A/D y aleatorizar identidad X/Y por caso.
5. Dar al juez las dos salidas completas, la misma entrada, el oráculo
   solo a él, y logs de herramientas asociados; no modificar respuestas.
6. Para cada hallazgo extra: registrar afirmación literal, prueba o SQL,
   hecho validado, impacto real, si fue inesperado y si cambia una acción.
   Si no existe evidencia, anotar HYPOTHESIS_ONLY, no inventar descubrimiento.
7. Comparar puntuaciones y regresiones por caso; explicar TIE y los
   casos en que A supera a D; calificar utilidad operativa global con
   ejemplos exactos A→D, no con porcentajes de selección de modos.
8. Veredicto PE10_C3 corresponde al evaluador independiente con el
   contrato de revisión vigente; este paquete no registra PASS.

## Pruebas técnicas del paquete
~~~bash
python3 -m unittest \
 skills.profile_creator.evals.pe10_c3_deep_functional_v2.test_cases_v2 \
 skills.profile_creator.evals.pe10_c3_deep_functional_v2.test_quant_methods_v2 \
 skills.profile_creator.evals.pe10_c3_deep_functional_v2.test_causal_diagnosis_v2 -v
~~~
Son pruebas de consistencia de escenarios y funciones experimentales.
**No acreditan superioridad de D**.

## Métodos experimentales
- quant_methods_v2.py: límites Wilson, riesgo Beta-Binomial,
  sample-ratio mismatch, esperanza de recaudación neta.
- causal_diagnosis_v2.py: actualización secuencial de hipótesis y
  orden de pruebas por ganancia de información. No prueba causalidad.
- Ambos en SHADOW_ONLY: que exista archivo NO significa que el modelo
  lo reciba ni pueda invocarlo. Antes del par productivo hay que confirmar
  alcance real dentro de la proyección / tool binding de la variante D.
No modificar el perfil canónico por el hecho de diseñar este benchmark.
