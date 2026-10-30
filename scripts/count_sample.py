"""Reproduce Beck's sample funnel: raw ESM -> complete surveys -> >=40 -> model files."""
import sys, collections, warnings
from pathlib import Path
import pandas as pd, rdata
warnings.filterwarnings("ignore")
repo = Path(sys.argv[1])

# 1. raw ESM
objs = rdata.read_rda(str(repo / "04-data/01-raw-data/esm_cleaned_combined_2021-04-07.RData"), default_encoding="utf8")
emo = objs["emo"]
emo["ts"] = emo["Date"].astype(str) + " " + emo["Hour"].astype(str) + ":" + emo["Minute"].astype(str)
per = emo.groupby("SID")["ts"].nunique()
print(f"Raw ESM: {per.size} participants, {per.sum()} surveys "
      f"(per person median {per.median():.0f}, range {per.min()}-{per.max()})")
print(f"  with >=40 surveys (before complete-case filter): {(per >= 40).sum()}  "
      f"surveys among them: {per[per >= 40].sum()}")
print("Affect items:", sorted(emo["trait"].dropna().unique()))
sit = objs["sit"]; print("Situation items:", sorted(sit["trait"].dropna().unique()))
print("DIAMONDS:", sorted(objs["ds8"]["trait"].dropna().unique()))
print("BFI traits/facets:", objs["bfi"].groupby("trait")["facet"].nunique().to_dict())

# 2. model files written by save_fun: SID_outcome_group_set_time.RData
files = [f.stem.split("_") for f in (repo / "04-data/02-model-data").glob("*.RData")]
df = pd.DataFrame(files, columns=["SID", "outcome", "group", "set", "time"])
print(f"\nModel files: {len(df)}; unique participants: {df.SID.nunique()}")
print("participants per outcome:", df.groupby("outcome").SID.nunique().to_dict())
print("feature sets:", df.groupby(["group", "set", "time"]).size().to_dict())

# 3. rows/columns of one example per outcome
for oc, g in df.groupby("outcome"):
    r = g[(g.group == "full") & (g.time == "time")].iloc[0] if ((g.group == "full") & (g.time == "time")).any() else g.iloc[0]
    d = rdata.read_rda(str(repo / f"04-data/02-model-data/{'_'.join(r)}.RData"), default_encoding="utf8")["d"]
    print(f"  {oc}: example {r.SID} ({r.group}/{r.set}/{r.time}) -> {d.shape[0]} rows x {d.shape[1]} cols")

# 4. total assessments among final participants (full set, time, any outcome)
tot = {}
for sid in df.SID.unique():
    g = df[(df.SID == sid) & (df.group == "full") & (df.time == "no time")]
    r = (g if len(g) else df[df.SID == sid]).iloc[0]
    d = rdata.read_rda(str(repo / f"04-data/02-model-data/{'_'.join(r)}.RData"), default_encoding="utf8")["d"]
    tot[sid] = d.shape[0]
s = pd.Series(tot)
print(f"\nFinal sample: N={s.size}, model rows total={s.sum()}, mean {s.mean():.1f} (SD {s.std():.1f}, {s.min()}-{s.max()})")
