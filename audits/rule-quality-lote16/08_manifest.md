# Lote 16 — Manifiesto de auditoría para el dueño

**Estado:** NO-GO / UNVERIFIED. No hay dictamen de producción ni PASS funcional.
**Auditor:** GPT-6, mismo modelo GPT; **juez NO independiente**. La identidad solicitada «Claude» NO está acreditada; no hubo segunda llamada a juez ni recibo externo.

## Alcance y fuente
- Supabase: `https://mhwmirqcgxxukpctffuv.supabase.co` (identidad del proyecto consultada mediante la conexión). Usuario de conexión: `supabase_read_only_user`; PostgreSQL 17.6. Solo SELECT. El banco PG18 del dueño es EXTERNO y **no fue ejecutado por este auditor**.
- Repositorio: `cristhianlujan/claude-persona-lf-patch`.
- Rama única de escritura: `lf/issue-3779-lote16-owner-triage-v1`, creada **desde** `lf/issue-3779-lote12-rule-quality-audit-v1` (fuente del mapeo y del informe del Lote 12).
- EKB leído: **INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4**, estado `CANDIDATO VERIFICADO PARCIALMENTE`. Se respetó autoridad de contratos desplegados y prohibición de rutas paralelas.
- El dueño reportó PASS externo Lotes 11C, 13, 14 y 15, con md5 `apply 86b04949`, `capture_record 89cbfac4`, `citation_verify 773a6278`, `l8 guard 522d12f0`. **No son hashes ni gates reproducidos dentro de este lote.**

## Fuentes SQL y SHA-256 verificables (OBJETIVO)
Los SHA-256 son de la serialización **JSONB canónica** del arreglo de filas completo, ordenado por texto de fila, codificado UTF-8 en PostgreSQL con `sha256(convert_to(...))`. SQL completo y método en `07_evidencia_select.sql`. No confundir estos digests con el Git blob SHA-1.

| ID | Dato extraído por SELECT | Filas | SHA-256 del resultado |
|---|---|---:|---|
| S01 | Inventario LF para familias, título, descripción, estado | 578 | `59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9` |
| S02 | Reglas VIGENTE y pendiente_decision=true | 57 | `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` |
| S03 | Referencias numéricas VIGENTE→CANDIDATO | 3 | `8b70da4a3d3b381620473202de4a569d4b09fcfda6b3973e81661c3d2631b46a` |
| S04 | Pares mismo campo/distinto valor con pantalla en común | 20 | `815d9f903189c7fe98c5b6c8ae7a32ca4b061d3422033010140fe60230f2dd3f` |

- **S01 OBJETIVO:** 578 reglas, 412 VIGENTE y 166 CANDIDATO. 15 familias propuestas por el mapeo del Lote 12, 71 ejemplos reales disponibles (14 familias con cinco; RETENCION con una).
- **S01 + mapeo L12 REQUIERE_REVISION_SEMANTICA:** 23 pertenencias dudosas señaladas individualmente, sin recategorizar registros.
- **S02 OBJETIVO:** 57 pendientes. **REQUIERE_REVISION_SEMANTICA** su agrupación de responsabilidad primaria: Legal=10, Negocio=4, Operaciones=8, tecnico/ledger=21, copy visual=14. Cada acción humana está marcada SUGERENCIA; hay posibles responsables secundarios.
- **S03 OBJETIVO:** 3 dependencias; **REQUIERE_REVISION_SEMANTICA** decidir promover/quitar/dejar y evaluar consecuencias. MFA: mantener fail-closed hasta pruebas.
- **S04 OBJETIVO:** 20 pares con `pantallas_comunes`; **REQUIERE_REVISION_SEMANTICA** la hipótesis «OPERACIONES_DISTINTAS_PROBABLE» en los 20. Nunca se afirmó contradicción por igualdad de campo.
- Cuatro candidatos de control débil: `REG_CHK_001`, `REG_OFR_001`, `REG_OFR_002`, `REG_OFR_008` reportados por el Lote 12 / dueño; **no se prueba aquí que realmente sean defectuosos**.

## Entregables
1. `01_familias_triage.md` — 15 familias; cantidad, cinco ejemplos cuando existen y citas exactas de dudas.
2. `02_pendientes_57.csv` — decisión primaria, texto pendiente literal truncado, propuesta humana.
3. `03_referencias_3.md` — textos origen/destino completos y riesgo de las tres opciones.
4. `04_parametros_20.csv` — pares, magnitudes, sujetos, evidencia textual y clasificación no concluyente.
5. `05_decisiones_dueno.md` — 12 preguntas ordenadas por impacto.
6. `06_respuestas_dueno.csv` — respuestas vacías, solo contiene sugerencias no vinculantes.
7. `07_evidencia_select.sql` — SELECT íntegros y SHA-256.
8. `08_manifest.md` — este registro.

## Ejecución, validación y cierre
- **Consulta de fuentes:** Supabase únicamente SELECT, no se ejecutaron DML/DDL.
- **Escritura:** solo artefactos documentales/CSV/SQL en rama nueva; no se tocó `main` ni rama fuente L12.
- **No se hizo:** ningún RUN de perfil, Input Governance operacional, modificación de reglas, activación, aprobación, merge, CI, producción, juicio externo ni pruebas PG18.
- **Readback:** verificación de los ocho archivos desde la rama y SHA de commit debe realizarse tras completar la escritura; un Git readback exitoso solo certifica publicación de documentos, no eficacia de controles.
- **Pendientes:** respuesta y validación del dueño; revisión semántica independiente si requerida; cualquier implementación se hará en lote posterior con autorización separada.
- **Cierre:** **NO-GO / UNVERIFIED** hasta constancia posterior. No promocionar ninguna regla por este informe.
