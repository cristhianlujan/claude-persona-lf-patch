#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]));from closure_audit import run
if __name__=='__main__':raise SystemExit(run('A58','runtime',Path('audit-results')))
