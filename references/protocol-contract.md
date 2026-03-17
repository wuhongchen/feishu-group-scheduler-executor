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
- Timeout:
  - accept timeout => reassignment
  - execution timeout => query + optional retry/escalation
