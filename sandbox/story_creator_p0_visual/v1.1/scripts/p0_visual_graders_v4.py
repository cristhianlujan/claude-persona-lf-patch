#!/usr/bin/env python3
from __future__ import annotations
from typing import Callable
from p0_visual_grader_core_v4 import *
from p0_visual_grader_text_v4 import j_text,j_uncertainty
from p0_visual_grader_object_v4 import j_object,j_style,j_semantic,j_skeptic
from p0_visual_grader_structure_v4 import j_complete,j_geometry,j_structure
RUNNERS:dict[str,Callable[[dict,dict],dict]]={'J-TEXT':j_text,'J-OBJECT':j_object,'J-COMPLETE':j_complete,'J-GEOMETRY':j_geometry,'J-STRUCTURE':j_structure,'J-STYLE':j_style,'J-SEMANTIC':j_semantic,'J-UNCERTAINTY':j_uncertainty,'J-SKEPTIC':j_skeptic}
def run_grader(grader_id:str,candidate:dict,ctx:dict)->dict:
 if grader_id not in RUNNERS:raise ValueError(f'unknown grader {grader_id}')
 local=dict(ctx);local['grader_execution_id']=ctx.get('grader_execution_id') or f"{grader_id}-{ctx['pass_id']}"
 return RUNNERS[grader_id](candidate,local)
def run_all(candidate:dict,ctx:dict)->list[dict]:
 outs=[]
 for idx,g in enumerate(GRADERS,1):
  local=dict(ctx);local['grader_execution_id']=f"{ctx['pass_id']}-{g}-{idx:02d}";outs.append(run_grader(g,candidate,local))
 return outs
