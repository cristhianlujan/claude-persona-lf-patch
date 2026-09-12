from __future__ import annotations
import json, unittest
from pathlib import Path
from profile_runtime_api.llama import governed_generation_schema, decode_ui_production_transport
class UIProductionSemanticTransportV5Test(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[3]
        self.schema=json.loads((root/'profiles/ui_architect/schemas/ui_production_spec.schema.json').read_text())
        self.a={'task_mode':'CREATE_NEW','implementation_readiness':'STRUCTURED_SPEC_READY_FOR_NEXT_AGENT','required_component_ids':['header_search','category_navigation','featured_services','service_cards','service_card_template','service_title','service_provider','service_price','service_cta'],'required_state_component_ids':['header_search','category_navigation','featured_services','service_cards','service_cta'],'required_sections':['header','categories','featured_services','service_cards'],'required_design_intents':['clear','professional','easy_to_navigate'],'required_responsive_modes':['desktop','mobile'],'required_service_leaf_components':['service_title','service_provider','service_price','service_cta'],'required_source_bindings':{'category_navigation.items':'DATA_BOUND','featured_services.items':'DATA_BOUND','service_card_template.fields':'title|provider|price|call_to_action','service_card_template.values':'DATA_BOUND','service_cards.items':'DATA_BOUND','service_cta.destination':'UNRESOLVED_UNTIL_SOURCE','service_cta.label':'DATA_BOUND:call_to_action','service_price.format':'SOURCE_DEFINED','service_price.value':'DATA_BOUND:price','service_provider.value':'DATA_BOUND:provider','service_title.value':'DATA_BOUND:title'},'minimum_component_count':9,'minimum_hierarchy_depth_edges':3,'minimum_risk_control_count':4}
    def test_fully_derivable_graph_sends_only_layout_gap_to_model(self):
        schema,policy=governed_generation_schema(self.schema,profile_slug='ui_architect',schema_mode='UI_PRODUCTION_SPEC',acceptance=self.a)
        self.assertEqual(schema['properties']['v']['const'],5); self.assertIn('UICT5',policy)
        self.assertEqual(schema['properties']['d']['required'],['l'])
        self.assertNotIn('c',schema['properties']['d']['properties']); self.assertIn('STANDARD_GRID_STACK',schema['properties']['d']['properties']['l']['enum'])
    def test_v5_materializes_graph_state_hierarchy_priority_deterministically(self):
        payload={'v':5,'d':{'l':'STANDARD_GRID_STACK'}}
        out,kind=decode_ui_production_transport(payload,self.a,domain_scope='GENERIC_SERVICE_MARKETPLACE')
        self.assertEqual(kind,'UICT5'); d=out['deliverable_created']; comps={x['component_id']:x for x in d['component_tree']}
        self.assertEqual(comps['header_search']['component_type'],'input'); self.assertEqual(comps['header_search']['zone_id'],'header')
        self.assertEqual(comps['category_navigation']['component_type'],'navigation'); self.assertEqual(comps['category_navigation']['zone_id'],'categories')
        self.assertEqual(comps['featured_services']['component_type'],'section'); self.assertEqual(comps['service_cards']['component_type'],'collection')
        self.assertEqual(comps['service_cta']['component_type'],'action'); self.assertEqual(comps['service_cta']['zone_id'],'service_cards')
        self.assertEqual(comps['service_cta']['visual_priority'],'HIGH'); self.assertEqual(len(d['visual_hierarchy']),3)
        self.assertIn('header_search',d['state_map']); self.assertNotEqual(d['state_map']['header_search'],d['state_map']['service_cta'])
    def test_unresolved_component_keeps_only_true_semantic_gap(self):
        a=dict(self.a); a['required_component_ids']=['hero','mystery_widget']; a['required_state_component_ids']=['mystery_widget']; a['required_sections']=['hero','body']; a['required_source_bindings']={'mystery_widget.binding':'DATA_BOUND'}; a['minimum_component_count']=2; a['minimum_hierarchy_depth_edges']=1; a['minimum_risk_control_count']=1; a['required_service_leaf_components']=[]
        schema,_=governed_generation_schema(self.schema,profile_slug='ui_architect',schema_mode='UI_PRODUCTION_SPEC',acceptance=a)
        d=schema['properties']['d']; self.assertIn('c',d['properties']); self.assertEqual(d['properties']['c']['required'],['mystery_widget'])
if __name__=='__main__': unittest.main()
