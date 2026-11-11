#!/usr/bin/env python3
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from pack_validation_common import main
if __name__=="__main__":
    p=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
    raise SystemExit(main(p,evals="--evals" in sys.argv[2:] or "--evals" in sys.argv[1:]))
