#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]));from skill_root_audit import static
if __name__=='__main__':
 import argparse;p=argparse.ArgumentParser();p.add_argument('--report-dir',type=Path,required=True);a=p.parse_args();raise SystemExit(static(a.report_dir))
