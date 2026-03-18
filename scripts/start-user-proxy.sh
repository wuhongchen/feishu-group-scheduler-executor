#!/usr/bin/env bash
set -euo pipefail

CHAT_ID=""
CONFIG_PATH=""
RELAY_NAME="值班同学"
RELAY_USER_ID=""

usage() {
  cat <<'EOF'
Usage:
  start-user-proxy.sh --chat-id <oc_xxx> [options]

Options:
  --chat-id <oc_xxx>         Target Feishu group chat id (required)
  --config <path>            Config path (default: ../config.local.json)
  --relay-name <name>        Relay operator name (default: 值班同学)
  --relay-user-id <ou_xxx>   Relay operator open_id
  -h, --help                 Show help

Example:
  bash scripts/start-user-proxy.sh --chat-id oc_31ba30dd8c8fdd422929c246432fb2ca
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chat-id)
      CHAT_ID="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --relay-name)
      RELAY_NAME="${2:-}"
      shift 2
      ;;
    --relay-user-id)
      RELAY_USER_ID="${2:-}"
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

if [[ -z "${CHAT_ID}" ]]; then
  echo "[error] --chat-id is required"
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${CONFIG_PATH}" ]]; then
  CONFIG_PATH="${SKILL_DIR}/config.local.json"
fi

TEMPLATE_PATH="${SKILL_DIR}/templates/skill-config.template.json"
if [[ ! -f "${CONFIG_PATH}" ]]; then
  if [[ ! -f "${TEMPLATE_PATH}" ]]; then
    echo "[error] template not found: ${TEMPLATE_PATH}"
    exit 1
  fi
  cp "${TEMPLATE_PATH}" "${CONFIG_PATH}"
  echo "[run] created config from template: ${CONFIG_PATH}"
fi

BACKUP_PATH="${CONFIG_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
cp "${CONFIG_PATH}" "${BACKUP_PATH}"
echo "[run] backup config -> ${BACKUP_PATH}"

python3 - "${CONFIG_PATH}" "${CHAT_ID}" "${RELAY_NAME}" "${RELAY_USER_ID}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
chat_id = sys.argv[2]
relay_name = sys.argv[3]
relay_user_id = sys.argv[4]

cfg = json.loads(config_path.read_text(encoding='utf-8'))

identity = cfg.setdefault('identity', {})
identity['role'] = 'scheduler'

feishu = cfg.setdefault('feishu', {})
feishu['chat_id'] = chat_id
feishu.setdefault('reply_mode', 'thread')

plugin_constraints = cfg.setdefault('plugin_constraints', {})
plugin_constraints['bot_to_bot_dispatch'] = False
plugin_constraints['dispatch_mode'] = 'user_proxy'
plugin_constraints['relay_operator'] = {
    'name': relay_name,
    'user_id': relay_user_id,
}

user_proxy = cfg.setdefault('user_proxy', {})
user_proxy['enabled'] = True
user_proxy['mode'] = 'send_as_user'
user_proxy['tool_name'] = 'feishu_im_user_message'
user_proxy['require_user_token'] = True
user_proxy['prefix'] = '[代发]'
user_proxy['fallback_mode'] = 'relay'

cfg.setdefault('admin_quick_ops', {
    'enabled': False,
    'require_token': True,
    'tokens': ['虾改配置'],
    'allowed_actions': ['status', 'relay-safe', 'direct-on', 'role-scheduler', 'role-executor', 'set-chat-id'],
})

config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('[ok] config updated:', config_path)
print('[ok] dispatch_mode=user_proxy, user_proxy.enabled=true')
PY

chmod +x "${SKILL_DIR}/scripts/main.py" || true
chmod +x "${SKILL_DIR}/scripts/start-user-proxy.sh" || true

echo "[done] user-proxy quick start enabled"
echo "[next] test command:"
echo "python3 ${SKILL_DIR}/scripts/main.py one-click-start --chat-id ${CHAT_ID}"
