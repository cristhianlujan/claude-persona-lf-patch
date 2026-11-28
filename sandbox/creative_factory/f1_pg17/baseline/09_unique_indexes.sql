\set ON_ERROR_STOP on
CREATE UNIQUE INDEX ux_brand_asset_alias ON lf_design.brand_assets USING btree (asset_code);
CREATE UNIQUE INDEX ux_color_token_alias ON lf_design.color_tokens USING btree (token_name);
CREATE UNIQUE INDEX ux_component_token_alias ON lf_design.component_tokens USING btree (component_token_code);
CREATE UNIQUE INDEX ux_design_system_alias ON lf_design.design_systems USING btree (design_system_code);
CREATE UNIQUE INDEX ux_spacing_token_alias ON lf_design.spacing_tokens USING btree (token_name);
CREATE UNIQUE INDEX ux_theme_binding_alias ON lf_design.theme_bindings USING btree (theme_binding_code);
CREATE UNIQUE INDEX ux_typography_token_alias ON lf_design.typography_tokens USING btree (token_name);
CREATE UNIQUE INDEX ux_lf_decisiones_gov_alias ON public.lf_decisiones_gov USING btree (id_decision);
CREATE UNIQUE INDEX creative_queue_one_active_v1 ON saly.creative_queue_claims_v1 USING btree (order_id) WHERE (state = 'ACTIVE'::text);
CREATE UNIQUE INDEX creative_runs_one_active_per_order_v1 ON saly.creative_runs USING btree (order_id) WHERE (state = ANY (ARRAY['EN_COLA'::text, 'EJECUTANDO'::text]));
CREATE UNIQUE INDEX creative_runs_one_active_per_item ON saly.creative_runs USING btree (item_id) WHERE (state = ANY (ARRAY['EN_COLA'::text, 'EJECUTANDO'::text]));
CREATE UNIQUE INDEX creative_runs_one_per_claim_v1 ON saly.creative_runs USING btree (queue_claim_id) WHERE (queue_claim_id IS NOT NULL);
CREATE UNIQUE INDEX identity_versions_open_approved_uk ON saly.identity_versions USING btree (element_id, channel_code, audience_code) WHERE ((approval_status = 'APPROVED'::text) AND (valid_to IS NULL));
