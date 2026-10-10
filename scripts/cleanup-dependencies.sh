#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

require_root
require_cmds rpm-ostree python3

ADDED="$HONOR_STATE_DIR/deps-added.txt"
TEMP="$HONOR_STATE_DIR/temporary-deps.txt"

[[ -r "$ADDED" && -r "$TEMP" ]] || {
    log "no dependency ownership record; skipping automatic cleanup"
    exit 0
}

mapfile -t requested < <(python3 - <<'PY'
import json, subprocess
j=json.loads(subprocess.check_output(["rpm-ostree","status","--json"], text=True))
booted=next((d for d in j.get("deployments",[]) if d.get("booted")), {})
for p in booted.get("requested-packages", []) or []:
    print(p)
PY
)

mapfile -t added < "$ADDED"
mapfile -t temporary < "$TEMP"

REMOVE=()
for pkg in "${added[@]}"; do
    [[ -n "$pkg" ]] || continue
    printf '%s\n' "${temporary[@]}" | grep -qxF "$pkg" || continue
    printf '%s\n' "${requested[@]}" | grep -qxF "$pkg" || continue
    REMOVE+=("$pkg")
done

if ((${#REMOVE[@]} == 0)); then
    log "no temporary packages owned by this setup need removal"
    exit 0
fi

log "removing temporary layered build dependencies: ${REMOVE[*]}"
rpm-ostree uninstall "${REMOVE[@]}"
printf '%s\n' "${REMOVE[@]}" > "$HONOR_STATE_DIR/deps-cleaned.txt"
