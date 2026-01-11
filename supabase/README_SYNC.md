## Atlas Supabase Sync (Owner-Only v1)

Tables created by `supabase/migrations/20270111_atlas_core.sql`:
- `profiles` (id = auth.users.id, username unique)
- `workout_sessions` (append-only; unique (user_id, local_id))
- `session_exercises` (append-only; unique (user_id, local_id))
- `set_logs` (append-only; unique (user_id, local_id), carries entered_unit/tag)
- `routines` (soft deletable via `deleted_at`; unique (user_id, local_id))
- `routine_exercises` (child rows; unique (user_id, local_id))

RLS summary:
- Each table enables RLS.
- Owner-only select/insert/update via `user_id = auth.uid()` policies.
- Workout tables forbid delete (rule `*_no_delete`).
- Routine tables allow delete or soft delete (`deleted_at`).

Schema cache refresh (run in Supabase SQL editor if PostgREST errors like PGRST204/PGRST205 appear):
```
select pg_notify('pgrst', 'reload schema');
```
If needed, restart the API service from the dashboard.

Client expectations:
- All upserts use `local_id` as idempotency key (also send `user_id`).
- Push order: workout_sessions → session_exercises → set_logs.
- Pull merges by `local_id` without duplicating drafts; only completed sessions (ended_at != null, total_sets > 0).
- Routines upsert with `group_id`, `local_id`, `is_coach_suggested`; soft delete by setting `deleted_at`.
