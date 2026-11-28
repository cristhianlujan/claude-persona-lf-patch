-- Internal SALY research catalog. Existing institutional-publication file only.
-- Register channel metadata; no publications, personal information, automated
-- collection, permissions changes or source activation in this migration.
BEGIN;
INSERT INTO saly.ventas_discovery_catalogo
(catalog_version,source_id,connector_id,substep_code,step,familia,nombre,landing_page,
 rights_status,persist_business_data,habilitada,runtime_status,copy_text_permitted)
VALUES ('PE-SALY-DISCOVERY-2026-11-V0.2','PE-FACEBOOK','SALY-U07-S14-C01','14.01',14,
 'RED_SOCIAL','Facebook','https://www.facebook.com/','PENDIENTE_VERIFICAR',
 false,false,'SPEC_ONLY_NOT_CONNECTED',false);
DO $check$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.v_ventas_social_fuentes_v1
  WHERE source_id='PE-FACEBOOK' AND source_name='Facebook'
  AND estado_catalogo='REGISTRADA_NO_HABILITADA')
 THEN RAISE EXCEPTION 'SALY_CATALOG_READBACK_FAILED'; END IF;
END $check$;
COMMIT;
