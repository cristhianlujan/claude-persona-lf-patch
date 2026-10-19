# PE10 C5→C6 · conciliación de autoridad GPT Native v0.2

**Estado:** diagnóstico/readback verificable y propuesta de reparación; **no** es cambio de contrato, aprobación independiente, activación de v0.2 ni cierre de checkpoint. Operación `ACTUALIZACION_PERFIL_LF`, plan `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1`, unidad `PE10`. No mezclar con el productor del perfil Reparador.

## Lote 1: comprobación real (sin repetir evaluación semántica)

| Evidencia / control | Valor leído | Interpretación |
|---|---|---|
| `EVIDENCE_LEDGER SOURCE_SNAPSHOT` sujeto `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10` | `37db027e-ad58-4cbb-b4dc-01b7568f6ac2`, `VERIFIED`, SHA `73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a` | Recibo existente: **no recrear** ni asumir que certifica el RAW de C6. |
| Material `GPT_NATIVE` de C6 en el chat actual | `pe10_c6_same_chat_gpt_material_authoring_20261016.json`: handoff `c07498fa3cd34ad65e296d63536c743a251d90834f4698ecd7ed318db293692a`, RAW `dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde` | Autoría vinculada; **no** invocación externa ni permiso operativo. |
| Fuente del perfil | `profiles/systemic_root_cause_repair_lf/SKILL.md` SHA-256 `2187c2671d0c05e7db0939b987c0a64f032e8d837603470b1330be61cf4e21f7` | Correspondencia de bytes probada sobre el árbol real por CI. |
| CI HEAD `f4491266d44424e52d7e9c468eb4e8a3fd8478d2` | Profile GPT Native Capture Regression [38990757053](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38990757053): **26/26 PASS**; PASE [38990757037](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/38990757037): **SUCCESS** | Incluye 2 verificaciones con material congelado real: hashes/fuente y rechazo sin recibo. Otros positivos usan dobles; CI no equivale a semántica independiente. |
| Ledger para RAW `dfbd274f…` | 0 coincidencias por `subject_sha256` | No emitir ni declarar un VERIFIED. |
| `INDEPENDENT_ASSURANCE` PE10 | Existe `EXEC-PE10C3-INDEP-e983544d2ee0aeb9`, `IN_PROGRESS`, vinculado al **sujeto global** SHA `73c884…` | No reutilizar como si fuera un revisor del RAW `dfbd…`. Evento 21093: `NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT`. |
| `METHOD_PACK_REGISTRY` actual | v1.0.0, portfolio `[]`, `qualified_methods_available=0`, `allow_runtime_execution=false` | No certificar motores externos. |
| Checkpoints/versionado | C1/C2/C2B/C3/C4 `DONE`; C5/C6/C7 `PENDING`; v0.1 activa | Avance verificable 5/8; no inventar cierre. |

## Diagnóstico de raíz — dos contratos no equivalentes

1. **Contrato C5 vigente en Supabase** (`unit_metadata.checkpoint_contracts.PE10_C5` + `action_specs_v1.PE10_C5.verification_queries`) exige `qualified_methods=8`, `method_execution_verified=true`, evento `PROFILE_EVOLUTION_CUTOVER_ADMITTED`, recibo `SAFE_CHANGE_ADMISSION` y evidencia de selección. Esto modela **engines certificados** y no la **autoría razonada en GPT Native dentro del chat** ya acordada. Repetir los 8 motores para desbloquearla sería un cambio de finalidad, no una verificación.
2. **Adaptador en PR #2851** resuelve únicamente un hipotético `INDEPENDENT_REVIEW_RECEIPT` de `PROFILE_NATIVE_CHAT_MATERIAL_REVIEW` y `subject_ref=…/PE10_C5`. Ningún productor autorizado actual crea esa combinación. El revisor existente `public.lf_independent_review_begin_v3` acepta sujetos genéricos, pero necesita **SOURCE_SNAPSHOT exacto, dispatch, reviewer distinto, pasos y veredicto real**. Un lector y 26 pruebas no crean esa evidencia.
3. La evidencia C3 y la de autoría C6 **no comparten digest/sujeto**. El recibo histórico global `73c884…` no puede hacerse pasar por el RAW de C6 `dfbd…`. No atribuir a la revisión de C3 una aprobación de experto que no otorgó.

## Reparación mínima propuesta: un Updater dinámico, dos medios de ejecución tipados

```text
Selección dinámica v0.2 (fuente/plan congelados)
  ├─ GPT_NATIVE / CLAUDE_NATIVE, MISMO CHAT
  │    └─ RAW + hashes + método aplicado como razonamiento
  │       └─ control estructural independiente + revisión semántica real
  │          └─ evidencia de autoría, SIN certificado de motor ni API
  └─ METHOD_PACK_EXECUTOR (solo cuando método externo sea necesario)
       └─ método seleccionado QUALIFIED + permiso + recibo por ejecución
             └─ evidencia externa apta
   ↓
SAFE_CHANGE_ADMISSION vigente + comprobación C5 sobre modalidad tipada
   ↓
C6 ensayo positivo Y negativo, BEGIN/ROLLBACK, sin activar v0.2
   ↓
C7/readback separado y decisión posterior de producción
```

### Cambios necesarios **a diseñar/autorizar** sobre el contrato canónico

- Resolver `execution_mode` en la **admisión**, no inferirlo de la palabra «método». Para autoría nativa, comprobar RAW actual, fuente, selección, límites y revisión semántica independiente **sin crear motores externos**; para ejecución de packs, exigir calificación/recibo **de cada método realmente seleccionado**, no `count=8` global. Mantener una única v0.2 dinámica y no fabricar una versión `LIMITED`.
- Ligar evidencia RAW a `INDEPENDENT_ASSURANCE` por un **sujeto exacto gobernado** (tipo y ref aprobados, digest RAW, readback GitHub/Supabase), produciendo SOURCE_SNAPSHOT y revisión con la operación genérica ya existente y sus seis pasos. No reutilizar C3 como si hubiera revisado el RAW; no introducir un segundo motor de revisión. Revisar compatibilidad de la forma del recibo genérico *antes* de cambiar el lector de #2851; su `_REVIEW_TYPE` actual es **provisional**.
- Emitir solo un evento de admisión real cuando el mismo consumidor haya validado fuente, revisión semántica, método/modo, SAFE_CHANGE_ADMISSION y preestado. Nunca hacer PASS por un nombre de referencia sin readback ni autorizar cutover por el hash de una captura.
- Mantener C5=C6=PENDING durante el cambio de contrato. Confirmar efectos de `checkpoint_contracts`, `action_specs_v1`, `source_pack_v2`, `acceptance_criteria`, consumidor/candidato y las invariantes de política antes de una migration. Usar Migration/Train; no SQL directo.

**Límite de alcance:** el cambio de la semántica C5 (de 8 motores obligatorios a ejecución tipada) modifica la **fuente oficial de admisión**. Este documento no lo aplica y requiere aprobación explícita como reparación de contrato. No pide una campaña de evaluación nueva.

## Criterio del siguiente lote

- **Positivo:** ruta gobernada emite evidencia no sintética vinculada a RAW; C5 acepta solo modalidad válida, preserva `cutover_eligible=false` hasta el gate; C6 demuestra admisión y rechazo con rollback; postreadback v0.1, 0 residuo.
- **Negativos:** sujeto global C3 usado para RAW, hash diferente, revisión propia, recibo inexistente, `QUALIFIED` ausente en método externo, falsa atestación, omisión de SAFE_CHANGE_ADMISSION, intento de activación: todos deben rechazar.
- **STOP:** sin consumidor actualizado y sin recibo válido = C5 no PASS. Ninguna prueba de integridad convierte automáticamente una revisión semántica fallida en PASS.
