---
name: auditoria-profunda-implementacion-lf
description: Auditar implementaciones LF leyendo código real, SPEC, EVAL, SQL, transporte, jueces y consumidores. Usar para descubrir omisiones no documentadas, parámetros perdidos, lógica incompleta, consultas redundantes, contexto insuficiente y contradicciones de autorización; producir causas, correcciones y pruebas reproducibles. Incluye checklist EKB y piloto Paso 70; no promover ni reparar masivamente.
---

# SKILL_AUDITORIA_PROFUNDA_IMPLEMENTACION_LF

Estado: `CANDIDATE_SOURCE_ONLY_NOT_REGISTERED`. Un candidato por PR no acredita
instalación, registro, ejecución de perfil ni autorización de efectos.

## Entrada y límites

Leer [contrato](contracts/main_contract.md), [faltantes](contracts/missing_input_policy.md)
y [checklist EKB](checklists/preflight_checklist.md). Validar forma de entrada con
[intake V2](schemas/audit_input_v2.schema.json), sin tomar un estado declarado
como autoridad verificada. Fijar objetivo, repositorio,
commit, superficies, consumidores, autoridad y alcance antes de analizar. En LF
comprobar proyecto `mhwmirqcgxxukpctffuv`; usar solo SELECT. No ejecutar código
ajeno sin inspeccionarlo ni usar credenciales, migraciones o producción. Razonar
con el modelo nativo; los scripts son ayudas acotadas, no un auditor universal.
No llamar APIs de modelos ni generar gasto.

## Seis fases obligatorias

1. **Descubrimiento.** Usar `rg --files` y `rg -n`; inventariar funciones,
   contratos, callers, datos, estados, permisos y consumidores hasta el efecto
   final. Leer EKB vigente mediante [adaptador](adapters/ekb_readonly.md); guardar
   consulta, códigos, estado, fecha y hash. Seleccionar recurrencias por contexto.
   Añadir riesgos nuevos aunque no existan en EKB; registrar superficies no leídas.
2. **Análisis estático y semántico.** Leer línea por línea las superficies
   relevantes. Contrastar especificado → implementado → transportado → validado →
   ejecutado → comprobado. Construir cadena de archivos, funciones, líneas y
   commits/hashes. Seguir campos y aliases, defaults, nulos, versiones, errores y
   argumentos en cada salto. Usar `scripts/inspect_sources.py` para candidatos
   AST; resolver importaciones ambiguas, SQL/TS y llamadas dinámicas manualmente.
3. **Diagnóstico arquitectónico.** Aplicar [reglas](references/inspection_rules.md)
   y [taxonomía](references/defect_taxonomy.json). Separar defecto contractual,
   pérdida de contexto y optimización opcional. Comparar alternativas por
   concurrencia, RLS, frescura, invalidación y consistencia. No preferir `case`,
   caché o materialización por estilo. Silencio del script no acredita corrección.
4. **Pruebas.** Construir reproductor mínimo desde las fuentes; incluir positivo,
   negativo y regresión. Separar fixtures y ejecuciones reales. Medir consultas,
   planes y operaciones del mismo dataset antes/después. No extrapolar SQLite a
   Postgres ni mocks a E2E. Ver [casos](evals/eval_matrix.json). No ejecutar tests
   desconocidos con efectos ni datos vivos.
5. **Correcciones.** Proponer código/contrato exacto, fuente de cada campo,
   componentes afectados, pruebas y rollback. Aplicar solo dentro del alcance
   autorizado. Los defectos funcionales LF de este piloto quedan como propuesta;
   un hallazgo no concede autoridad de reparación ni promoción.
6. **Verificación.** Reejecutar consumidor y controles después de cada corrección
   permitida; comparar baseline, releer destino, guardar comando, exit code,
   salida, hashes y límites. Aplicar obligatoriamente el
   [contrato de profundidad V2](contracts/reporting_and_contract_depth_v2.md):
   once pasos con aciertos/evidencia/pendientes, SQL por consulta, todos los saltos,
   inventario PASS con negativos, cohorte N y matriz semántica por tipo de contrato.
   Completar [comprobaciones V2](checklists/reporting_v2.md) y checklist EKB
   con procedencia explícita, sin recertificar un snapshot histórico por copiarlo.
   Validar reporte nuevo con
   `python <skill>/validators/validate_audit_v2.py <report.json> --repo-root <repo>`.
   `FIX_VERIFIED` exige before/after y readback del alcance efectivamente probado.

## Definición puntual de los jueces

**Revisar exclusivamente el contexto, SPEC y EVAL aplicables al cometido del
juez. Eso acredita el pase cuando sus criterios se cumplen y la autoridad
vigente lo acepta. No exigir otro proveedor, modelo o API por preferencia.**

| Dimensión | Qué acredita | Evidencia |
|---|---|---|
| Validez contextual | Evaluación correcta para el objetivo | SPEC/EVAL vigentes, candidato y alcance enlazados, contraejemplos |
| Independencia | Separación respecto del productor | Aislamiento de contexto/evaluación admitido y procedencia verificada |
| Autoridad de promoción | Permiso del efecto específico | Política vigente, actor, objeto, versión y condiciones |

Un mismo modelo puede acreditar independencia lógica con aislamiento comprobado
si el contrato lo admite. Revisar el propio contexto puede acreditar suficiencia
contextual; no convierte al productor en independiente. No usar independencia
como veto adicional donde la política acepte SPEC/EVAL/contexto/deterministas.
Si existe autoridad y todos los criterios se cumplen, emitir literalmente
`promotion_authorized=true` y la acción autorizada. Si falta, emitir
`promotion_authorized=false`, cláusula exacta y cambio contractual propuesto.
No sustituir permiso por «podría» o «retornar al Router». Diferenciar solicitar,
aprobar y aplicar. Leer [juez contextual](judges/context_spec_judge.md).
[El readback V1](references/governance_current_readback.json) es histórico:
resolver política, función y autoridad actuales para cada efecto y versión,
incluidas rutas AUTO si están autorizadas. No imponer un antiguo gate humano ni
un viejo veto de independencia. La aceptación contextual no prueba independencia.
Emitir [resultado tipado del juez](schemas/judge_result_v2.schema.json). Un schema
comprueba forma y coherencia; la autorización exige readback gobernado real.

## Salida y cierre

Cumplir [schema V2](schemas/audit_report_v2.schema.json); conservar
[V1](schemas/output.schema.json) para los informes históricos. Mostrar
**cobertura del lote**, **calidad contractual** y **veredicto del flujo** por separado.
Una corrida histórica no acredita un E2E nuevo, aunque tenga once PASS.
Los [perfiles de diez tipos](references/contract_profiles_v2.json) definen formatos
y campos aplicables; descubrir además lo que requieran sus consumidores.
La matriz usa verde aceptable, amarillo débil, rojo falta/contradicción, gris no
evaluado y NA justificado. Revisar significado, claridad, condición, error y prueba;
no longitud del texto. Por celda débil: literal, fuente, consumidor y redacción exacta.
Incluir hallazgos completos, cadena de consumidores, checklist EKB con evidencia,
procedencia/confianza y cobertura leída/no leída. Cada hallazgo
incluye ID, ubicación/commit/hash, código literal, esperado y evidencia, defecto,
causa, impacto, corrección exacta, pruebas positiva/negativa, resultado, readback y
`CONFIRMED|HYPOTHESIS|NOT_VERIFIED|FIX_VERIFIED`.

Usar [rúbrica](judges/score_rubric.md) y [handoff](handoffs/to_quality_pack.handoff.json).
Un test de fixture no acredita despliegue. Informar cada lote en español:
`Alcance | Acción | Evidencia | Hallazgos | % avance | Pendientes | Siguiente lote`.
Cerrar con PR/HEAD/readback/CI reales y límites, manteniendo registro y activación
separados. Consultar [alcance](references/scope.md) antes de extrapolar.

## Verificar el paquete local

```bash
python -m unittest discover -s skills/auditoria-profunda-implementacion-lf/evals -p 'test_*.py' -v
python skills/auditoria-profunda-implementacion-lf/validators/validate_pack.py
```
