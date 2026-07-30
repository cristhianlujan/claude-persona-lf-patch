#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]));from schema_audit import run
if __name__=='__main__':
 import argparse;p=argparse.ArgumentParser();p.add_argument('--report-dir',type=Path,required=True);a=p.parse_args();raise SystemExit(run('A61','static',a.report_dir))
