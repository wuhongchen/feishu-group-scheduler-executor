# Feishu Group Scheduler Executor

`feishu-group-scheduler-executor` 是一个面向 **OpenClaw + 飞书群聊** 的多机器人协作技能。

它的核心用途是：

- 在同一个群里，让“调度者（Scheduler）”和“执行者（Executor）”按统一协议协同工作。
- 把自然语言任务转成可追踪的任务流（分配、接单、进度、完成、重试、归档）。
- 降低多机器人并发时的串线和失控风险。

---

## 这个技能适合什么场景

- 群里有多个机器人：代码机器人、写作机器人、搜索机器人等。
- 希望由一个调度机器人统一分发任务、追踪状态、回传结果。
- 需要在群里保留完整任务轨迹，便于运营、排障、复盘。

---

## 核心能力

- **统一消息协议**：`ASSIGN / ACCEPT / PROGRESS / DONE / RETRY / ARCHIVE ...`
- **双角色一体化**：同一套 skill 通过 `role` 切换为调度者或执行者
- **任务状态机**：从 `PENDING` 到 `ARCHIVED` 的完整生命周期
- **路由策略**：按能力匹配 + 在线状态 + 负载 + 成功率选择执行者
- **容错机制**：超时重分配、失败重试、取消与归档
- **群聊治理**：支持 thread 回复策略，减少消息噪声
- **插件受限兜底**：当飞书插件不支持 bot->bot 直派单时，自动切换人工中继（relay）
- **一键改配置**：`quick-config.sh` 在开关+口令校验通过后，快速完成常见配置修改
- **用户代发调度**：支持 `send_as_user` 代发 `@执行者`，突破 bot->bot 不投递限制

---

## 协议格式

标准协议消息：

```text
@目标 #TASK-YYYYMMDD-NNN COMMAND 内容 #标签1 #标签2
```

示例：

```text
@代码虾 #TASK-20260318-001 ASSIGN 写一个飞书消息去重器 #代码 #Python
@调度虾 #TASK-20260318-001 PROGRESS 进度: 50% 已完成核心逻辑 #进度更新
@调度虾 #TASK-20260318-001 DONE 已完成并附测试说明 #已完成
```

---

## 快速开始

### 0) 一键安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wuhongchen/feishu-group-scheduler-executor/main/scripts/install.sh)
```

如果是让机器人执行安装/更新，优先使用受控脚本（避免 `curl | bash`）：

```bash
bash scripts/managed-install.sh --mode update --allow-network --yes
```

可选环境变量：

- `OPENCLAW_SKILLS_DIR`：自定义 skills 安装目录
- `REPO_BRANCH`：指定安装分支（默认 `main`）

### 1) 使用模板配置

从模板创建你的配置文件：

- `templates/skill-config.template.json`
- 安装脚本会自动生成 `config.local.json`（如果不存在）

重点填写：

- `identity.role`：`scheduler` 或 `executor`
- `feishu.chat_id`
- 执行者池 `workers.pool`（名称、user_id、能力、负载、成功率）
- 插件约束 `plugin_constraints.bot_to_bot_dispatch`（是否允许 bot 直派 bot）

### 2) 本地协议工具（演示）

```bash
python scripts/main.py create-id
python scripts/main.py parse --message '@代码虾 #TASK-20260318-001 ASSIGN 写个脚本 #代码'
python scripts/main.py route --content '帮我写一个Python脚本抓取网页' --workers-json '[{"name":"代码虾","capabilities":["代码","Python"],"load":1,"status":"online","success_rate":0.95}]'
python scripts/main.py dispatch --content '写一个消息去重脚本' --sender-type bot --dispatch-mode auto --operator-name '路飞船长' --workers-json '[{"name":"秦隆","user_id":"ou_xxx","capabilities":["代码","Python"],"load":1,"status":"online","success_rate":0.95}]'
python scripts/main.py admin-install-task --target '安装虾' --mode update --allow-network
python scripts/main.py quick-config-task --target '安装虾' --quick-action relay-safe --token '虾改配置'
python scripts/main.py dispatch-user-proxy --content '搜索 openclaw feishu plugin 最新资讯' --chat-id 'oc_xxx' --sender-open-id 'ou_user_xxx' --workers-json '[{"name":"秦隆","user_id":"ou_xxx","capabilities":["搜索","代码","通用"],"load":1,"status":"online","success_rate":0.95}]'
python scripts/main.py one-click-start --chat-id 'oc_xxx'
```

---

## 飞书插件限制说明（重点）

在部分飞书/OpenClaw 插件配置下，机器人消息不会触发另一个机器人（即 bot->bot 指令不会被消费）。

本技能提供三种派单模式：

- `direct`：强制直派（需要插件允许）
- `relay`：强制人工中继（让指定人类转发协议消息）
- `auto`：自动判断；若发送者是 bot，则走 relay

当进入 relay 模式时，调度者不会继续“等待执行者响应”，而是进入 `waiting_relay` 状态并输出可转发 payload。

---

## 给“安装虾”执行的受控安装脚本

为了避免 `curl | bash` 被模型判定为高风险，skill 内提供本地受控脚本：

- `scripts/managed-install.sh`

特点：

- 默认 **dry-run**，必须显式 `--yes` 才执行
- 必须显式 `--allow-network` 才会拉取远端仓库
- 只处理当前 skill 安装目录，不执行任意外部脚本

执行示例：

```bash
bash scripts/managed-install.sh --mode update --allow-network --yes
```

---

## 给“安装虾”执行的一键改配置脚本

脚本路径：

- `scripts/quick-config.sh`

执行前安全检查：

- `admin_quick_ops.enabled` 必须为 `true`
- 如启用口令校验，`--token` 必须命中 `admin_quick_ops.tokens`
- 动作必须在 `admin_quick_ops.allowed_actions` 白名单中

先在 `config.local.json` 开启：

```json
"admin_quick_ops": {
  "enabled": true,
  "require_token": true,
  "tokens": ["虾改配置"],
  "allowed_actions": ["status", "relay-safe", "direct-on", "role-scheduler", "role-executor", "set-chat-id"]
}
```

常用动作：

```bash
bash scripts/quick-config.sh --action status --token '虾改配置'
bash scripts/quick-config.sh --action relay-safe --token '虾改配置'
bash scripts/quick-config.sh --action role-executor --token '虾改配置'
bash scripts/quick-config.sh --action set-chat-id --chat-id 'oc_xxx' --token '虾改配置'
```

---

## 一键启动用户代发调度

脚本路径：

- `scripts/start-user-proxy.sh`

一键启动：

```bash
bash scripts/start-user-proxy.sh --chat-id oc_xxx
```

作用：

- 自动更新 `config.local.json` 为 `dispatch_mode=user_proxy`
- 启用 `user_proxy.enabled=true`
- 若用户 token 不可用，自动保留 relay 回退链路

---

## 目录结构

```text
.
├── SKILL.md
├── README.md
├── scripts/
│   ├── main.py
│   ├── install.sh
│   ├── managed-install.sh
│   ├── quick-config.sh
│   └── start-user-proxy.sh
├── references/
│   ├── protocol-contract.md
│   └── implementation-notes.md
└── templates/
    ├── skill-config.template.json
    └── example.template
```

---

## 相关文档

- 技能主规范：`SKILL.md`
- 协议契约：`references/protocol-contract.md`
- 实施建议：`references/implementation-notes.md`

---

## 版本

当前版本：`0.3.0`
