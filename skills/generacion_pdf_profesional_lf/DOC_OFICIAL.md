# DOC_OFICIAL — SKILL_GENERACION_PDF_PROFESIONAL_LF v0.1 CANDIDATO

## Estado documental

- proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
- activo: SKILL_GENERACION_PDF_PROFESIONAL_LF_v0.1_CANDIDATO
- tipo: SKILL
- estado_documental: CANDIDATO
- estado_operativo: READ_ONLY
- runtime_estado: NO_HABILITADO
- impacto_automatico: BLOQUEADO
- operation_code: CREACION_SKILL_LF
- fecha: 2026-06-13

## Problema operativo

Los PDF LF estaban saliendo basicos: baja jerarquia visual, poco control de layout, falta de fuente editable, poca evidencia de QA y cierre visual no verificable.

## Objetivo

Crear una skill candidata para producir PDFs profesionales, ejecutivos, visuales y verificables, con protocolo LF completo y sin habilitacion productiva automatica.

## Alcance

Incluye:
- generacion de PDFs nuevos;
- reconstruccion visual desde texto, markdown, DOCX, PPTX o HTML;
- seleccion de pipeline editable;
- QA visual obligatorio;
- readback de evidencia;
- plantillas base para reportes, brandbooks, auditorias y briefs ejecutivos.

No incluye:
- runtime automatico;
- aprobacion productiva;
- reemplazo de ACT-0043, ACT-0045 o ACT-0047;
- copia de implementaciones propietarias externas;
- generacion sin fuente verificable.

## Activos madre relacionados

| Activo | Rol |
|---|---|
| ACT-0001 | Router operativo rector |
| ACT-0043 | Skill Creator LF vigente, produccion controlada read-only |
| ACT-0045 | Skill creadora de perfiles/cards vigente, produccion controlada read-only |
| ACT-0047 | Skill transversal de Design System multicanal, candidato read-only |
| CREACION_SKILL_LF | Protocolo operativo de creacion de skills |

## Principios de diseño

1. El PDF final no es el unico entregable; debe existir fuente editable cuando el caso lo requiera.
2. El render debe pasar auditoria visual, no solo compilacion tecnica.
3. Los PDFs ejecutivos deben usar componentes visuales: cards, tablas, flujos, callouts, semaforos y resumen operativo.
4. La skill debe ser compatible con Claude/Agent Skills, pero gobernada por LF.
5. No se admite cierre sin readback y evidencia.

## Pipeline oficial candidato

```text
Brief -> clasificacion de PDF -> seleccion de fuente editable -> diseno visual -> render -> QA visual -> correccion -> readback -> cierre candidato
```

## Matriz de decision

| Decision | Criterio | Resultado |
|---|---|---|
| Crear skill nueva | No existe skill PDF LF especifica | Crear candidata |
| Reutilizar Claude PDF | Util como referencia tecnica, no como gobierno LF | Referenciar, no copiar |
| Usar Design System LF | Necesario para elevar calidad visual | Integrar como activo relacionado |
| Habilitar runtime | Sin sandbox ni QA real aun | Bloqueado |
| Marcar VIGENTE/VALIDATED | Falta prueba con PDFs reales LF | Bloqueado |

## Research to rules matrix

| Fuente | Hallazgo | Regla LF derivada |
|---|---|---|
| Anthropic Skills | Skills son carpetas con SKILL.md, scripts y recursos | Paquete multiarchivo con SKILL.md obligatorio |
| Agent Skills standard | Formato ligero, portable y versionable | Mantener carpeta portable y versionada |
| Anthropic PDF skill | PDF puede cubrir crear, editar, extraer, combinar y renderizar | Separar capacidad tecnica de calidad visual |
| Anthropic PPTX skill | QA visual y ciclo fix-and-verify son obligatorios para slides | Adoptar QA visual obligatorio para PDFs |
| Anthropic DOCX skill | DOCX requiere validacion y fuente editable | Exigir fuente editable y validacion cuando aplique |
| Estudios externos de agent skills | Riesgo de duplicidad y seguridad en skills de terceros | No usar skills externas sin governance, sandbox y judge |

## Criterios de aceptacion

- Paquete creado en `/skills/generacion_pdf_profesional_lf/`.
- Estado maximo: CANDIDATO.
- Runtime: NO_HABILITADO.
- Impacto automatico: BLOQUEADO.
- Incluye SKILL.md, DOC_OFICIAL.md, manifest, research pack, eval y judge.
- Readback GitHub ejecutado.
- Registro Supabase si el conector lo permite.

## Bloqueos

- No puede declararse oficial productiva.
- No puede reemplazar skills existentes.
- No puede operar sin QA visual.
- No puede generar PDFs finales sin fuente editable cuando sea necesaria.

## Cierre candidato

Este documento deja creada la definicion oficial candidata de la skill. Queda pendiente sandbox con PDF real LF y aprobacion explicita para cualquier promocion documental u operativa.
