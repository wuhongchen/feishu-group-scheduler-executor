# Protocol Contract

## Message format

`@target #TASK-YYYYMMDD-NNN COMMAND content #tag1 #tag2`

Notes:

- `target` can be display name or `<at user_id="..."></at>` wrapper.
- `task_id` is globally unique per day.
- `COMMAND` is uppercase.
- `tags` are optional and used for routing and observability.

## Command semantics

- `ASSIGN`: scheduler -> executor
- `ADMIN_INSTALL`: scheduler -> installer-admin (specialized install/update operation, should use managed-install.sh)
- `ADMIN_QUICK_CONFIG`: scheduler -> installer-admin (guarded quick config operation, should use quick-config.sh)
- `ASSIGN` (user_proxy): scheduler -> (send_as_user tool) -> executor
- `ACCEPT`: executor -> scheduler
- `REJECT`: executor -> scheduler
- `PROGRESS`: executor -> scheduler (and optionally user)
- `DONE`: executor -> scheduler
- `REVIEW`: scheduler -> reviewer
- `PASS`: reviewer -> scheduler
- `FAIL`: reviewer -> scheduler
- `RETRY`: scheduler -> executor
- `ARCHIVE`: scheduler -> creator
- `CANCEL`: scheduler -> executor
- `QUERY`: any -> any (status inquiry)
- `PING`: heartbeat

## State machine

`PENDING -> ACCEPTED -> IN_PROGRESS -> DONE -> REVIEWING -> PASSED -> ARCHIVED`

Exception branches:

- `REJECT` keeps task in pending and triggers reassignment.
- `FAIL` moves to failed and waits for `RETRY`.
- `CANCEL` moves to cancelled from active states.

## Error handling

- Invalid protocol line: ignore and optionally reply with usage hint.
- Invalid transition: return structured error, keep original state.
- Privileged operation:
  - `ADMIN_INSTALL` must only be handled by installer-admin role.
  - always run dry-run first, then explicit confirmation execution.
  - `ADMIN_QUICK_CONFIG` must pass `enabled/token/allowed_actions` checks before applying changes.
- user_proxy dispatch:
  - requires valid `sender_open_id` + `chat_id` + target executor `user_id`.
  - requires user token authorization (`send_as_user`); otherwise fallback to relay.
- Timeout:
  - accept timeout => reassignment
  - execution timeout => query + optional retry/escalation
