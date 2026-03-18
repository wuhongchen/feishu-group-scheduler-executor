#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="feishu-group-scheduler-executor"
DEFAULT_REPO_URL="https://github.com/wuhongchen/feishu-group-scheduler-executor.git"
DEFAULT_BRANCH="main"

MODE="update"
CONFIRM="false"
ALLOW_NETWORK="false"
REPO_URL="${DEFAULT_REPO_URL}"
REPO_BRANCH="${DEFAULT_BRANCH}"
SKILL_BASE_DIR=""

usage() {
  cat <<'EOF'
Usage:
  managed-install.sh [options]

Options:
  --mode <install|update>      Default: update
  --skills-dir <path>          Override skills base dir
  --repo-url <url>             Default fixed repo URL
  --branch <name>              Default: main
  --allow-network              Allow git clone/fetch from remote
  --yes                        Execute changes (without this: dry-run only)
  -h, --help                   Show help

Examples:
  # Dry-run (safe preview)
  bash scripts/managed-install.sh --mode update

  # Real execution (admin bot / admin user)
  bash scripts/managed-install.sh --mode update --allow-network --yes
EOF
}

resolve_skill_base_dir() {
  if [[ -n "${SKILL_BASE_DIR}" ]]; then
    echo "${SKILL_BASE_DIR}"
    return
  fi
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --skills-dir)
      SKILL_BASE_DIR="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --branch)
      REPO_BRANCH="${2:-}"
      shift 2
      ;;
    --allow-network)
      ALLOW_NETWORK="true"
      shift
      ;;
    --yes)
      CONFIRM="true"
      shift
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

if [[ "${MODE}" != "install" && "${MODE}" != "update" ]]; then
  echo "[error] --mode must be install|update"
  exit 1
fi

BASE_DIR="$(resolve_skill_base_dir)"
TARGET_DIR="${BASE_DIR}/${SKILL_NAME}"
TMP_DIR="$(mktemp -d)"
SOURCE_DIR="${TMP_DIR}/repo"

cleanup() { rm -rf "${TMP_DIR}" || true; }
trap cleanup EXIT

echo "[plan] mode=${MODE}"
echo "[plan] base_dir=${BASE_DIR}"
echo "[plan] target_dir=${TARGET_DIR}"
echo "[plan] repo=${REPO_URL}#${REPO_BRANCH}"
echo "[plan] allow_network=${ALLOW_NETWORK}"

if [[ "${ALLOW_NETWORK}" != "true" ]]; then
  echo "[safe-stop] network disabled. This script requires --allow-network to fetch trusted repo."
  echo "[hint] rerun with: --allow-network --yes"
  exit 2
fi

if [[ "${CONFIRM}" != "true" ]]; then
  echo "[safe-stop] dry-run only. add --yes to execute."
  exit 2
fi

mkdir -p "${BASE_DIR}"

echo "[run] cloning trusted source..."
git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${SOURCE_DIR}"

if [[ -d "${TARGET_DIR}" ]]; then
  BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
  echo "[run] backup existing -> ${BACKUP_DIR}"
  mv "${TARGET_DIR}" "${BACKUP_DIR}"
elif [[ "${MODE}" == "update" ]]; then
  echo "[warn] target not found, update will behave like install."
fi

echo "[run] install to ${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
(cd "${SOURCE_DIR}" && tar --exclude=".git" -cf - .) | (cd "${TARGET_DIR}" && tar -xf -)

CONFIG_PATH="${TARGET_DIR}/config.local.json"
TEMPLATE_PATH="${TARGET_DIR}/templates/skill-config.template.json"
if [[ ! -f "${CONFIG_PATH}" && -f "${TEMPLATE_PATH}" ]]; then
  cp "${TEMPLATE_PATH}" "${CONFIG_PATH}"
  echo "[run] generated config.local.json"
fi

chmod +x "${TARGET_DIR}/scripts/main.py" || true
chmod +x "${TARGET_DIR}/scripts/install.sh" || true
chmod +x "${TARGET_DIR}/scripts/managed-install.sh" || true
chmod +x "${TARGET_DIR}/scripts/quick-config.sh" || true
chmod +x "${TARGET_DIR}/scripts/start-user-proxy.sh" || true

echo "[done] ${SKILL_NAME} ${MODE} completed"
echo "[next] edit ${CONFIG_PATH}"
