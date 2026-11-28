\set ON_ERROR_STOP on
CREATE INDEX brand_assets_lookup_idx ON saly.brand_assets USING btree (project_id, code, valid_from DESC) WHERE (approval_status = 'APPROVED'::text);
CREATE INDEX creative_deps_ready_idx ON saly.creative_item_dependencies USING btree (order_id, item_id);
CREATE INDEX creative_items_queue_idx ON saly.creative_order_items USING btree (order_id, status, ordinal);
CREATE INDEX creative_orders_queue_idx ON saly.creative_orders USING btree (project_id, status, created_at);
CREATE INDEX creative_queue_item_history_v1 ON saly.creative_queue_claims_v1 USING btree (item_id, id DESC);
CREATE INDEX creative_runs_expiry_idx ON saly.creative_runs USING btree (deadline_at, id) WHERE (state = ANY (ARRAY['EN_COLA'::text, 'EJECUTANDO'::text]));
CREATE INDEX identity_versions_lookup_idx ON saly.identity_versions USING btree (element_id, channel_code, audience_code, valid_from DESC) WHERE (approval_status = 'APPROVED'::text);
