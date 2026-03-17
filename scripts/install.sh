#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="feishu-group-scheduler-executor"
REPO_URL="${REPO_URL:-https://github.com/wuhongchen/feishu-group-scheduler-executor.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

resolve_skill_base_dir() {
  if [[ -n "${OPENCLAW_SKILLS_DIR:-}" ]]; then
    echo "${OPENCLAW_SKILLS_DIR}"
    return
  fi

  if [[ -n "${CODEX_HOME:-}" && -d "${CODEX_HOME}/skills" ]]; then
    echo "${CODEX_HOME}/skills"
    return
  fi

  echo "${HOME}/.openclaw/workspace/skills"
}

SKILL_BASE_DIR="$(resolve_skill_base_dir)"
TARGET_DIR="${SKILL_BASE_DIR}/${SKILL_NAME}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}" || true
}
trap cleanup EXIT

echo "[install] skill base dir: ${SKILL_BASE_DIR}"
mkdir -p "${SKILL_BASE_DIR}"

echo "[install] cloning ${REPO_URL}#${REPO_BRANCH}"
git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${TMP_DIR}/repo"

if [[ -d "${TARGET_DIR}" ]]; then
  BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
  echo "[install] existing skill detected, backing up to ${BACKUP_DIR}"
  mv "${TARGET_DIR}" "${BACKUP_DIR}"
fi

echo "[install] installing to ${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
# Copy all files except .git metadata.
(cd "${TMP_DIR}/repo" && tar --exclude=".git" -cf - .) | (cd "${TARGET_DIR}" && tar -xf -)

CONFIG_PATH="${TARGET_DIR}/config.local.json"
TEMPLATE_PATH="${TARGET_DIR}/templates/skill-config.template.json"
if [[ ! -f "${CONFIG_PATH}" && -f "${TEMPLATE_PATH}" ]]; then
  cp "${TEMPLATE_PATH}" "${CONFIG_PATH}"
  echo "[install] generated ${CONFIG_PATH} from template"
fi

chmod +x "${TARGET_DIR}/scripts/main.py" || true
chmod +x "${TARGET_DIR}/scripts/quick-config.sh" || true

echo ""
echo "[done] ${SKILL_NAME} installed"
echo "path: ${TARGET_DIR}"
echo ""
echo "next:"
echo "1) edit ${CONFIG_PATH} (chat_id / workers / relay_operator)"
echo "2) test parser:"
echo "   python3 ${TARGET_DIR}/scripts/main.py parse --message '@代码虾 #TASK-20260318-001 ASSIGN 写个脚本 #代码'"
echo "3) test relay dispatch:"
echo "   python3 ${TARGET_DIR}/scripts/main.py dispatch --content '写一个消息去重脚本' --sender-type bot --dispatch-mode auto --operator-name '值班同学' --workers-json '[{\"name\":\"代码虾\",\"user_id\":\"ou_xxx\",\"capabilities\":[\"代码\",\"Python\"],\"load\":1,\"status\":\"online\",\"success_rate\":0.95}]'"
