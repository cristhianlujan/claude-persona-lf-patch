# SALY — Home-first / EXPLORE v0.3

**Estado:** candidato de diseño. No equivale a identidad oficial ni estándar activo.
**Objetivo:** producir nuevas pantallas SALY con libertad de composición, preservando los dos tokens oficiales y el logo de Drive. No copiar el Home como plantilla rígida.

## Fuentes y autoridad

| Fuente | Se usa para | Autoridad |
|---|---|---|
| `saly.v_identity_current` | Dos verdes aprobados: marca `#00C853`; CTA blanco `#008200` | OFICIAL |
| `saly.identity_elements / identity_versions` (prefijo `candidate.saly_ds_v1.`) | Diez colores, cuatro radios, siete espaciados, ocho roles tipográficos, tres reglas de accesibilidad | CANDIDATE |
| `saly.identity_elements / identity_versions` (prefijo `candidate.saly_home_v3.`) | Seis colores/aliases + una sombra opcional | CANDIDATE EXPLORE |
| Drive `1JbkHTPOhacOdA3dbO_kQgjn8LAP-yHOQ` | Evidencia visual Home v3 Rewards/Sorteos | REFERENCIA, no valor HEX/dp verificable |
| Drive logos oficiales / `saly.brand_assets` | Logo, sin regenerarlo | FUENTE APROBADA; archivo/hashes según registro y verificación |

## Paquete de trabajo propuesto

- **Fijos:** logo oficial; `color.brand.primary` únicamente marca; `color.action.primary.bg` para CTA blanco. Respeto de información y controles funcionales.
- **Reutilizables en exploración:** `#081631` navy, `#5C6577` texto secundario, superficies blanco/mint/Rewards, purple Beneficios, scale 4/8/12/16/24/32/48, radios 14/16/24/pill; tipografía Inter **no verificada**. Todos estos roles siguen siendo candidatos.
- **Nuevos candidatos del Home:** `color.surface.benefits=#F4E7FD` (estimación); navegación activa `{color.action.primary.bg}`, inactiva `{color.ink.gray.600}`, fondo `{color.surface.white}`; `module.benefits.bg` alias del surface; `notification.badge=#E62F40` (estimación).
- **Sombra opcional:** `elevation.card.hero` = offset(0,4), blur16, spread0, navy #081631/0.1, **no medido**; diseñador puede variar o quitarlo en `EXPLORE`.
- **Fuera de tokens de marca:** menú actual Inicio / Historial / Explorar / Perfil; iPhone 16 Pro como referencia de dispositivo; el PNG 1086×1448 incluye frame completo y **no** prueba tamaño nativo ni safe areas.
- **No promover:** `candidate.saly_ds_v1.semantic.color.action.primary.bg` porque apunta a un color de rol conflictivo; proteger verde CTA vs verde de marca.

## Regla de compilación visual (futura, no implementada aquí)

`request -> resolver oficial -> resolver de candidatos explícitos -> brief pantalla -> libertad de composición -> imagen candidata -> QA`.

Los aliases a candidatos necesitan resolución controlada: no se deben exponer como tokens oficiales ni usarse en producción sin aprobación y prueba de dependencias.

## Readback esperado tras lote A + B

- 2 oficiales efectivamente seleccionables, sin cambios.
- 46 candidatos preexistentes, de los cuales 32 están seleccionados para la prueba visual.
- 7 candidatos nuevos Home v3, todos `DRAFT/CANDIDATE`, ninguno efectivo.
- Total en SALY: 55 elementos / 55 versiones. **0 estándares activos**.
- No se modifica código de perfil UI, imágenes, menú de producción ni esquema `visual`.

**Riesgos pendientes:** contraste funcional y modo oscuro de colores no oficiales; tipografía nativa sin source de diseño; viewport/safe areas; UX de navegación alterna; falta de versión vigente de estándar visual. Son insumos de exploración, no bloqueos para bocetar.
