"""List objects in .RData files using the `rdata` package."""
import sys, rdata, pandas as pd
for path in sys.argv[1:]:
    print("\n########", path.split("/")[-1])
    try:
        objs = rdata.read_rda(path, default_encoding="utf8")
    except Exception as e:
        print("FAILED:", type(e).__name__, str(e)[:200]); continue
    for k, v in objs.items():
        if isinstance(v, pd.DataFrame):
            print(f"--- {k}: DataFrame {v.shape}"); print("cols:", list(v.columns)[:30])
            for sid in ("SID",):
                if sid in v.columns: print("unique SID:", v[sid].nunique())
        else:
            print(f"--- {k}: {type(v).__name__} len={getattr(v,'__len__',lambda:None)()}")
