"""Objects the recommended config (relaxed pool, pad 1.0, auto + top-3 frames, max-conf) changes vs the auto photo."""
import sys, os, io, contextlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
with contextlib.redirect_stdout(io.StringIO()):
    import mv_eval as E
for key in [("relaxed", 1.0, 3, "max-conf", True), ("relaxed", 1.0, 3, "mean-prob", True)]:
    pr = E.results[key]; print("\n", key)
    for i, r in enumerate(E.rows):
        if pr[i] != E.base[3][i] and E.truth[i] != "unclear":
            print(f"  {'FIX' if pr[i]==E.truth[i] else 'BRK' if E.base[3][i]==E.truth[i] else 'chg'} {r['object_id'][:8]} {r['true_object']!r:40} auto={E.base[3][i]:12} -> {pr[i]}")
