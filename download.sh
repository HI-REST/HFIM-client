#!/usr/bin/env bash
# Download one campaign's results from the FIM server.
#
# Usage:
#   ./download.sh <id-or-prefix>     # download the named campaign (summary only)
#   ./download.sh --latest           # download the most recent completed campaign
#   ./download.sh <id> --full        # also pull the per-injection injections/ tree
#   ./download.sh <id> --purge       # delete the server copy after download
#   ./download.sh <id> --with-golden # also pull the campaign's golden reference
#
# Golden references (the no-fault baseline each campaign is compared against):
#   ./download.sh --list-golden      # list golden dirs on the server
#   ./download.sh --golden <name>    # download one golden dir (see --list-golden)
#   ./download.sh --golden-all       # download every golden dir
#
# Selection:
#   <id-or-prefix> matches a campaign id, or a unique prefix of one. An ambiguous
#   prefix (matching >1 campaign) is rejected so you never download the wrong run.
#
# Verbosity (default = summary):
#   summary  report.tsv, injections.csv, metadata.json, provenance.json,
#            faultlist.json, and the source/ dir -- enough to read the outcome.
#   --full   everything, including injections/<i>/ (UART/register dumps, logs).
#
# Server copy is KEPT by default so you can re-download. Pass --purge to remove
# it on the server after a successful fetch. Golden dirs land in ./golden/.
#
set -euo pipefail

# RETIRED (hfim-core phase R-4): `hfim runs fetch` replaces this script. It
# prints the command that replaces it and exits 2.
_retired() {
    local with="hfim runs fetch <id>   (or hfim runs fetch --latest)"
    case " $* " in
        *" --purge "*) with="hfim runs fetch <id>, then hfim runs clean <id>" ;;
        *" --list-golden "*) with="hfim golden list --on <server>" ;;
        *" --golden "*|*" --golden-all "*|*" --with-golden "*)
            with="none: a Golden belongs to the simulator that measured it and is not copied (hfim golden list --on <server> lists them)" ;;
        *" --latest "*) with="hfim runs fetch --latest" ;;
    esac
    {
        echo "download.sh is retired. Run this in your campaign repository instead:"
        echo "  $with"
        echo ""
        echo "Every HFIM-client command and its replacement:"
        echo "  ./run.sh benchmarks/<b> [flags]  ->  hfim run --on <server> campaigns/<campaign>.yaml"
        echo "  ./run.sh --batch <file>          ->  hfim run --on <server> <batch>.yaml"
        echo "  ./run.sh ... --follow            ->  hfim run --on <server> ... (follows by default; --detach returns)"
        echo "  ./status.sh [--watch|--tail N]   ->  hfim runs, hfim runs show <id>, hfim runs attach <id>"
        echo "  ./download.sh <id>|--latest      ->  hfim runs fetch <id> | hfim runs fetch --latest"
        echo "  ./download.sh <id> --purge       ->  hfim runs clean <id>   (after the fetch)"
        echo "  ./download.sh --list-golden      ->  hfim golden list --on <server>"
        echo "  ./download.sh --golden ...       ->  none: a Golden stays with the simulator that measured it"
        echo "  ./build.sh benchmarks/<b>        ->  hfim build benchmarks/<b>   (or --on <server>)"
        echo "  config.yaml user/server/ssh_key  ->  hfim remote add <server> ... (once, in ~/.hfim/servers.yaml)"
        echo "  config.yaml telegram             ->  hfim remote notify <server> --telegram --chat-id <chat id>"
        echo ""
        echo "Flags that built a campaign on the server (-n, --fault, --seed, --arch, --label) have no"
        echo "replacement on purpose: write them into the campaign file."
        echo "Install hfim and set up a Server: https://github.com/HI-REST/hfim-docs (guides/run-on-a-server.md)."
        echo "Your old results stay readable on the server; this repository is no longer maintained."
    } >&2
    exit 2
}
_retired "$@"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

read_config() {
    python3 -c "import yaml; print(yaml.safe_load(open('$SCRIPT_DIR/config.yaml'))['$1'])" 2>/dev/null \
        || grep "^$1:" "$SCRIPT_DIR/config.yaml" | awk '{print $2}'
}

USER=$(read_config user)
SERVER=$(read_config server)
SSH_KEY=$(read_config ssh_key)
SSH_KEY="${SSH_KEY/#\~/$HOME}"

REMOTE="fim-${USER}@${SERVER}"
SSH_OPTS="-o StrictHostKeyChecking=no"
[ -f "$SSH_KEY" ] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

REMOTE_RESULTS="/srv/fim/users/${USER}/results"
REMOTE_GOLDEN="/srv/fim/users/${USER}/golden"
LOCAL_RESULTS="$SCRIPT_DIR/results"
LOCAL_GOLDEN="$SCRIPT_DIR/golden"

# Derive the golden dir name from a campaign id.
# Campaign ids look like:  <bench>_<arch>_<timestamp>           (qemu)
#                     or:  <bench>_<arch>_<timestamp>_gem5      (gem5)
# Golden dir names are:    <bench>_<arch>_qemu   or   <bench>_<arch>_gem5
golden_for() {
    local result="$1"
    local sim="qemu"
    if [[ "$result" == *_gem5 ]]; then sim="gem5"; fi
    local trimmed="${result%_gem5}"
    trimmed=$(echo "$trimmed" | sed -E 's/_[0-9]{8}_[0-9]{6}_[0-9]+$//')
    echo "${trimmed}_${sim}"
}

# ── Parse args ───────────────────────────────────────────────────
SELECTOR=""
LATEST=false
FULL=false
PURGE=false
WITH_GOLDEN=false
for arg in "$@"; do
    case "$arg" in
        --latest)       LATEST=true ;;
        --full)         FULL=true ;;
        --purge)        PURGE=true ;;
        --with-golden)  WITH_GOLDEN=true ;;
        --list-golden)
            echo "Available golden dirs for ${USER}:"
            ssh $SSH_OPTS "$REMOTE" "ls ${REMOTE_GOLDEN}/ 2>/dev/null" || echo "  (none)"
            exit 0 ;;
        --golden)
            shift || true
            [ $# -ge 1 ] || { echo "--golden requires a name (see --list-golden)" >&2; exit 1; }
            mkdir -p "$LOCAL_GOLDEN"
            echo "Downloading golden/$1..."
            scp $SSH_OPTS -r "${REMOTE}:${REMOTE_GOLDEN}/$1" "$LOCAL_GOLDEN/"
            echo "  Saved to: golden/$1/"
            exit 0 ;;
        --golden-all)
            mkdir -p "$LOCAL_GOLDEN"
            echo "Downloading every golden dir..."
            scp $SSH_OPTS -r "${REMOTE}:${REMOTE_GOLDEN}/." "$LOCAL_GOLDEN/"
            echo "  Saved to: golden/"
            exit 0 ;;
        -h|--help)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --*)
            echo "Unknown option: $arg" >&2; exit 1 ;;
        *)
            if [ -z "$SELECTOR" ]; then SELECTOR="$arg"; else
                echo "Only one campaign id/prefix may be given (got '$SELECTOR' and '$arg')" >&2
                exit 1
            fi ;;
    esac
done

if [ "$LATEST" = false ] && [ -z "$SELECTOR" ]; then
    echo "Usage: $0 <id-or-prefix> | --latest  [--full] [--purge] [--with-golden]" >&2
    echo "       $0 --list-golden | --golden <name> | --golden-all" >&2
    echo "Run ./status.sh to see campaign ids." >&2
    exit 1
fi

# ── Resolve selector -> a single campaign id, server-side ─────────
# Ask the gateway for the campaign list (the same source ./status.sh shows) and
# resolve the prefix / --latest there, so this stays a thin client.
RESOLVE_PY=$(cat <<'PY'
import json, sys
sel = sys.argv[1]
latest = sys.argv[2] == "true"
rows = json.load(sys.stdin).get("campaigns", [])
def cid(r): return r.get("id", r.get("campaign_id", ""))
def st(r):  return (r.get("status") or "").strip()
if latest:
    done = [r for r in rows if st(r) == "done"]
    if not done:
        sys.stderr.write("No completed campaign to download.\n"); sys.exit(2)
    # rows come newest-first from the gateway; take the first done one.
    print(cid(done[0])); sys.exit(0)
matches = [cid(r) for r in rows if cid(r) == sel] or \
          [cid(r) for r in rows if cid(r).startswith(sel)]
if not matches:
    sys.stderr.write(f"No campaign matches '{sel}'. Run ./status.sh to list ids.\n"); sys.exit(2)
if len(matches) > 1:
    sys.stderr.write(f"'{sel}' is ambiguous -- matches {len(matches)} campaigns:\n")
    for m in matches: sys.stderr.write(f"  {m}\n")
    sys.exit(2)
print(matches[0])
PY
)

CID=$(ssh $SSH_OPTS "$REMOTE" "fim-run jobs --json" \
    | python3 -c "$RESOLVE_PY" "${SELECTOR:-}" "$LATEST") || CID=""

# Filesystem fallback. serial_pty benchmarks (robot_arm) run inline and never
# register with the gateway ledger, so `fim-run jobs` can't resolve them -- the
# results still exist under results/. When the ledger lookup fails, resolve the
# id/prefix (or --latest) against the result dirs directly. --latest here means
# "most recently modified result dir for this user".
if [ -z "$CID" ]; then
    if [ "$LATEST" = true ]; then
        CID=$(ssh $SSH_OPTS "$REMOTE" "ls -1dt ${REMOTE_RESULTS}/*/ 2>/dev/null | head -1 | xargs -r basename")
    else
        MATCHES=$(ssh $SSH_OPTS "$REMOTE" "ls -1d ${REMOTE_RESULTS}/${SELECTOR}* 2>/dev/null | xargs -rn1 basename")
        N=$(printf '%s\n' "$MATCHES" | grep -c . || true)
        if [ "$N" -gt 1 ]; then
            echo "'${SELECTOR}' is ambiguous -- matches ${N} result dirs:" >&2
            printf '  %s\n' $MATCHES >&2
            exit 2
        fi
        CID="$MATCHES"
    fi
fi

[ -n "$CID" ] || { echo "Could not resolve a campaign id. Run ./status.sh to list ids." >&2; exit 1; }
echo "Campaign: $CID"

REMOTE_DIR="${REMOTE_RESULTS}/${CID}"
if ! ssh $SSH_OPTS "$REMOTE" "test -d '${REMOTE_DIR}'"; then
    echo "No result tree on server at results/${CID} (campaign may still be running)." >&2
    exit 1
fi

DEST="$LOCAL_RESULTS/$CID"
mkdir -p "$DEST"

# ── Fetch ────────────────────────────────────────────────────────
if [ "$FULL" = true ]; then
    echo "Downloading FULL result tree (per-injection included)..."
    scp $SSH_OPTS -r "${REMOTE}:${REMOTE_DIR}/." "$DEST/"
else
    echo "Downloading summary (use --full for per-injection data)..."
    # Top-level summary files. injections.csv is the per-injection roll-up; the
    # injections/ subdir (one dir per injection) is only pulled with --full.
    for f in report.tsv injections.csv metadata.json provenance.json faultlist.json results.txt; do
        scp $SSH_OPTS "${REMOTE}:${REMOTE_DIR}/${f}" "$DEST/" 2>/dev/null || true
    done
    # source/ (the benchmark as run) is small and high-value for provenance.
    ssh $SSH_OPTS "$REMOTE" "test -d '${REMOTE_DIR}/source'" \
        && scp $SSH_OPTS -r "${REMOTE}:${REMOTE_DIR}/source" "$DEST/" 2>/dev/null || true
fi
echo "  Saved to: results/${CID}/"

# ── Optional paired golden ───────────────────────────────────────
if [ "$WITH_GOLDEN" = true ]; then
    # First-choice golden name carries the sim suffix (_qemu/_gem5). Older
    # benchmarks pre-date that convention, so fall back to the unsuffixed name.
    GOLDEN=$(golden_for "$CID")
    LEGACY="${GOLDEN%_qemu}"; LEGACY="${LEGACY%_gem5}"
    mkdir -p "$LOCAL_GOLDEN"
    echo "Downloading paired golden..."
    if scp $SSH_OPTS -r "${REMOTE}:${REMOTE_GOLDEN}/$GOLDEN" "$LOCAL_GOLDEN/" 2>/dev/null; then
        echo "  Saved to: golden/$GOLDEN/"
    elif [ "$LEGACY" != "$GOLDEN" ] && scp $SSH_OPTS -r "${REMOTE}:${REMOTE_GOLDEN}/$LEGACY" "$LOCAL_GOLDEN/" 2>/dev/null; then
        echo "  Saved to: golden/$LEGACY/  (legacy unsuffixed naming)"
    else
        echo "  Warning: golden dir not found on server (tried $GOLDEN, $LEGACY)."
        echo "           Use ./download.sh --list-golden to see what's available."
    fi
fi

# ── Optional purge ───────────────────────────────────────────────
if [ "$PURGE" = true ]; then
    ssh $SSH_OPTS "$REMOTE" "rm -rf '${REMOTE_DIR}'"
    echo "  Removed server copy."
fi

echo "Done."
