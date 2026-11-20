"""Run P2 positive/negative Step60 schema dispatch tests in the existing R17 carrier."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"profile_execution_runtime"))
from test_lf_p2_product_direction_output_modes_v1 import ProductDirectorOutputModes
