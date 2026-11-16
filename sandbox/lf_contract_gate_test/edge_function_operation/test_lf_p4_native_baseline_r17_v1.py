"""Include P4 typed continuation source-bound tests in existing R17 lane."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"profile_execution_runtime"))
from test_lf_p4_baseline_native_request import P4BaselineIssue
