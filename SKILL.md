---
name: feishu-group-scheduler-executor
version: 0.1.0
description: "OpenClaw 飞书群聊多机器人协作技能：统一协议支持调度者与执行者在同一群内进行任务分发、执行回报、状态追踪和故障恢复。"
author: "hongchen"
license: "MIT"

capabilities:
  - id: protocol-normalization
    description: "将群消息标准化为统一任务协议（ASSIGN/ACCEPT/PROGRESS/DONE 等）"
  - id: scheduler-routing
    description: "调度者基于能力标签、负载和健康状态为任务选择最合适执行者"
  - id: executor-reporting
    description: "执行者按协议回报接单、进度、结果和异常，保证群内可追踪"
  - id: task-lifecycle-management
    description: "管理任务状态机、重试、超时处理和归档回执"
  - id: feishu-thread-safe-reply
    description: "支持话题回复和常规回复策略，避免多机器人群聊串线"
  - id: bot-relay-fallback
    description: "当飞书插件限制 bot->bot 派单时，自动切换到人工中继模式"
  - id: managed-skill-install
    description: "提供受控安装/更新脚本（dry-run + 显式确认）供管理员角色调度执行"

permissions:
  network: true
  filesystem: true
  shell: true
  clipboard: false
  env:
    - FEISHU_APP_ID
    - FEISHU_APP_SECRET
    - FEISHU_CHAT_ID

inputs:
  - name: role
    type: string
    required: true
    default: "scheduler"
    description: "当前实例角色：scheduler 或 executor"
  - name: user_message
    type: string
    required: true
    default: ""
    description: "飞书群内收到的原始消息"
  - name: sender
    type: string
    required: true
    default: ""
    description: "发送者名称"
  - name: sender_id
    type: string
    required: false
    default: ""
    description: "发送者 user_id/open_id（用于真实 @）"
  - name: workers_config
    type: object
    required: false
    default: {}
    description: "调度者可见的执行者池配置（能力、负载、在线状态）"
  - name: task_store_path
    type: string
    required: false
    default: "tasks.json"
    description: "任务状态存储路径"
  - name: reply_mode
    type: string
    required: false
    default: "thread"
    description: "回复模式：thread 或 normal"
  - name: sender_type
    type: string
    required: false
    default: "human"
    description: "发送者类型：human 或 bot（用于判断是否需要中继）"
  - name: dispatch_mode
    type: string
    required: false
    default: "auto"
    description: "派单模式：auto / direct / relay"
  - name: relay_operator_name
    type: string
    required: false
    default: "值班同学"
    description: "中继模式下负责转发协议消息的人类操作者名称"
  - name: relay_operator_id
    type: string
    required: false
    default: ""
    description: "中继操作者的飞书 user_id"

outputs:
  - name: outbound_messages
    type: array
    description: "需要发送到群聊的协议消息列表"
  - name: task_updates
    type: object
    description: "任务状态变更（状态、负责人、重试次数、时间戳）"
  - name: routing_decision
    type: object
    description: "调度决策结果（能力判断、候选、最终执行者、原因）"
  - name: execution_signal
    type: object
    description: "执行者侧动作信号（accept/reject/start/progress/done/error）"
  - name: relay_plan
    type: object
    description: "中继派单计划（relay_payload、relay_operator、waiting_relay）"

tags: ["openclaw", "feishu", "group-chat", "multi-agent", "scheduler", "executor"]
minOpenClawVersion: "2.1.0"
---

# Feishu Group Scheduler Executor

## Overview
这是一个面向 OpenClaw + 飞书群场景的“调度者/执行者一体化”技能设计。

同一套协议、同一套状态机，既可部署为调度者（scheduler），也可部署为执行者（executor）：

- `scheduler`：接收自然语言需求，生成任务 ID，按能力与负载选择执行者，持续跟踪状态并回传用户。
- `executor`：按能力接单，持续汇报进度，产出结果并按协议回传。

适合以下场景：
- 一个飞书群里有多个机器人（代码、写作、搜索等）协同工作。
- 希望调度逻辑和执行逻辑统一标准化，便于扩容和治理。
- 需要在群里实时可见任务轨迹（谁接了、做到哪一步、是否失败重试）。

## Usage
### 1) 协议格式

统一消息格式（文本态）：

`@目标 #TASK-YYYYMMDD-NNN COMMAND 内容 #标签1 #标签2`

示例：

- `@代码虾 #TASK-20260318-001 ASSIGN 写一个飞书消息去重器 #代码 #Python`
- `@调度虾 #TASK-20260318-001 PROGRESS 进度: 50% 已完成去重逻辑 #进度更新`
- `@调度虾 #TASK-20260318-001 DONE 已产出脚本与测试说明 #已完成`

### 2) 角色模式

- `role = scheduler`
  - 识别自然语言需求
  - 进行能力判断与执行者路由
  - 发送 `ASSIGN/QUERY/RETRY/ARCHIVE`
- `role = executor`
  - 处理 `ASSIGN/RETRY/CANCEL`
  - 发送 `ACCEPT/PROGRESS/DONE/REJECT`

### 3) 调度决策优先级

1. 能力匹配（capabilities）
2. 在线状态（online > busy > offline）
3. 当前负载（越低越优）
4. 历史成功率（越高越优）

### 4) 回复策略

- `reply_mode=thread`：优先在原话题下回复，降低群噪声与串线风险。
- `reply_mode=normal`：普通群消息回复（兼容未启用 thread 的环境）。

### 5) 派单模式（解决 bot->bot 受限）

- `dispatch_mode=auto`：
  - `sender_type=human` 时直派（direct）
  - `sender_type=bot` 时中继（relay）
- `dispatch_mode=direct`：强制直派（要求插件允许 bot->bot）
- `dispatch_mode=relay`：强制人工中继（生成可转发协议消息）

### 6) 管理任务（安装/更新）

可通过本地受控脚本执行 skill 安装/更新（避免远程脚本直执）：

`bash scripts/managed-install.sh --mode update --allow-network --yes`

也可由调度者先生成管理任务协议消息：

`python scripts/main.py admin-install-task --target '安装虾' --mode update --allow-network`

## Notes
### 任务状态机

`PENDING -> ACCEPTED -> IN_PROGRESS -> DONE -> REVIEWING -> PASSED -> ARCHIVED`

异常分支：
- `REJECT`: 重新分配
- `FAIL`: 进入 `FAILED`，再经 `RETRY` 回到 `IN_PROGRESS`
- `CANCEL`: 终止任务

### 容错规则

- 接单超时：调度者触发重分配。
- 执行超时：调度者发送 `QUERY` 催办，必要时触发 `RETRY`。
- 连续失败上限：默认 3 次，超限后 `ARCHIVE` 并附失败原因。
- 消息去重：基于 `message_id` 缓存，避免重复消费。

### 安全与治理

- 所有群内动作必须带 `task_id`，避免多机器人并发时上下文漂移。
- 对执行者使用真实 `user_id` 的 `<at ...>`，避免“看见消息但未收到提醒”。
- 对自然语言入口做最小化意图识别，不允许无 ID 的隐式状态改写。
- 当插件不消费 bot 消息时，不应继续“等待执行者响应”，而应进入 `waiting_relay`。
- shell 权限仅用于 `scripts/managed-install.sh` 这类受控运维动作，禁止远程脚本直执（如 `curl | bash`）。

### 输出约定

建议输出 JSON，以便接入自动化流水线和观测系统：

```json
{
  "ok": true,
  "role": "scheduler",
  "task_id": "#TASK-20260318-001",
  "action": "assign",
  "target": "代码虾"
}
```

## Dependencies
- Python 3.9+
- 飞书开放平台应用（机器人能力、消息读取/发送权限）
- 推荐将配置放在 `templates/skill-config.template.json` 的衍生文件中

推荐安装/更新（受控执行）：

```bash
bash scripts/managed-install.sh --mode update --allow-network --yes
```

示例命令（本地协议演示脚本）：

```bash
python scripts/main.py create-id
python scripts/main.py parse --message '@代码虾 #TASK-20260318-001 ASSIGN 写个脚本 #代码'
python scripts/main.py route --content '写个 Python 采集脚本' --workers-json '[{"name":"代码虾","capabilities":["代码","Python"],"load":1,"status":"online","success_rate":0.95}]'
python scripts/main.py dispatch --content '写一个消息去重脚本' --sender-type bot --dispatch-mode auto --operator-name '路飞船长' --workers-json '[{"name":"秦隆","user_id":"ou_xxx","capabilities":["代码","Python"],"load":1,"status":"online","success_rate":0.95}]'
python scripts/main.py admin-install-task --target '安装虾' --mode update --allow-network
```
