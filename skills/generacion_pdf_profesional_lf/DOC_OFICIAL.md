# DOC_OFICIAL — SKILL_GENERACION_PDF_PROFESIONAL_LF v0.1 CANDIDATO

## 1. Estado documental

| Campo | Valor |
|---|---|
| Proyecto | 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF |
| Activo | SKILL_GENERACION_PDF_PROFESIONAL_LF_v0.1_CANDIDATO |
| Tipo | SKILL |
| Estado documental | CANDIDATO |
| Estado operativo | READ_ONLY |
| Runtime | NO_HABILITADO |
| Impacto automatico | BLOQUEADO |
| Operation code | CREACION_SKILL_LF |
| Fecha | 2026-06-13 |

## 2. Problema operativo

Los PDFs LF estaban saliendo basicos: poca jerarquia visual, bajo control de layout, ausencia de fuente editable, falta de QA visual y cierres sin readback suficiente.

## 3. Objetivo

Crear una skill candidata para generar, reconstruir y auditar PDFs LF profesionales, ejecutivos, visuales y verificables, sin habilitar produccion ni runtime automatico.

## 4. Alcance

Incluye:

- generacion de PDFs nuevos;
- seleccion de pipeline editable;
- reconstruccion desde PDF basico existente;
- conversion desde Markdown, DOCX, PPTX, HTML/CSS o ReportLab;
- QA visual obligatorio;
- readback de evidencia;
- plantillas base para reportes, brandbooks, auditorias, propuestas y briefs ejecutivos.

No incluye:

- runtime automatico;
- aprobacion productiva;
- reemplazo de ACT-0043, ACT-0045 o ACT-0047;
- copia de implementaciones propietarias externas;
- uso de skills externas como runtime;
- generacion de contenido factual sin fuente verificable.

## 5. Activos madre relacionados

| Activo | Rol | Estado operativo usado |
|---|---|---|
| ACT-0001 | Router operativo rector | VIGENTE / ACTIVO / RECTOR |
| ACT-0043 | Skill Creator LF | VIGENTE / READ_ONLY |
| ACT-0045 | Skill creadora perfiles/cards LF | VIGENTE / READ_ONLY |
| ACT-0047 | Design System multicanal LF | CANDIDATO / READ_ONLY |
| contrato_skill_lf.yaml | Contrato alto nivel CREACION_SKILL_LF | CANDIDATO_READ_ONLY |
| judge_contrato_skill_lf.yaml | Judge contractual CREACION_SKILL_LF | CANDIDATO_READ_ONLY |
| matriz_repos_lf.yaml | Repo y rutas autorizadas | AUTHORIZED |

## 6. Ruta obligatoria ejecutada

```text
Router -> ACT-0001 -> Supabase / v_lf_fuente_operativa -> activo vigente aplicable -> contrato CREACION_SKILL_LF -> duplicidad -> research pack -> research_to_rules_matrix -> decision_matrix -> diseno canonico -> paquete skill -> evals -> judge -> manifest -> GitHub write -> readback -> evidence log -> cierre candidato
```

## 7. Validacion de duplicidad

| Fuente | Resultado | Decision |
|---|---|---|
| Supabase / v_lf_fuente_operativa_busqueda | No se encontro skill PDF profesional LF exacta | Procede candidato |
| GitHub repo autorizado | Ya existia carpeta `skills/generacion_pdf_profesional_lf/` | No duplicar; regularizar paquete existente |
| ACT-0047 Design System | Cubre sistema visual multicanal, no pipeline PDF completo | Relacionar, no reemplazar |
| Skills externas PDF/DOCX/PPTX | Referencias tecnicas externas | Usar patrones, no copiar ni adoptar runtime |

## 8. Research to rules matrix

| Fuente | Hallazgo operativo | Regla LF derivada | Destino |
|---|---|---|---|
| ACT-0001 | Toda tarea operativa entra por Router y fuente operativa | PDF LF no inicia directo por render | SKILL.md / manifest |
| ACT-0043 | Skill candidata requiere activadores, limites, sandbox, baseline y no duplicidad | Definir activadores/no activadores y bloqueo | SKILL.md |
| ACT-0045 | Research pack debe puntuar fuentes y evitar copia | Research pack con scoring y riesgos | research_pack.md |
| ACT-0047 | Diseño visual debe respetar tokens, componentes, accesibilidad y QA | PDF profesional requiere sistema visual minimo | evals / judge |
| Anthropic Agent Skills | Skills son carpetas con SKILL.md y recursos | Paquete multiarchivo versionado | manifest.yaml |
| anthropics/skills/pdf | PDF tiene operaciones tecnicas de lectura, extraccion y render | Separar operacion tecnica de calidad visual LF | SKILL.md |
| anthropics/skills/docx | DOCX funciona como fuente editable verificable | Exigir fuente editable cuando aplique | evals |
| anthropics/skills/pptx | QA visual exige render, inspeccion, correccion y verificacion | Adoptar QA visual obligatorio para PDFs | judge |
| Research de riesgos | Skills externas tienen riesgo de redundancia, permisos, procedencia y supply chain | No confiar en skill externa sin governance, sandbox y judge | restrictions |

## 9. Matriz de decision

| Caso | Decision | Pipeline |
|---|---|---|
| Documento largo / informe formal | Crear fuente editable estructurada | Markdown o DOCX -> PDF |
| Propuesta ejecutiva / directorio | Priorizar narrativa visual | PPTX 16:9 -> PDF |
| Reporte visual / brandbook | Priorizar control de layout | HTML/CSS o ReportLab -> PDF |
| Tablas extensas | Evitar tablas rotas | DOCX o HTML -> PDF |
| PDF existente basico | No maquillar superficialmente | Extraer -> reconstruir editable -> redisenar -> PDF |
| Sin fuente verificable | Bloquear contenido factual | Solicitar/consultar fuente autorizada |
| Sin QA visual | Bloquear cierre | Render -> inspeccion -> fix -> re-render |
| Pedido de runtime/productivo | Bloquear | Mantener CANDIDATO_READ_ONLY |

## 10. Diseno canonico

La skill queda como paquete portable en:

```text
skills/generacion_pdf_profesional_lf/
```

Archivos obligatorios:

- `SKILL.md`
- `DOC_OFICIAL.md`
- `research_pack.md`
- `manifest.yaml`
- `evals/pdf_quality_checklist.yaml`
- `judges/judge_pdf_profesional_lf.yaml`
- `examples/input_brief.md`
- `examples/output_expected.md`

## 11. Criterios de aceptacion

- Estado maximo: CANDIDATO.
- Operacion: READ_ONLY.
- Runtime: NO_HABILITADO.
- Impacto automatico: BLOQUEADO.
- Research pack presente.
- Research to rules matrix presente.
- Decision matrix presente.
- Eval presente.
- Judge presente.
- Manifest presente.
- GitHub readback ejecutado.
- Supabase evidence log registrado.

## 12. Bloqueos

Bloquear si:

- se intenta marcar VALIDATED, VIGENTE o APROBADO;
- se habilita runtime;
- se habilita impacto automatico;
- falta readback;
- falta evidence log;
- falta judge/eval/manifest;
- falta research_to_rules_matrix;
- falta decision_matrix;
- se intenta modificar marketplace-ssot;
- se copia contenido propietario externo;
- se cierra un PDF sin QA visual.

## 13. Cierre candidato

Este documento deja regularizada la definicion candidata de la skill. Queda pendiente sandbox con PDFs reales LF y aprobacion explicita para cualquier promocion documental u operativa.

Estado final permitido:

```text
CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO PARA PRODUCCION
```