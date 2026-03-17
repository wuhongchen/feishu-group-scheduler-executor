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

### 1) 使用模板配置

从模板创建你的配置文件：

- `templates/skill-config.template.json`

重点填写：

- `identity.role`：`scheduler` 或 `executor`
- `feishu.chat_id`
- 执行者池 `workers.pool`（名称、user_id、能力、负载、成功率）

### 2) 本地协议工具（演示）

```bash
python scripts/main.py create-id
python scripts/main.py parse --message '@代码虾 #TASK-20260318-001 ASSIGN 写个脚本 #代码'
python scripts/main.py route --content '帮我写一个Python脚本抓取网页' --workers-json '[{"name":"代码虾","capabilities":["代码","Python"],"load":1,"status":"online","success_rate":0.95}]'
```

---

## 目录结构

```text
.
├── SKILL.md
├── README.md
├── scripts/
│   └── main.py
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
