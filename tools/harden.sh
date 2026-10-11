#!/usr/bin/env bash
# Local LibreLane hardening via the official tt-support-tools (same flow as the TT gds action).
# Works before the first git commit: commit/remote metadata falls back to placeholders.
# Usage: tools/harden.sh [extra tt_tool args]     e.g. tools/harden.sh --print-stats
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
source tools/.venv/bin/activate
export LOCAL_HARDEN_ARGS="${*:---harden}"
python - <<'PY'
import os, runpy, shlex, sys
sys.path.insert(0, "tt")
import project
def _safe(fn, fallback):
    def wrapper(self):
        try:
            return fn(self)
        except Exception:
            return fallback
    return wrapper
project.Project.get_git_remote = _safe(project.Project.get_git_remote, "local")
project.Project.get_git_commit_hash = _safe(project.Project.get_git_commit_hash, "0" * 40)
def run(argv):
    sys.argv = ["tt/tt_tool.py", *argv]
    try:
        runpy.run_path("tt/tt_tool.py", run_name="__main__")
    except SystemExit as e:
        if e.code not in (None, 0):
            raise
args = shlex.split(os.environ["LOCAL_HARDEN_ARGS"])
if "--harden" in args:
    run(["--create-user-config"])
run(args)
PY
