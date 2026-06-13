---
name: generacion-pdf-profesional-lf
description: Skill candidata LF para crear, reconstruir y auditar PDFs profesionales, visuales, ejecutivos y verificables. Usar cuando el usuario pida PDF, reporte, brandbook, propuesta, auditoria, dossier o entregable final con QA visual obligatorio. No habilita runtime automatico ni estado productivo.
status: CANDIDATO
estado_documental: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
automatic_impact: BLOQUEADO
owner_project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
operation_code: CREACION_SKILL_LF
version: v0.1-candidato-read-only
last_updated: 2026-06-13
---

# SKILL_GENERACION_PDF_PROFESIONAL_LF

## 1. Proposito

Crear PDFs LF profesionales, visuales, ejecutivos y verificables, evitando entregables basicos, planos, sin jerarquia visual o sin QA.

Esta skill decide el pipeline correcto, conserva fuente editable cuando corresponde, exige QA visual y bloquea cierres sin readback.

## 2. Estado operativo

| Campo | Valor |
|---|---|
| estado_documental | CANDIDATO |
| estado_operativo | READ_ONLY |
| runtime_estado | NO_HABILITADO |
| impacto_automatico | BLOQUEADO |
| cierre_permitido | CANDIDATO_READ_ONLY |

No puede marcar APROBADO, VALIDATED, VIGENTE, RUNTIME_READY ni PRODUCCION.

## 3. Activadores

Activar cuando el usuario solicite:

- crear PDF profesional;
- mejorar PDF basico existente;
- convertir brandbook, reporte, propuesta o deck a PDF;
- preparar PDF para directorio, cliente, owner o auditoria;
- reconstruir un PDF desde fuente editable;
- hacer QA visual de PDF;
- convertir Markdown, DOCX, PPTX, HTML/CSS o ReportLab a PDF con control visual.

## 4. No activar

No activar si:

- solo se requiere texto plano;
- basta una respuesta simple;
- el pedido implica modificar fuente oficial LF sin Router y autorizacion vigente;
- se pretende usar una skill externa como runtime directo;
- se busca declarar produccion, validacion o aprobacion;
- no hay fuente verificable y el usuario exige contenido factual;
- el entregable no requiere PDF ni control visual.

## 5. Ruta LF obligatoria

```text
Router -> ACT-0001 -> Supabase / v_lf_fuente_operativa -> activo vigente aplicable -> adapter si aplica -> operacion controlada -> render -> QA visual -> readback -> cierre candidato
```

## 6. Inputs minimos

- Objetivo del PDF.
- Audiencia: owner, directorio, cliente, equipo, auditoria.
- Tipo: informe formal, propuesta ejecutiva, brandbook, reporte visual, auditoria, manual, dossier.
- Fuente: texto, Markdown, DOCX, PPTX, HTML, imagenes, Supabase, Drive, GitHub u otra fuente autorizada.
- Restricciones: marca, formato, idioma, orientacion, confidencialidad, version/estado.
- Nivel visual esperado: ejecutivo, fintech, sobrio, tecnico, comercial, institucional.
- Reglas LF aplicables si el contenido toca proyectos, documentos o activos oficiales.

## 7. Decisor de pipeline

| Caso | Fuente editable recomendada | Render final | Criterio |
|---|---|---|---|
| Documento largo / informe formal | Markdown o DOCX | PDF | Mucho texto, estructura formal, anexos, indice |
| Propuesta ejecutiva / directorio | PPTX 16:9 | PDF | Narrativa visual, slides, decision ejecutiva |
| Reporte visual / brandbook | HTML/CSS o ReportLab | PDF | Layout visual, componentes, tokens, grillas |
| Tablas extensas | DOCX o HTML | PDF | Tablas, continuidad, legibilidad |
| PDF existente basico | Extraer -> reconstruir fuente editable -> redisenar -> renderizar | PDF | No editar superficialmente si el origen es pobre |

Regla: si el PDF debe revisarse, conservar fuente editable salvo justificacion NA.

## 8. Procedimiento operativo

1. Clasificar el entregable y audiencia.
2. Verificar fuente operativa y activos aplicables.
3. Seleccionar pipeline editable.
4. Definir estructura: portada, indice si aplica, secciones, anexos.
5. Definir sistema visual minimo: paleta, tipografia, grilla, componentes.
6. Construir fuente editable.
7. Renderizar PDF.
8. Ejecutar QA visual.
9. Corregir cortes, solapes, margenes, tablas, contraste o textos pequenos.
10. Re-renderizar.
11. Hacer readback: paginas, ruta, fuente editable, QA, pendientes.
12. Cerrar solo como candidato/revisable cuando aplique.

## 9. Estandar visual minimo

Todo PDF profesional LF debe incluir, cuando aplique:

- portada profesional;
- indice o estructura clara;
- jerarquia tipografica;
- paleta visual definida;
- grilla y margenes consistentes;
- cards, tablas, callouts, flujos o semaforos;
- footer con version, estado y pagina;
- fuente editable;
- QA visual obligatorio;
- readback final.

## 10. Componentes LF recomendados

- Cover ejecutivo.
- Resumen operativo.
- Matriz objetivo -> contexto -> opciones -> riesgos -> recomendacion -> siguiente accion.
- Cards de hallazgos.
- Semaforo de riesgo.
- Tabla de decisiones.
- Flujo operativo.
- Checklist de cierre.
- Anexo de evidencia.

## 11. QA visual obligatorio

Antes de cerrar cualquier PDF:

1. Renderizar PDF.
2. Revisar paginas clave visualmente.
3. Detectar cortes, solapes, textos pequenos, baja alineacion, bajo contraste o tablas rotas.
4. Corregir.
5. Re-renderizar.
6. Registrar evidencia/readback.

Bloquear si:

- hay texto cortado;
- hay elementos superpuestos;
- la tabla no es legible;
- falta fuente editable sin justificacion;
- el PDF luce generico o plano;
- no existe evidencia de QA;
- se declara cierre productivo.

## 12. Outputs obligatorios

- PDF final o instruccion de render si se opera en entorno sin render.
- Fuente editable cuando corresponda.
- Checklist QA.
- Readback operativo.
- Riesgos y pendientes.
- Estado final no productivo.

## 13. Relacion con activos internos

| Activo | Uso |
|---|---|
| ACT-0001 | Router rector obligatorio |
| ACT-0043 | Creador/gobierno de skills LF |
| ACT-0045 | Criterios de research pack, perfil/card y no duplicidad |
| ACT-0047 | Design System multicanal para PDFs, presentaciones y brandbooks |
| CREACION_SKILL_LF | Contrato operativo de creacion |

## 14. Uso de fuentes externas

Las skills externas de PDF, DOCX, PPTX y Agent Skills se usan solo como referencia de patrones. No se copian instrucciones propietarias, no se adopta runtime externo y no se confia en terceros sin governance, sandbox y judge LF.

## 15. Cierre permitido

Cierre maximo permitido:

```text
CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO PARA PRODUCCION
```

No cerrar como completo productivo, validado, aprobado o vigente.