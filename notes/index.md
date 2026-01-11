## Notes Index

- **Privacy manifest:** `Atlas/PrivacyInfo.xcprivacy` (declare tracking/data access; ensure target membership in Xcode).
- **Permission usage strings:** `Atlas/Info.plist` (currently only URL schemes; no runtime permissions requested).
- **Reviewer access:** Demo mode is available on the sign-in screen (`Auth/AuthGateView.swift` → “Continue in Demo Mode”). No backend required.
- **App review template:** `notes/app_review_notes_template.md` (fill before submission with contacts, demo creds, and review steps).
- **Data/History:** Single shared SwiftData container built in `AtlasApp.swift`; history CRUD in `Data/HistoryStore.swift`.
- **Stats/coverage:** Computed in `StatsStore.swift` + `MuscleCoverageScoring.swift` (shared with Stats tab and Friend compare).
- **Sync (Supabase):** Config keys in Info.plist (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Sync outbox model `Data/SyncModels.swift`, service `Data/SyncService.swift` (created in `AtlasApp` and passed into stores, not an EnvironmentObject). History upserts enqueued from `HistoryStore.endSession`; routines upserts/deletes from `RoutineStore`. Watermarks stored in UserDefaults.
- **Sync implementation notes:** Filtering/ordering is done on the filter builder returned by `.select()`. Apply filters (`eq/gte/in`) after `select()`, then order/limit, and decode via `execute().value` (no `execute(decoding:)`). Payload helpers live in `Data/SyncService.swift`. End-session triggers `pushCompletedSessions`, routine changes trigger `upsertAllRoutines` / `deleteRoutineRemote`.
- **Supabase schema/RLS:** See `supabase/migrations/20260110_supabase_v1.sql`, `supabase/migrations/20260110_create_routines.sql`, and `supabase/migrations/20260112_fix_rls_and_local_id.sql` for tables/policies (history append-only, routines owner CRUD, friendships helper). History tables: insert/select owner or accepted friend, no updates/deletes. Routines: owner CRUD. Local_id and user_id alignment lives in the 20260112 migration.
- **Migrations:** Supabase SQL under `supabase/migrations/` (tables for profiles, workout_sessions, exercise_logs, set_logs, set_tags, routines; owner-only RLS). Update or add new migrations there.
