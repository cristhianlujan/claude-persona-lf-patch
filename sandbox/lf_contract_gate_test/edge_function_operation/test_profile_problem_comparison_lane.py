"""Run Profile Updater problem-by-problem tests in existing LF Edge Operation R17 CI lane.

No new workflow, no runtime or operational side effects.
"""
from pathlib import Path
import runpy

TEST_FILE = (Path(__file__).resolve().parents[1]
             / "profile_execution_runtime/test_profile_problem_comparison.py")
ProblemComparisonTest = runpy.run_path(str(TEST_FILE))["ProblemComparisonTest"]
