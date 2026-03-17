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

## 目录结构

```text
.
├── SKILL.md
├── README.md
├── scripts/
│   ├── main.py
│   ├── install.sh
│   └── managed-install.sh
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

当前版本：`0.1.0`
