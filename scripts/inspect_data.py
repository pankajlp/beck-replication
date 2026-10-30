"""Inspect Beck & Jackson (2022) raw data: objects, columns, N, assessments."""
import sys
from pathlib import Path

import pandas as pd
import pyreadr

raw = Path(sys.argv[1])  # path to 04-data/01-raw-data

for f in sorted(raw.iterdir()):
    print(f"\n######## {f.name}")
    if f.suffix == ".csv":
        objs = {"csv": pd.read_csv(f, low_memory=False)}
    elif f.suffix == ".RData":
        objs = pyreadr.read_r(str(f))
    else:
        continue
    for name, df in objs.items():
        print(f"--- object '{name}': {df.shape[0]} rows x {df.shape[1]} cols")
        print("columns:", list(df.columns)[:40], "..." if df.shape[1] > 40 else "")
        sid = next((c for c in df.columns if c.lower() in ("sid", "id", "pid")), None)
        if sid:
            print(f"unique {sid}: {df[sid].nunique()}")
            if "Full_Date" in df.columns or "beep" in df.columns:
                tcol = "Full_Date" if "Full_Date" in df.columns else "beep"
                n_obs = df.groupby(sid)[tcol].nunique()
                print(f"assessments ({tcol}) total={n_obs.sum()} per-person "
                      f"median={n_obs.median()} min={n_obs.min()} max={n_obs.max()} "
                      f">=40: {(n_obs >= 40).sum()}")
        for c in ("category", "item", "trait", "wave"):
            if c in df.columns:
                vc = df[c].value_counts()
                print(f"{c} ({len(vc)} levels):", dict(vc.head(25)))
        print(df.head(3).to_string()[:1500])
