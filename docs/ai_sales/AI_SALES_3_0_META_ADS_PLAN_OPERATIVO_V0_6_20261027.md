# AI Sales 3.0 — Meta Ads (Facebook e Instagram) v0.6

**Estado:** planificación propuesta. No hay pauta enviada, campañas activas, cuenta conectada, gasto aprobado, Pixel ni Conversions API activados.

## Propósito y límites

Añadir un carril de adquisición paga que convierta tráfico/visibilidad en oportunidades **SALY B2B verificadas**. No confundir:
- **Publicidad Meta** (campañas, anuncios e impresiones en Facebook/Instagram).
- **Mensajería directa** (WhatsApp/DM/email), que requiere autorización y controles independientes.
- **Envío a Meta de eventos o listas**, que implica privacidad/propósito y restricciones específicas de la fuente de datos.

El presupuesto inicial de licencias/API sigue en **US$0**; **compra de medios** es un gasto distinto y no está aprobado por el plan.

## Advertencia de elegibilidad

Las políticas actuales de Meta restringen/prohíben promociones de *paycheck advances*, payday loans y otros préstamos de corto plazo. La oferta SALY B2B, el texto de anuncio, la llamada a la acción y la landing deben evaluarse conjuntamente y documentarse antes de anunciar. No disfrazar una oferta no permitida como «beneficio corporativo». El marketing de marca o un mensaje corporativo solamente se evaluará si realmente es distinto y admisible; no tiene pase automático. Aplicar clasificación de categoría especial y restricciones de segmentación cuando correspondan al país y al producto, sin trasladar mecánicamente reglas de EE.UU. al Perú.

**Gate fail-closed:** `PROHIBITED / UNKNOWN` = sin publicación ni gasto. Puede evaluarse un diseño de campaña, sin publicación, mientras no exista elegibilidad.

Referencias de política a verificar de nuevo al implementar:
- Meta Advertising Standards: https://transparency.meta.com/policies/ad-standards/
- Meta Business Help Center (Special Ad Categories): https://www.facebook.com/business/help/298000447747885
- Colección oficial Marketing API de Meta: https://www.postman.com/meta/facebook-marketing-api/overview

## Unidad U17 — 18 checkpoints
| Código | Trabajo |
|---|---|
| U17-C01 | Elegibilidad por oferta, anuncio y landing |
| U17-C02 | Activos y verificación de cuenta Meta |
| U17-C03 | API Marketing, permisos y rate limit |
| U17-C04 | Objetivos de campañas y embudo B2B |
| U17-C05 | Audiencias, ubicaciones y segmentación permitida |
| U17-C06 | Creatividades, formatos y copy verificable |
| U17-C07 | Constructor Meta y creación PAUSED |
| U17-C08 | Aprobación de publicación y presupuesto |
| U17-C09 | Presupuesto y optimización de pacing |
| U17-C10 | Pixel y Conversions API con privacidad |
| U17-C11 | Lead Ads y entrada CRM |
| U17-C12 | Landing corporativa y medición de clics |
| U17-C13 | Insights y atribución hasta convenio |
| U17-C14 | Feedback de conversiones CRM permitido |
| U17-C15 | Experimentos A/B y optimización |
| U17-C16 | Frecuencia, fatiga y experiencia publicitaria |
| U17-C17 | Rechazos, anomalías y recuperación |
| U17-C18 | E2E de entrega publicitaria y oportunidad |

## Contrato de publicación
1. Cuenta y Página/Instagram autorizadas; permisos mínimos, tokens protegidos.
2. Clasificación de oferta, anuncio, CTA, landing y país con políticas vigentes.
3. Segmentación y creatividades verificadas; anuncios **PAUSED** inicialmente.
4. Autorización humana específica para **cuenta, campaña, monto, moneda, periodo, límites y responsable**.
5. Meta revisa el anuncio; rechazo o cuenta restringida cancela despacho.
6. Después de autorización, evidenciar entrega mediante estado e **impresiones** en Insights. `ACTIVE` de configuración por sí solo no prueba que Meta lo mostró.
7. Reportar en CRM *leads cualificados, reuniones y convenios*, además de CTR/CPL/gasto; pausar por presupuesto, fatiga, quejas o mal desempeño.

## Integración con el plan anterior
- U00: riesgo/compliance/costo de pauta.
- U02: procedencia Meta y consentimiento.
- U04: Marketing API y webhooks.
- U08: separar audiencia publicitaria de mensajería.
- U09: landing, formularios y CTA.
- U11: CAC/costo por oportunidad y reconciliación Meta↔CRM.
- U12: prueba controlada con presupuesto solo si autorizado.
- U16: cuota, latencia y recuperación.
- **G0** admite diseño/viabilidad Meta en lectura, no gasto; **G2** incluye U17 como carril **condicional**, sin bloquear otros canales si el producto no es elegible.

## Readback del registro de plan
Se esperan **18 unidades / 180 checkpoints PENDING**. Todos los **162 previos permanecen con el mismo ID y estado**; se añade solamente U17 con 18 nuevos. El snapshot v0.5 permanece en el evento 21630. Ningún checkpoint necesita una ronda de revisión independiente.

**Importante:** la migración sólo registra planificación; no crea cuentas Meta, campañas, licencias, secretos, colas, gastos ni eventos de marketing.
