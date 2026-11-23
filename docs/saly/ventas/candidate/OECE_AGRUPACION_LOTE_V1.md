# SALY Ventas — Vínculos empresariales v1 (candidato, 23/11/2026)

**Estado:** DRAFT, schema-only. No importar OECE ni activar runtime, CRM, publicidad o contacto.

## Histórico y situación
- Prueba anterior reportó 413.016 filas de socios OECE, 75 propietarios que vinculaban 161 empresas de un universo de 7.514 RUC SALY.
- El CSV original, SHA256 y la relación detallada no quedaron conservados, por lo que esos conteos son históricos NO reproducidos.
- Lectura de SALY 23/11: 7.514 RUC jurídicos 20... bajo PE-SUNAT-RUC.
- Fuente OECE: https://www.datosabiertos.gob.pe/dataset/personas-declaradas-en-la-conformaci%C3%B3n-jur%C3%ADdica-de-proveedores-en-el-registro-nacional-de
- En catálogo: licencia **License Not Specified**. Datos declarados por proveedores; actualizaciones mensuales; no equivalen a control societario vigente.

## Alcance exacto
- Una migración vacía con dos tablas saly.ventas_vinculos_empresariales_v1 y saly.ventas_vinculos_evidencias_v1.
- Cada arista tiene dos RUC jurídicos, tipo, estado, fuente y corte, sin agrupar transitivamente. Evidencia en tabla dependiente con ON DELETE RESTRICT.
- SOCIO_DECLARADO no acredita control ni un grupo económico. Estados CORROBORADO y CONTROL_VERIFICADO exigen metadatos de verificación; control adicional de calidad documental corresponde a la futura puerta gobernada.
- RLS ENABLE + FORCE para ambas tablas desde la creación, revocación para PUBLIC, anon, authenticated, service_role. Sin políticas ni grants a runtime hasta diseñar la operación bajo permisos mínimos.
- Ningún dato real o sintético queda insertado: el SQL de pruebas corre en PostgreSQL 17 descartable y realiza ROLLBACK.

## Gates sin suplantación
1. PR DRAFT hasta PG17 real con positivos/negativos, RLS y ROLLBACK; PASE, clasificación, HEAD y Merge Train gobernado.
2. Habilitación de ingestión OECE solo al recuperar CSV, SHA y contrato de columnas, y después de resolver los derechos de reutilización.
3. Cierre como grupos controlados únicamente tras evidencia societaria independiente, vigencia y verificación por RUC.
4. Readback real en Supabase separado de los resultados de CI; la existencia de secuencias o migración no prueba filas.
