# Implementation Notes

## Design baseline

This skill follows a unified protocol for both roles:

- Scheduler (task intake, routing, monitoring, retry)
- Executor (task acceptance, execution, progress, done)

The baseline command set is aligned with the existing OpenClaw multi-bot pattern:

`ASSIGN, ACCEPT, REJECT, PROGRESS, DONE, REVIEW, PASS, FAIL, RETRY, ARCHIVE, CANCEL, QUERY, PING`

For skill operations, add one privileged command:

`ADMIN_INSTALL` (scheduler -> installer-admin)
`ADMIN_QUICK_CONFIG` (scheduler -> installer-admin)

For blocked bot->bot scenarios, prefer `user_proxy` dispatch:

- use `feishu_im_user_message.send` with sender's `user_access_token`
- send `<at user_id=\"executor_open_id\">` in group chat
- fallback to relay when token unavailable

## Recommended runtime contract

1. Every task mutation must include `task_id`.
2. Every role reply should be machine-readable and traceable in JSON.
3. Scheduler must not reassign without recording previous assignee + reason.
4. Executor should emit `PROGRESS` at predictable checkpoints (0/25/50/75/100).
5. Use thread reply in group chat when available to reduce context collision.
6. Installer-admin should only execute `scripts/managed-install.sh` with explicit flags, never `curl | bash`.
7. For quick config, run `scripts/quick-config.sh`; enforce `enabled + token + allowed_actions` before any write.
8. Keep auditable records for proxy sends: `task_id`, `sender_open_id`, `target_executor`.

## Migration strategy (from existing shrimp-team-protocol)

1. Keep current protocol and state machine contract.
2. Replace mock Feishu API stubs with real OpenClaw Feishu tool calls.
3. Keep route policy pluggable (round-robin / best-score / affinity).
4. Add idempotency key on incoming `message_id` to prevent duplicate handling.
