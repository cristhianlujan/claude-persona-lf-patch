#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from profile_audit import run
if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser(); parser.add_argument('--report-dir',type=Path,required=True); args=parser.parse_args(); raise SystemExit(run('A26','static',args.report_dir))
