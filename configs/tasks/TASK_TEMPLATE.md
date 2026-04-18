# Task: <short title>

status: pending

## Description

What needs to be done, and why.

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Next Steps

1. First action required to make progress.
2. …

## Blockers

- (none — or describe what is blocking progress)

## History

| Date | Update |
|------|--------|
| YYYY-MM-DD | Task created |

---
> Schema note (for heartbeat scanning):
>
> The `status:` field on the second line drives the `pending-tasks` heartbeat.
> Valid values: `pending` | `in-progress` | `blocked` | `done`
>
> The heartbeat alerts when status is `pending` or `blocked` AND the file has
> not been modified in more than 24 hours.  Set status to `done` when complete.
>
> Copy this file to workspace/tasks/<TASK_NAME>.md to start a new task.
