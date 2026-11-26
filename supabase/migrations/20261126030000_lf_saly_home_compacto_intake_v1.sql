-- Governed single-order intake; no existing order updates or grants.
BEGIN;
SELECT * FROM saly.creative_order_create_v1(
 p_project_id=>2, p_context_set_id=>5,
 p_code=>'SALY_HOME_COMPACTO_20261125',
 p_request_key=>'SALY_HOME_COMPACTO_20261125',
 p_title=>'Home compacto SALY',
 p_requested_by=>'CHAT_USER',
 p_scope_json=>$json${"literal_request":"ENCARGO DEL DUEÑO (chat nuevo dentro del proyecto, para no cargar el chat del alta de LF): explorar un Home de Saly que aproveche mejor el espacio. Motivo del dueño: el Home actual se ve tradicional y las apps que ya lo usan (BCP, BBVA, Yape) compactan mucho. Reglas del dueño: (1) El Home por defecto es el estado 'Uso habitual' (sin banner); la campaña es un estado temporal con banner o carrusel que se puede cerrar. (2) La fila de accesos es un SLOT VARIABLE: puede llevar 'mi disponible', 'cuándo me descuentan', Historial, Saly Rewards, Más opciones, etc.; en campañas pueden rotar y luego quedar permanentes; no los trates como fijos. (3) Textos conocidos: 'Hola, Cristhian', 'Disponible para adelantar', 'Próximo descuento 28 de noviembre', '¿Necesitas ayuda? Contáctanos por chat'. La cifra del monto aún NO está decidida: usa el marcador S/ [DISPONIBLE]. (4) Ideas a explorar, tú decides cómo: unir el monto y la acción de solicitar en una sola tarjeta, mostrar el próximo descuento dentro del bloque principal, accesos más compactos, campañas en banda delgada o carrusel. Tokens ACTIVOS de Saly, sin inventar colores. Por la ruta gobernada de siempre: registra UN pedido nuevo de Saly (Home compacto, una imagen) en saly.creative_orders y corre la skill completa; sin tocar los pedidos 11 a 21 ni reclamar el 12. Esto lo pedí también en el chat 'Alta gobernada bloqueada': este chat nuevo es el que lo ejecuta, no dupliques el pedido. Responde con id del pedido, pasos de la skill y decisiones de fondo, jerarquía y composición.","literal_origin":"OWNER_CHAT_USER","source_verification_status":"OWNER_LITERAL_IN_CURRENT_CHAT","module":"Home","state_code":"USO_HABITUAL","render_authorized":true,"rendering_authority":true,"identity_sources":{"tokens":"saly.v_identity_current","logo_code":"logo.primary.transparent","context_set_id":5}}$json$::jsonb,
 p_item_code=>'SALY_HOME_COMPACTO_SCREEN_01',
 p_item_title=>'Home compacto - Uso habitual',
 p_acceptance_json=>$json${"image_count":1,"default_state":"Uso habitual","banner":false,"variable_access_slot":true,"amount_literal":"S/ [DISPONIBLE]","official_tokens_only":true,"official_logo":true}$json$::jsonb,
 p_context_json=>$json${"screen_spec":{"screen":"HOME","device":"IPHONE16PRO"}}$json$::jsonb
);
COMMIT;
