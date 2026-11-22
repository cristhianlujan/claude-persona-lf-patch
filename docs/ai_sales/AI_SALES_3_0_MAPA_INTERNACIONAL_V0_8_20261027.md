# AI Sales 3.0 — Evolución v0.8 de selección internacional

**Estado:** PROPUESTA EN PR BORRADOR. La v0.7 sigue siendo la versión oficial hasta admisión del Router y Merge Train.

## Diferencial validado

| Unidad | Cambios | Resultado |
| --- | --- | --- |
| U02 | C06 y C07 ampliados; nuevo C13 | Grupo > sociedad jurídica > sucursal > establecimiento, identificador por país y fuente |
| U03 | C06 y C10 ampliados | Catálogo de fuentes y verificación de hechos por jurisdicción, dependencia y vigencia |
| U04 | C06 ampliado | Contratos de adaptadores, permisos, cuotas, errores y alternativas manuales |
| U07 | C06, C08, C20 ampliados; nuevo C21 | Búsqueda multifuente, deduplicación y enriquecimiento en cascada con parada/costo |
| U08 | C07 ampliado; nuevo C14 | Contactabilidad por país/subjurisdicción, canal, persona, producto y finalidad |
| U12 | C10 ampliado; nuevo C11 | Calibración y pruebas multinacionales con no regresión de SALY Perú |

**Totales:** 18 unidades sin cambios, 188 checkpoints anteriores conservados, 10 contratos ampliados, 4 CP nuevos: **192 previstos**.

## Referencias técnicas de investigación 2026

| Región | Fuente de partida | Alcance y advertencia |
| --- | --- | --- |
| Perú | SUNAT RUC | Identidad jurídica; no inferir plantilla ni demanda |
| Colombia | RUES, SECOP, DANE | Sociedad y sucursal / contratación / estadística; verificar términos de acceso |
| México | INEGI DENUE | Establecimientos, no siempre empresas legales; agrupar con evidencia |
| Brasil | Receita Federal CNPJ | Compañías/establecimientos y sus relaciones |
| Estados Unidos | SEC EDGAR | Solo entidades que presentan información a SEC |
| Reino Unido | Companies House | Sociedades registradas, estados y documentos |
| Unión Europea | BRIS | Consultas a registros nacionales vinculados |
| Comercial | Clay, Microsoft Sales, 6sense, Demandbase | Selección por cuenta, waterfall, intent y ajuste a resultados (referencias de diseño, no promesas de rendimiento) |

Las fuentes, políticas de contacto y disponibilidad de APIs se deben comprobar nuevamente al ejecutar cada país. La investigación no confiere licencia de extracción o publicidad.

## Criterios de ejecución

- Separar **grupo, empresa legal, sucursal y establecimiento**. Evitar fusiones automáticas por nombre/marca.
- Conservar los niveles **C0-C3 por atributo**, sin expresarlos como probabilidad calibrada.
- En el **waterfall**, primero reglas/fuentes económicas y permitidas; continuar únicamente si reduce incertidumbre decisiva; guardar motivo de parada y fuente.
- Contactabilidad independiente de scoring; si la jurisdicción/canal/producto/finalidad carece de admisión suficiente: `HOLD`.
- G0 SALY Perú continúa sin esperar el desarrollo de todos los adaptadores extranjeros.
- No se activan agentes, cuentas, campañas Meta, anuncios, envíos ni gastos.

## Readback exigido al Merge Train, una vez autorizado

1. El preestado debe ser exactamente evento v0.7 **21637** con digest `6b7891742f570f6337cc8ab288e3eafb09f21ce428d18fea98663622dab9c966`.
2. Mantener los 18 work items, 188 checkpoint IDs/títulos/secuencias/estados y el historial de versiones anteriores.
3. Registrar 4 nuevos checkpoints `PENDING`; total 192, y ampliar 10 criterios por unidad sin alterar las identidades previas.
4. Todos los checkpoints conservan contrato, evidencia de cierre y ausencia de revisión independiente.
5. Ningún efecto sobre runtime ni autorizaciones comerciales; completar solamente mediante `ACT-0001 → ACTUALIZACION_DB_LF → LF Migration Merge Train`.

**Importante:** la existencia de esta rama y del PR borrador no es autorización del Router para ejecutar la migración. No asignar la etiqueta `ready-to-merge` sin evidencia de esa autorización.
