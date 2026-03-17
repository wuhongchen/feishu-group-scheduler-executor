#!/usr/bin/env bash
set -euo pipefail

ACTION="status"
TOKEN=""
CHAT_ID=""
ROLE=""
CONFIG_PATH=""

usage() {
  cat <<'EOF'
Usage:
  quick-config.sh [options]

Options:
  --action <status|relay-safe|direct-on|role-scheduler|role-executor|set-chat-id>
  --token <text>               Required when admin_quick_ops.require_token=true
  --chat-id <oc_xxx>           Required when action=set-chat-id
  --role <scheduler|executor>  Optional alias for role actions
  --config <path>              Default: <skill_dir>/config.local.json
  -h, --help                   Show help

Examples:
  bash scripts/quick-config.sh --action status
  bash scripts/quick-config.sh --action relay-safe --token '虾改配置'
  bash scripts/quick-config.sh --action set-chat-id --chat-id 'oc_xxx' --token '虾改配置'
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --chat-id)
      CHAT_ID="${2:-}"
      shift 2
      ;;
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[error] unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${CONFIG_PATH}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  CONFIG_PATH="${SKILL_DIR}/config.local.json"
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[error] config not found: ${CONFIG_PATH}"
  exit 1
fi

if [[ "${ROLE}" == "scheduler" ]]; then
  ACTION="role-scheduler"
elif [[ "${ROLE}" == "executor" ]]; then
  ACTION="role-executor"
fi

if [[ "${ACTION}" == "set-chat-id" && -z "${CHAT_ID}" ]]; then
  echo "[error] --chat-id is required when --action set-chat-id"
  exit 1
fi

python3 - "${CONFIG_PATH}" "${ACTION}" "${TOKEN}" "${CHAT_ID}" <<'PY'
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

config_path = Path(sys.argv[1])
action = sys.argv[2]
token = sys.argv[3]
chat_id = sys.argv[4]

allowed_actions_default = {
    "status",
    "relay-safe",
    "direct-on",
    "role-scheduler",
    "role-executor",
    "set-chat-id",
}

raw = config_path.read_text(encoding="utf-8")
cfg = json.loads(raw)

quick_ops = cfg.get("admin_quick_ops", {})
enabled = bool(quick_ops.get("enabled", False))
require_token = bool(quick_ops.get("require_token", True))
tokens = [str(x) for x in quick_ops.get("tokens", [])]
allowed_actions = set(str(x) for x in quick_ops.get("allowed_actions", []))
if not allowed_actions:
    allowed_actions = set(allowed_actions_default)

if not enabled:
    print("[safe-stop] admin_quick_ops.enabled is false")
    print(f"[hint] please enable first in {config_path}")
    sys.exit(2)

if action not in allowed_actions:
    print(f"[safe-stop] action not allowed: {action}")
    print(f"[hint] allowed_actions={sorted(allowed_actions)}")
    sys.exit(2)

if require_token:
    if not token:
        print("[safe-stop] token required but missing (--token)")
        sys.exit(2)
    if tokens and token not in tokens:
        print("[safe-stop] token mismatch")
        sys.exit(2)

def set_path(root, path, value):
    node = root
    for key in path[:-1]:
        if key not in node or not isinstance(node[key], dict):
            node[key] = {}
        node = node[key]
    node[path[-1]] = value

summary = {
    "config": str(config_path),
    "action": action,
    "changed": [],
}

if action == "status":
    snapshot = {
        "identity.role": cfg.get("identity", {}).get("role"),
        "feishu.chat_id": cfg.get("feishu", {}).get("chat_id"),
        "plugin_constraints.bot_to_bot_dispatch": cfg.get("plugin_constraints", {}).get("bot_to_bot_dispatch"),
        "plugin_constraints.dispatch_mode": cfg.get("plugin_constraints", {}).get("dispatch_mode"),
        "admin_quick_ops.enabled": quick_ops.get("enabled"),
        "admin_quick_ops.require_token": quick_ops.get("require_token"),
        "admin_quick_ops.allowed_actions": sorted(allowed_actions),
    }
    print(json.dumps({"ok": True, "mode": "status", "snapshot": snapshot}, ensure_ascii=False, indent=2))
    sys.exit(0)

backup_path = f"{config_path}.backup.{datetime.now().strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(config_path, backup_path)
summary["backup"] = backup_path

if action == "relay-safe":
    set_path(cfg, ["plugin_constraints", "bot_to_bot_dispatch"], False)
    set_path(cfg, ["plugin_constraints", "dispatch_mode"], "auto")
    summary["changed"] = [
        "plugin_constraints.bot_to_bot_dispatch=false",
        "plugin_constraints.dispatch_mode=auto",
    ]
elif action == "direct-on":
    set_path(cfg, ["plugin_constraints", "bot_to_bot_dispatch"], True)
    set_path(cfg, ["plugin_constraints", "dispatch_mode"], "direct")
    summary["changed"] = [
        "plugin_constraints.bot_to_bot_dispatch=true",
        "plugin_constraints.dispatch_mode=direct",
    ]
elif action == "role-scheduler":
    set_path(cfg, ["identity", "role"], "scheduler")
    summary["changed"] = ["identity.role=scheduler"]
elif action == "role-executor":
    set_path(cfg, ["identity", "role"], "executor")
    summary["changed"] = ["identity.role=executor"]
elif action == "set-chat-id":
    set_path(cfg, ["feishu", "chat_id"], chat_id)
    summary["changed"] = [f"feishu.chat_id={chat_id}"]
else:
    print(f"[error] unsupported action: {action}")
    sys.exit(1)

set_path(
    cfg,
    ["admin_quick_ops", "last_applied"],
    {
        "action": action,
        "at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    },
)

config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
summary["ok"] = True
print(json.dumps(summary, ensure_ascii=False, indent=2))
PY

if [[ "${ACTION}" == "status" ]]; then
  echo "[done] quick config status checked"
else
  echo "[done] quick config action applied"
fi
