# Lote 27 — Manifiesto de cierre documental / NO-GO

## Identidad y alcance

- **Autor/juez:** GPT-6, **mismo modelo**, revisión no independiente; identidad Claude no acreditada. Esta es **reconciliación documental de decisiones del dueño**, no una revisión semántica independiente.
- **Base Git exacta:** `dce10390aafdbf9a05362fde8b8799055c6b0319` (L25).
- **Rama nueva:** `lf/issue-3779-lote27-owner-decisions-register-v1` del repo `cristhianlujan/claude-persona-lf-patch`.
- **Dossier L21 importado:** ocho archivos del commit `4c3e376c62a3ae488d1c031ba7043d686919a65d`, bajo `audits/rule-quality-lote21/`.
- **Sólo documento:** no Supabase (ni siquiera SELECT nuevo), no PG18, no DML/DDL, no producción, no cambio RUN, no gates, no L25 propuestas. El SQL copiado de L21 y el borrador P27_01/P27_02 **NO SE EJECUTARON EN L27**.
- **Fuente EKB:** INPUT GOVERNANCE LF V1.4, CANDIDATO VERIFICADO PARCIALMENTE, SHA-256 bytes `234fafb2b06b91e96a979feac138069ec75863aae1bd75aea93c72740c075f79`.

## Resultado de reconciliación

| Estado del CSV | Total | IDs |
|---|---:|---|
| `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` | **3** | L16-Q03, L16-Q04, L16-Q05 |
| `RECOMENDADA_SIN_CONFIRMAR` | **1** | L16-Q01 |
| `PENDIENTE` | **28** | L16-Q02, L16-Q06..Q12, L19-Q01..Q08 y L21-X01..X12 |
| **TOTAL** | **32** | **32 IDs distintos, mismo set L21** |
| **Firmas formales verificadas** | **0** | Identidad/firma/fecha/recibo en blanco |

- **Q03:** opción A, Niubiz único para recaudo tarjeta/Yape; producción sigue condicionada a contrato, callbacks, componente PCI del proveedor, ledger Q02, sin credenciales DEMO.
- **Q04:** subdecisiones confirmadas sobre estados, sin gracia, corte Lima, conciliación indeterminada, cancelación EN_PROCESO/VENCIDA y autoantigüedad 12 meses con variable; **cuatro pendientes exclusivos**: reintentos automáticos, recordatorios, mora, destino contable INCOBRABLE.
- **Q05:** opción A, pricing versionado con vigencias sin huecos/solapes, historial no editable ni borrable, no cotizar sin versión vigente, snapshot del plan y actualizador autorizado por permiso de perfil. Fuente física/permisos pendientes.
- **Q01:** MFA C recomendada **sin aceptación**; Q02 ledger **PENDIENTE** y construcción de Producto/QA fuera de IG.
- **L25:** 13 propuestas de reglas y 1 parámetro CANDIDATO **no aprobados, no promovidos**. Estado conversacional no es firma de aprobación de regla.

## Restricción probatoria sobre permisos Q05

- **Lectura histórica objetiva L19/L21:** 45 permisos, cero asignaciones usuario-perfil en tablas inspeccionadas; L19 O2 SHA-256 `0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d`; L21 S21_01 SHA-256 `4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933`.
- **Dato comunicado por dueño:** 16 `resource_type` y ausencia de permisos pricing. **No se ejecutó SELECT nuevo ni se verificó ese detalle directamente en L27**.
- **Borrador SQL documentado:** `02_pricing_permission_select_no_ejecutado.sql`. Resultados/sha propios del borrador: `NO_EJECUTADO`; no inventar SHA de resultados. No confiar únicamente en regex para una prueba semántica de permisos.

## Preservación exacta de L21

| Archivo importado sin cambio | Git blob SHA-1 L21 = L27 |
|---|---|
| `audits/rule-quality-lote21/02_matriz_bloqueos_produccion.md` | `797cbe3cd31d54b0c45fca15583733c1be6ef1f7` |
| `audits/rule-quality-lote21/03_tablero_12_etapas.md` | `bb3faa6b6412b5c540ff0670fb0de0166809e9a6` |
| `audits/rule-quality-lote21/04_go_no_go_firmable.md` | `d519694d3c1d0490360b9f85e6f23a211be740ba` |
| `audits/rule-quality-lote21/06_select_evidencia_live.sql` | `5d9180582b6453caadd786a58fe6f07b4c42d277` |

**Tablero:** se preserva el alcance histórico de L21 (15/36 etapas REAL_EN_SANDBOX = 41,7%; 0/36 etapas productivas nativas acreditadas). L23 puede tener experimentos posteriores pero **no fueron ejecutados ni contabilizados en L27**.

**GO/NO-GO:** el checklist L21 conserva sus **15 gates NO_VERIFICADO**, casillas sin marcar, sin firma; por tanto producción sigue NO-GO.

## Hash exacto de archivos nuevos/actualizados antes de este manifiesto

SHA-256 UTF-8 sobre contenido GitHub (algoritmo verificado con SHA256('abc')), más blob SHA-1 reportado por GitHub. Hash de resultado SQL es otra cosa y **no se calculó de nuevo**.

| Archivo | SHA-256 UTF-8 | Git blob SHA-1 |
|---|---|---|
| `audits/rule-quality-lote21/00_portada_dossier.md` | `6264632f1d26019642b986d58dbd5fba54931666f92902d0e31aa18bb25f468f` | `7f216dc3fac06e8cf04d376091c82a3428d761f5` |
| `audits/rule-quality-lote21/01_registro_unico_decisiones.md` | `50df21489d05ea859d0d8a7b0c5f61cabf7dc47d333105d8de0c7fc3677f5846` | `4a791c544350354324adf0b19d795448491b21eb` |
| `audits/rule-quality-lote21/05_respuestas_dueno.csv` | `6be7a1eb2ae3b3a45ab166ea953ff39af559469bcf33ae1a2eaf66724b961c73` | `a8066e4747bb61dca55a76ec2f71fe4fa6f58c2d` |
| `audits/rule-quality-lote21/07_manifest.md` | `ba96e15fd7fdf655068cfb233e8ed06d5d40c5394a0007242fff16501f6f88ff` | `a38366a34bd63ef8f231f12047fd51203b67ac66` |
| `audits/rule-quality-lote27/00_antes_l21_despues_l27.md` | `27a5131565bb4009dc8f0686de78724c3663028368e5993a6041b5a0b289a425` | `f2dcc023c917a0149c711a5b151df3ba74e4cbf4` |
| `audits/rule-quality-lote27/01_matriz_reglas_afectadas.md` | `134bb70ec73d08a4b20b60a16dae99c5dc2e7f7097d623e1255bd1a307e97f8d` | `19a028d3d82a9cf992c0209708730909623b9555` |
| `audits/rule-quality-lote27/02_pricing_permission_select_no_ejecutado.sql` | `4a16538525bb30b9d6148ee94ee94fed8af1ea72cb0002023df20c5d844f524c` | `22ea56e72b29a6c0738fc532d8060eb4e24daf12` |

## Índice de cierre

- `audits/rule-quality-lote21/01_registro_unico_decisiones.md`: registro único de 32 estados.
- `audits/rule-quality-lote21/05_respuestas_dueno.csv`: 32 respuestas y 0 firmas, mismo set de IDs.
- `audits/rule-quality-lote27/00_antes_l21_despues_l27.md`: comparativo explícito.
- `audits/rule-quality-lote27/01_matriz_reglas_afectadas.md`: reglas por decisión + gobierno, propuestas L25 no adoptadas.
- `audits/rule-quality-lote27/02_pricing_permission_select_no_ejecutado.sql`: solo borrador de futura verificación.
- `audits/rule-quality-lote27/03_manifest_evidencia_readback.md`: este manifiesto.

**Readback de la rama tras escribir este archivo:** verificar `HEAD`, el árbol limitado a dos carpetas y los hashes del registro/CSV. No representar como terminado antes de la lectura final.

**DICTAMEN DOCUMENTAL:** `REGISTER_RECONCILED` condicionado a readback. **FIRMA: 0/32**. **PRODUCCIÓN NO-GO / UNVERIFIED**.
