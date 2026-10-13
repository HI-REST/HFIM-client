#!/usr/bin/env bash
# Run a fault injection campaign on the FIM server
#
# Usage:
#   ./run.sh benchmarks/mmult                           # upload + build + golden + 20 injections
#   ./run.sh benchmarks/mmult -n 100                    # 100 injections
#   ./run.sh benchmarks/mmult --fault memory            # memory faults
#   ./run.sh benchmarks/mmult --workers 4               # 4 parallel QEMU instances
#   ./run.sh benchmarks/mmult --arch aarch64             # build for aarch64
#   ./run.sh benchmarks/mmult --follow                  # stream live + download
#
# By default a campaign is submitted to the server's always-on gateway + worker
# fleet and this command returns immediately -- the campaign keeps running after
# you close the terminal. Check it with ./status.sh (or ./status.sh --watch) and
# fetch finished results with ./download.sh <id> (or ./download.sh --latest).
# Use --follow to stream live output and download when it finishes.
#
set -euo pipefail

# RETIRED (hfim-core phase R-4). HFIM-client no longer submits campaigns;
# hfim does, from the campaign repository, with `hfim run --on <server>`.
# This script prints the command that replaces it and exits 2. The code
# below is kept for reference until the repository is archived.
_retired() {
    local with="hfim run --on <server> campaigns/<campaign>.yaml"
    case " $* " in
        *" --batch "*) with="hfim run --on <server> <batch>.yaml" ;;
    esac
    {
        echo "run.sh is retired. Run this in your campaign repository instead:"
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

# Parse config
read_config() {
    python3 -c "import yaml; print(yaml.safe_load(open('$SCRIPT_DIR/config.yaml'))['$1'])" 2>/dev/null \
        || grep "^$1:" "$SCRIPT_DIR/config.yaml" | awk '{print $2}'
}

USER=$(read_config user)
SERVER=$(read_config server)
SSH_KEY=$(read_config ssh_key)
SSH_KEY="${SSH_KEY/#\~/$HOME}"

if [ -z "$USER" ] || [ -z "$SERVER" ]; then
    echo "Error: fill in config.yaml first"
    exit 1
fi

REMOTE="fim-${USER}@${SERVER}"
SSH_OPTS="-o StrictHostKeyChecking=no"
[ -f "$SSH_KEY" ] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

# Sync Telegram config to server if configured
TELEGRAM_TOKEN=$(read_config telegram_bot_token 2>/dev/null || true)
TELEGRAM_CHAT=$(read_config telegram_chat_id 2>/dev/null || true)
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT" ]; then
    ssh $SSH_OPTS "$REMOTE" "cat > .fim_notify.conf <<EOF
telegram_bot_token=$TELEGRAM_TOKEN
telegram_chat_id=$TELEGRAM_CHAT
EOF" 2>/dev/null
fi

# Check for --batch mode
BATCH_FILE=""
BATCH_BG=""
PREV_WAS_BATCH=false
for arg in "$@"; do
    if [ "$PREV_WAS_BATCH" = true ]; then BATCH_FILE="$arg"; PREV_WAS_BATCH=false; continue; fi
    if [ "$arg" = "--batch" ]; then PREV_WAS_BATCH=true; continue; fi
    if [ "$arg" = "--background" ]; then BATCH_BG="--background"; fi
done

if [ -n "$BATCH_FILE" ]; then
    # Batch mode: upload all benchmarks referenced in YAML, then run batch
    if [ ! -f "$BATCH_FILE" ]; then
        echo "Error: batch file not found: $BATCH_FILE"
        exit 1
    fi

    echo "Batch campaign: $BATCH_FILE"
    echo ""

    # Extract benchmark names from YAML and upload each
    BENCHMARKS=$(python3 -c "
import yaml
with open('$BATCH_FILE') as f:
    b = yaml.safe_load(f)
seen = set()
for c in b.get('campaigns', []):
    name = c.get('benchmark', b.get('defaults', {}).get('benchmark', ''))
    if name and name not in seen:
        print(name)
        seen.add(name)
" 2>/dev/null)

    for bench in $BENCHMARKS; do
        BENCH_DIR="$SCRIPT_DIR/benchmarks/$bench"
        if [ -d "$BENCH_DIR" ]; then
            echo "Uploading ${bench}..."
            # Source only -- see the non-batch upload note below for why build/
            # and .build_hash_* are excluded (server rebuilds + owns the golden).
            rsync -a --exclude 'build/' --exclude '.build_hash_*' \
                -e "ssh $SSH_OPTS" "$BENCH_DIR" "${REMOTE}:/srv/fim/users/${USER}/benchmarks/"
        else
            echo "Warning: benchmark ${bench} not found locally, skipping upload"
        fi
    done

    # Upload the batch YAML
    BATCH_NAME=$(basename "$BATCH_FILE")
    scp $SSH_OPTS "$BATCH_FILE" "${REMOTE}:/srv/fim/users/${USER}/${BATCH_NAME}"
    echo ""

    # Run batch on server
    ssh $SSH_OPTS "$REMOTE" "fim-run batch ${BATCH_NAME} $BATCH_BG" 2>&1 | \
        sed -e 's|/srv/fim/users/[^/]*/||g' -e 's|/home/[^/]*/[^ ]*/||g' -e 's|\x1b\[[0-9;]*m||g'

    if [ -n "$BATCH_BG" ]; then
        echo ""
        echo "Check status:     ./status.sh   (or ./status.sh --watch)"
        echo "Download results: ./download.sh <id>   (./download.sh --latest)"
    else
        # Download all results
        REMOTE_RESULTS="/srv/fim/users/${USER}/results"
        LOCAL_RESULTS="$SCRIPT_DIR/results"
        mkdir -p "$LOCAL_RESULTS"
        echo ""
        echo "Downloading results..."
        # Only pull result dirs for benchmarks named in THIS batch. The results
        # dir is shared box-wide; globbing '*/' also matches other users' runs,
        # whose mode-700 dirs we cannot rm (the loop then aborts mid-download and
        # our own results never land). Scope to our benchmarks and only rm what
        # we actually downloaded.
        for bench in $BENCHMARKS; do
            for dir in $(ssh $SSH_OPTS "$REMOTE" "ls -d ${REMOTE_RESULTS}/${bench}_*/ 2>/dev/null" | xargs -n1 basename 2>/dev/null); do
                if scp $SSH_OPTS -r "${REMOTE}:${REMOTE_RESULTS}/${dir}" "$LOCAL_RESULTS/"; then
                    ssh $SSH_OPTS "$REMOTE" "rm -rf ${REMOTE_RESULTS}/${dir}" 2>/dev/null || true
                    echo "  $dir"
                else
                    echo "  (skipped, download failed) $dir"
                fi
            done
        done
        echo "Done."
    fi
    exit 0
fi

# Parse arguments - extract benchmark dir, pass the rest through
BENCHMARK_DIR=""
PASS_ARGS=()

for arg in "$@"; do
    if [ -z "$BENCHMARK_DIR" ] && [ -d "$arg" ]; then
        BENCHMARK_DIR="$arg"
    elif [ -z "$BENCHMARK_DIR" ] && [ -d "$SCRIPT_DIR/$arg" ]; then
        BENCHMARK_DIR="$SCRIPT_DIR/$arg"
    else
        PASS_ARGS+=("$arg")
    fi
done

if [ -z "$BENCHMARK_DIR" ]; then
    echo "Usage: $0 <benchmark_dir> [options]"
    echo "       $0 --batch <campaign.yaml> [--background]"
    echo ""
    echo "Options:"
    echo "  -n, --injections N    Number of fault injections (default: 20)"
    echo "  --fault TYPE          register or memory (default: register)"
    echo "  --workers N           Parallel QEMU instances (default: 1)"
    echo "  --arch ARCH           riscv64 or aarch64 (default: riscv64)"
    echo "  --seed N              PRNG seed (default: 42)"
    echo "  --follow              Stream live output + auto-download when done"
    echo "  --background          Accepted alias for the default (submit + return)"
    echo "  --batch FILE          Run multiple campaigns from YAML config"
    echo ""
    echo "Available benchmarks:"
    for d in "$SCRIPT_DIR"/benchmarks/*/; do
        [ -f "$d/main.c" ] || [ -f "$d/Cargo.toml" ] && echo "  benchmarks/$(basename "$d")"
    done
    exit 1
fi

NAME="$(basename "$BENCHMARK_DIR")"

# ── Upload benchmark to server ────────────────────────────────────
# Ship source only -- the server rebuilds and owns its own build/ + golden.
# build/ holds a locally-compiled .elf + .build_hash; uploading it would
# overwrite the server's binary with whatever stale artifact sits on this
# laptop. The server's golden is keyed off a source hash, not the ELF, so a
# stale local ELF would silently run without retriggering the golden. rsync
# --exclude keeps build/ on the laptop; scp -r had no way to exclude it.
echo "Uploading ${NAME}..."
upload_benchmark() {  # $1 = local benchmark dir
    rsync -a --exclude 'build/' --exclude '.build_hash_*' \
        -e "ssh $SSH_OPTS" "$1" "${REMOTE}:/srv/fim/users/${USER}/benchmarks/"
}
upload_benchmark "$BENCHMARK_DIR"
echo ""

# ── Run on server (build + golden + submit campaign) ──────────────
# The server owns the campaign lifecycle: fim-run builds + runs golden, then
# submits to the student's always-on gateway + worker fleet, which runs the
# campaign to completion regardless of this SSH session. By default fim-run
# submits and returns (fire-and-forget); the campaign keeps running after this
# command exits. Pass --follow to stream live output instead.
# Capture the run output so we can tell whether the campaign ran inline to
# completion (serial_pty benchmarks like robot_arm force inline execution and
# finish before this returns) vs was submitted fire-and-forget to the fleet.
RUN_OUT=$(mktemp)
ssh $SSH_OPTS "$REMOTE" "FIM_FORCE_INLINE_PTY=${FIM_FORCE_INLINE_PTY:-0} fim-run run ${NAME} ${PASS_ARGS[*]:-}" 2>&1 | \
    sed -e 's|/srv/fim/users/[^/]*/||g' -e 's|/home/[^/]*/[^ ]*/||g' -e 's|\x1b\[[0-9;]*m||g' \
    | tee "$RUN_OUT"

# Only --follow waits for completion locally; in that case the result tree is
# ready and we download it now. Otherwise (the default) the campaign is still
# running server-side: do not download, just tell the student how to retrieve.
FOLLOWED=false
for arg in "${PASS_ARGS[@]}"; do
    [ "$arg" = "--follow" ] && FOLLOWED=true
done

# Inline-completion detection: fim-run prints "Campaign complete: <id>" to stdout
# only when the campaign ran to completion in this session (serial_pty / inline
# path). Such a run never registers with the gateway ledger, so ./status.sh and
# ./download.sh --latest (which read `fim-run jobs`) can't see it -- the student
# is left with an empty results/ dir. When we detect this marker, download that
# exact id now, the same way --follow does, regardless of the --follow flag.
INLINE_CID=$(grep -oE 'Campaign complete: [A-Za-z0-9_]+' "$RUN_OUT" | tail -1 | awk '{print $3}')
rm -f "$RUN_OUT"

if [ "$FOLLOWED" != true ] && [ -z "$INLINE_CID" ]; then
    echo ""
    echo "Campaign is running on the server fleet (keeps running after this exits)."
    echo "  Check progress:   ./status.sh   (or ./status.sh --watch)"
    echo "  Download results: ./download.sh --latest   (or ./download.sh <id>)"
    exit 0
fi

# ── --follow: campaign finished, pull its result tree ─────────────
REMOTE_RESULTS="/srv/fim/users/${USER}/results"
LOCAL_RESULTS="$SCRIPT_DIR/results"
mkdir -p "$LOCAL_RESULTS"

echo ""
echo "Downloading results..."
# Prefer the exact id parsed from the run output (inline completion); only fall
# back to the newest-dir heuristic for --follow fleet runs that don't print one.
# The heuristic is a guess on the box-wide shared results dir, so the exact id is
# always safer when we have it.
if [ -n "$INLINE_CID" ]; then
    LATEST="${REMOTE_RESULTS}/${INLINE_CID}"
else
    LATEST=$(ssh $SSH_OPTS "$REMOTE" "ls -1d ${REMOTE_RESULTS}/${NAME}_* 2>/dev/null | sort | tail -1")
fi
if [ -n "$LATEST" ]; then
    RESULT_NAME=$(basename "$LATEST")
    scp $SSH_OPTS -r "${REMOTE}:${LATEST}" "$LOCAL_RESULTS/"
    echo "  Saved to: results/${RESULT_NAME}/"

    ssh $SSH_OPTS "$REMOTE" "rm -rf ${LATEST}"
    echo "  Cleaned server copy"

    REMOTE_LOGS="/srv/fim/users/${USER}/logs"
    mkdir -p "$LOCAL_RESULTS/${RESULT_NAME}"
    scp $SSH_OPTS "${REMOTE}:${REMOTE_LOGS}/fim.log" "$LOCAL_RESULTS/${RESULT_NAME}/server.log" 2>/dev/null && \
        echo "  Server log saved to: results/${RESULT_NAME}/server.log"

    PROV_FILE="$LOCAL_RESULTS/${RESULT_NAME}/provenance.json"
    if [ -f "$PROV_FILE" ] && git -C "$SCRIPT_DIR" rev-parse HEAD &>/dev/null; then
        GIT_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
        GIT_DIRTY=$(git -C "$SCRIPT_DIR" diff --quiet 2>/dev/null && echo "false" || echo "true")
        GIT_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
        python3 -c "
import json
with open('$PROV_FILE') as f: p = json.load(f)
p['git_commit'] = '$GIT_COMMIT'
p['git_branch'] = '$GIT_BRANCH'
p['git_dirty'] = $GIT_DIRTY
with open('$PROV_FILE', 'w') as f: json.dump(p, f, indent=4)
" 2>/dev/null
    fi
else
    echo "  No results found to download"
fi

echo ""
echo "Done."
