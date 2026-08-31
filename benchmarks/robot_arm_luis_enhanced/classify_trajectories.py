#!/usr/bin/env python3
"""Post-mortem trajectory classifier for robot_arm campaigns.

This is the analysis Sergio described in HFIM-client issue #1: the campaign
stores the coordinates the arm passed through, one file per fault, and a
posteriori we decide whether the run was wrong - did it reach the final
coordinates, were there significant deviations along the way.

Verdicts (per injection, from its trajectory.csv vs the golden's):
  reached       final pose within tolerance of the golden's, path close
  path_deviated final pose fine, but the path deviated beyond tolerance
  wrong_pose    converged somewhere else (final pose off target)
  not_converged the arm never settled (ran to the tick cap)
  dead          non-finite values (NaN torques/positions)
  no_data       no trajectory recorded (crash before any tick, timeout)

Usage (also wired as a campaign_end hook):
  classify_trajectories.py <campaign_outdir> --golden <golden_dir>
"""
import argparse
import csv
import json
import math
import os
import sys

FINAL_TOL = 0.10      # rad: same threshold the C controller uses to declare
                      # target reached (|pos - target| < 0.1 on every joint)
PATH_TOL = 0.15       # rad: max per-joint deviation from the golden path
                      # before we call it a deviated trajectory
CAP_TICKS = 2000      # the feeder's iteration cap = never converged


def read_traj(path):
    if not os.path.isfile(path):
        return None
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            try:
                rows.append([float(r[f"pos{i}"]) for i in range(4)])
            except (KeyError, ValueError):
                return None
    return rows or None


def classify(traj, golden):
    if traj is None:
        return "no_data", {}
    flat = [v for row in traj for v in row]
    if any(not math.isfinite(v) for v in flat):
        return "dead", {"ticks": len(traj)}
    if len(traj) >= CAP_TICKS:
        return "not_converged", {"ticks": len(traj)}

    final_err = max(abs(a - b) for a, b in zip(traj[-1], golden[-1]))
    n = min(len(traj), len(golden))
    path_err = max(
        (abs(traj[i][j] - golden[i][j]) for i in range(n) for j in range(4)),
        default=0.0)
    info = {"ticks": len(traj), "final_err_rad": round(final_err, 6),
            "max_path_err_rad": round(path_err, 6)}
    if final_err > FINAL_TOL:
        return "wrong_pose", info
    if path_err > PATH_TOL:
        return "path_deviated", info
    return "reached", info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign_outdir")
    ap.add_argument("--golden", required=True)
    args = ap.parse_args()

    golden = read_traj(os.path.join(args.golden, "trajectory.csv"))
    if golden is None:
        print(f"golden trajectory not found under {args.golden}", file=sys.stderr)
        return 1

    inj_dir = os.path.join(args.campaign_outdir, "injections")
    outcomes = {}
    csv_path = os.path.join(args.campaign_outdir, "injections.csv")
    if os.path.isfile(csv_path):
        with open(csv_path) as f:
            for r in csv.DictReader(f):
                outcomes[int(r["injection_id"])] = r["outcome"]

    rows, counts = [], {}
    for name in sorted(os.listdir(inj_dir)) if os.path.isdir(inj_dir) else []:
        p = os.path.join(inj_dir, name, "trajectory.csv")
        try:
            iid = int(name)
        except ValueError:
            continue
        verdict, info = classify(read_traj(p), golden)
        counts[verdict] = counts.get(verdict, 0) + 1
        rows.append({"injection_id": iid, "verdict": verdict,
                     "campaign_outcome": outcomes.get(iid, ""), **info})

    out_csv = os.path.join(args.campaign_outdir, "trajectory_verdicts.csv")
    fields = ["injection_id", "verdict", "campaign_outcome", "ticks",
              "final_err_rad", "max_path_err_rad"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in sorted(rows, key=lambda x: x["injection_id"]):
            w.writerow({k: r.get(k, "") for k in fields})

    summary = {"campaign": os.path.basename(args.campaign_outdir.rstrip("/")),
               "n": len(rows), "counts": counts,
               "tolerances": {"final_rad": FINAL_TOL, "path_rad": PATH_TOL}}
    with open(os.path.join(args.campaign_outdir, "trajectory_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
