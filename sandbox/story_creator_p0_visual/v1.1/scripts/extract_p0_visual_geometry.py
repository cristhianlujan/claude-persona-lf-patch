#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import geometry_profile,build_spatial_relations,_layout_regions,_viewport_size

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--output',required=True);a=p.parse_args();c=json.loads(Path(a.candidate).read_text());vw,vh=_viewport_size(c);by={e['element_id']:e for e in c.get('elements',[])}
 for e in c.get('elements',[]):e['geometry']=geometry_profile(e,by.get(e.get('parent_id')),vw,vh)
 out={'schema_version':'p0-visual-geometry-extraction/v1','elements':[{'element_id':e['element_id'],'geometry':e['geometry']} for e in c.get('elements',[])],'layout_regions':_layout_regions(c.get('elements',[]),vw,vh),'spatial_relations':build_spatial_relations(c.get('elements',[]),{})};Path(a.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');return 0
if __name__=='__main__':raise SystemExit(main())
