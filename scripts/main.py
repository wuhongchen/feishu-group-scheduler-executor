#!/usr/bin/env python3
"""Protocol utility for Feishu group scheduler/executor skill."""

import argparse
import json
import re
import sys
from datetime import datetime
from typing import Any, Dict, List, Optional

MESSAGE_RE = re.compile(
    r"^@(.+?)\s+(#[A-Z]+-\d{8}-\d{3,})\s+([A-Z]+)\s+([\s\S]+?)(?:\s+((?:#[a-zA-Z0-9_\u4e00-\u9fa5]+\s*)*))?$"
)
AT_TAG_RE = re.compile(r'<at[^>]*user_id="([^"]*)"[^>]*>([^<]*)</at>')
AT_SIMPLE_RE = re.compile(r"<at[^>]*>([^<]*)</at>")

CAPABILITY_KEYWORDS = {
    "代码": ["代码", "程序", "脚本", "bug", "开发", "python", "js"],
    "文案": ["文案", "文章", "写作", "公众号", "小红书"],
    "搜索": ["搜索", "调研", "资料", "检索", "查询"],
    "分析": ["分析", "统计", "报告", "总结"],
    "设计": ["设计", "原型", "ui", "ux"],
}


def clean_feishu_tags(message: str) -> str:
    def replace_with_user(match: re.Match[str]) -> str:
        user_id = match.group(1)
        display_name = (match.group(2) or "").strip() or user_id
        return f"@{display_name}"

    result = AT_TAG_RE.sub(replace_with_user, message)
    result = AT_SIMPLE_RE.sub(lambda m: f"@{m.group(1)}", result)
    return result


def create_task_id(prefix: str = "TASK") -> str:
    today = datetime.now().strftime("%Y%m%d")
    serial = datetime.now().strftime("%H%M%S")
    return f"#{prefix}-{today}-{serial}"


def parse_message(message: str) -> Optional[Dict[str, Any]]:
    clean_msg = clean_feishu_tags(message.strip())
    match = MESSAGE_RE.match(clean_msg)
    if not match:
        return None
    target, task_id, command, content, tags_str = match.groups()
    tags: List[str] = []
    if tags_str:
        tags = [tag.strip().lstrip("#") for tag in tags_str.split() if tag.strip()]
    return {
        "target": target,
        "task_id": task_id,
        "command": command,
        "content": content.strip(),
        "tags": tags,
        "raw": message,
        "clean": clean_msg,
    }


def format_message(
    target: str,
    task_id: str,
    command: str,
    content: str,
    tags: Optional[List[str]] = None,
    target_id: str = "",
) -> str:
    target_token = f'<at user_id="{target_id}"></at>' if target_id else f"@{target}"
    tags = tags or []
    tags_part = " ".join(f"#{tag}" for tag in tags)
    parts = [target_token, task_id, command.upper(), content]
    if tags_part:
        parts.append(tags_part)
    return " ".join(parts)


def infer_capability(content: str) -> str:
    text = content.lower()
    for capability, keywords in CAPABILITY_KEYWORDS.items():
        if any(keyword in text for keyword in keywords):
            return capability
    return "通用"


def route_worker(content: str, workers: List[Dict[str, Any]]) -> Dict[str, Any]:
    capability = infer_capability(content)
    candidates: List[Dict[str, Any]] = []

    for worker in workers:
        status = worker.get("status", "unknown")
        if status == "offline":
            continue

        caps = worker.get("capabilities", [])
        if capability not in caps and "通用" not in caps:
            continue

        load = int(worker.get("load", 0))
        success_rate = float(worker.get("success_rate", 1.0))
        score = success_rate * 100 - load * 10

        item = {
            "name": worker.get("name", ""),
            "user_id": worker.get("user_id", ""),
            "capabilities": caps,
            "status": status,
            "load": load,
            "success_rate": success_rate,
            "score": round(score, 2),
        }
        candidates.append(item)

    if not candidates:
        return {
            "required_capability": capability,
            "selected": None,
            "reason": "no_candidate",
            "candidates": [],
        }

    candidates.sort(key=lambda c: c["score"], reverse=True)
    selected = candidates[0]
    return {
        "required_capability": capability,
        "selected": selected,
        "reason": "best_score",
        "candidates": candidates,
    }


def build_dispatch_plan(
    content: str,
    workers: List[Dict[str, Any]],
    task_id: str = "",
    sender_type: str = "human",
    dispatch_mode: str = "auto",
    operator_name: str = "值班同学",
    operator_id: str = "",
    extra_tags: Optional[List[str]] = None,
) -> Dict[str, Any]:
    decision = route_worker(content, workers)
    selected = decision.get("selected")
    required_capability = decision.get("required_capability", "通用")
    if not selected:
        return {
            "ok": False,
            "action": "no_candidate",
            "reason": "no_available_worker",
            "routing_decision": decision,
            "outbound_messages": [],
        }

    task_id = task_id or create_task_id()
    tags = [required_capability] + (extra_tags or [])
    assign_message = format_message(
        target=selected["name"],
        task_id=task_id,
        command="ASSIGN",
        content=content,
        tags=tags,
        target_id=selected.get("user_id", ""),
    )

    if dispatch_mode == "direct":
        mode = "direct"
    elif dispatch_mode == "relay":
        mode = "relay"
    else:
        mode = "relay" if sender_type == "bot" else "direct"

    if mode == "direct":
        return {
            "ok": True,
            "action": "dispatch_direct",
            "task_id": task_id,
            "routing_decision": decision,
            "outbound_messages": [assign_message],
            "next_status": "waiting_executor",
        }

    relay_target = f'<at user_id="{operator_id}"></at>' if operator_id else f"@{operator_name}"
    relay_message = (
        f"{relay_target} 当前飞书插件限制 bot->bot 直派单，请代转以下协议消息给执行者：\n"
        f"{assign_message}"
    )
    return {
        "ok": True,
        "action": "dispatch_relay",
        "task_id": task_id,
        "routing_decision": decision,
        "outbound_messages": [relay_message],
        "relay_payload": assign_message,
        "next_status": "waiting_relay",
        "relay_operator": {
            "name": operator_name,
            "user_id": operator_id,
        },
    }


def build_admin_install_task(
    target: str,
    task_id: str = "",
    target_id: str = "",
    mode: str = "update",
    allow_network: bool = True,
) -> Dict[str, Any]:
    task_id = task_id or create_task_id("ADMIN")
    cmd = "bash scripts/managed-install.sh"
    cmd += f" --mode {mode}"
    if allow_network:
        cmd += " --allow-network"
    cmd += " --yes"
    message = format_message(
        target=target,
        task_id=task_id,
        command="ASSIGN",
        content=f"ADMIN_INSTALL(安装管理员职责) 执行 `{cmd}` 并回传日志摘要",
        tags=["admin_install", "skill_ops"],
        target_id=target_id,
    )
    return {
        "ok": True,
        "task_id": task_id,
        "action": "admin_install_assign",
        "outbound_messages": [message],
        "run_command": cmd,
    }


def output(payload: Dict[str, Any], exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return exit_code


def main() -> int:
    parser = argparse.ArgumentParser(description="Feishu group scheduler/executor protocol utility")
    sub = parser.add_subparsers(dest="action", required=True)

    create_id = sub.add_parser("create-id", help="Create task ID")
    create_id.add_argument("--prefix", default="TASK")

    parse = sub.add_parser("parse", help="Parse protocol message")
    parse.add_argument("--message", required=True)

    fmt = sub.add_parser("format", help="Build protocol message")
    fmt.add_argument("--target", required=True)
    fmt.add_argument("--task-id", required=True)
    fmt.add_argument("--command", required=True)
    fmt.add_argument("--content", required=True)
    fmt.add_argument("--tags", default="")
    fmt.add_argument("--target-id", default="")

    route = sub.add_parser("route", help="Route task to a worker")
    route.add_argument("--content", required=True)
    route.add_argument("--workers-json", required=True, help="JSON array of worker objects")

    dispatch = sub.add_parser("dispatch", help="Build scheduler dispatch plan (direct/relay)")
    dispatch.add_argument("--content", required=True)
    dispatch.add_argument("--workers-json", required=True, help="JSON array of worker objects")
    dispatch.add_argument("--task-id", default="")
    dispatch.add_argument("--sender-type", choices=["human", "bot"], default="human")
    dispatch.add_argument("--dispatch-mode", choices=["auto", "direct", "relay"], default="auto")
    dispatch.add_argument("--operator-name", default="值班同学")
    dispatch.add_argument("--operator-id", default="")
    dispatch.add_argument("--tags", default="")

    admin_install = sub.add_parser("admin-install-task", help="Build protocol task for managed skill install/update")
    admin_install.add_argument("--target", default="安装虾")
    admin_install.add_argument("--target-id", default="")
    admin_install.add_argument("--task-id", default="")
    admin_install.add_argument("--mode", choices=["install", "update"], default="update")
    admin_install.add_argument("--allow-network", action="store_true")

    args = parser.parse_args()

    if args.action == "create-id":
        return output({"ok": True, "task_id": create_task_id(args.prefix)})

    if args.action == "parse":
        parsed = parse_message(args.message)
        if not parsed:
            return output({"ok": False, "error": "invalid_protocol_message"}, exit_code=1)
        return output({"ok": True, "parsed": parsed})

    if args.action == "format":
        tags = [tag.strip() for tag in args.tags.split(",") if tag.strip()]
        message = format_message(
            target=args.target,
            task_id=args.task_id,
            command=args.command,
            content=args.content,
            tags=tags,
            target_id=args.target_id,
        )
        return output({"ok": True, "message": message})

    if args.action == "route":
        try:
            workers = json.loads(args.workers_json)
            if not isinstance(workers, list):
                raise ValueError("workers-json must be a JSON array")
        except Exception as exc:  # noqa: BLE001
            return output({"ok": False, "error": f"invalid_workers_json: {exc}"}, exit_code=1)

        decision = route_worker(args.content, workers)
        return output({"ok": True, "decision": decision})

    if args.action == "dispatch":
        try:
            workers = json.loads(args.workers_json)
            if not isinstance(workers, list):
                raise ValueError("workers-json must be a JSON array")
        except Exception as exc:  # noqa: BLE001
            return output({"ok": False, "error": f"invalid_workers_json: {exc}"}, exit_code=1)

        tags = [tag.strip() for tag in args.tags.split(",") if tag.strip()]
        plan = build_dispatch_plan(
            content=args.content,
            workers=workers,
            task_id=args.task_id,
            sender_type=args.sender_type,
            dispatch_mode=args.dispatch_mode,
            operator_name=args.operator_name,
            operator_id=args.operator_id,
            extra_tags=tags,
        )
        exit_code = 0 if plan.get("ok") else 1
        return output(plan, exit_code=exit_code)

    if args.action == "admin-install-task":
        plan = build_admin_install_task(
            target=args.target,
            task_id=args.task_id,
            target_id=args.target_id,
            mode=args.mode,
            allow_network=args.allow_network,
        )
        return output(plan)

    return output({"ok": False, "error": "unknown_action"}, exit_code=1)


if __name__ == "__main__":
    sys.exit(main())
