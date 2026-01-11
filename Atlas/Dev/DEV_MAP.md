# Dev Map (Atlas)

Update Protocol: When you add/edit features, update this map with what changed and where to work.

## Start Here
- Atlas is a minimalist “liquid-glass” iOS workout logger: routines live in JSON, history in SwiftData, and AI helps parse routines + summarize sessions.
- Boot path: `AtlasApp` builds a single SwiftData `ModelContainer`, injects `RoutineStore` + `HistoryStore`, then shows `ContentView`.
- UI start: `ContentView` roots a `NavigationStack` with `HomeView` (calendar only for history access) and presents Settings as a full-screen cover.
- Data storage: routines/templates persist to `Documents/routines.json` via `RoutineStore`; performed sessions/sets persist in SwiftData models (`WorkoutSession`, `ExerciseLog`, `SetLog`, `Workout` for calendar dots).

## Big Picture Architecture
- Templates vs History: `RoutineStore` (Codable + JSON) powers routine builder screens; `HistoryStore` (SwiftData) powers session logging, calendar underlines, and summaries.
- Single shared `ModelContainer`: built once in `AtlasApp` and reused everywhere so `@Query` and manual fetches see the same data; avoid creating extra containers.
- Navigation: `ContentView.Route` drives flows (Home → RoutineList → Create/Review/PreStart → WorkoutSession → PostWorkoutSummary; Home → DayHistory via calendar; Home → Settings).
- AI pipeline: `RoutineAIService` orchestrates generate → repair → parse using `OpenAIChatClient`; prompts and schemas live in `OpenAIChatClient` + `Models/PostWorkoutSummaryModels`..
. . 
## Every File / Folder Inventory

### Root app + navigation
- `AtlasApp.swift` — Launch entry; builds SwiftData container, creates `RoutineStore`/`HistoryStore`/`AuthStore`, injects into `AuthGateView` which chooses Landing vs Content. Change when adding models or new environment objects. Do not drop models from `modelTypes` without migration (data loss). Example: add a new `@Model` type to `modelTypes` to persist new data.
- `ContentView.swift` — Root `NavigationStack` and settings cover. Manages intro overlay and routes into routines/history. Change to add routes or adjust path handling. Avoid removing Route cases without updating destinations. Example: add `.history` navigation to push `AllHistoryView`.
- `HomeView.swift` — Calendar and Start Workout pill. Reads SwiftData via `@Query` for calendar marks and history underlines. Keep filters `endedAt != nil && totalSets > 0` so drafts stay hidden. Example: adjust `activeSessionDays` if you want to include in-progress sessions.
- `SettingsView.swift` — Appearance + weight unit selectors stored in `@AppStorage`. Runs as fullScreenCover from `ContentView`. Change to add new settings rows. Keep dismiss callbacks so Home can close settings. Example: add a “Reset intro” toggle by extending `DropdownType` and the card rows.
- `Item.swift` — Template SwiftData model from Xcode; currently unused. Remove or repurpose only if you also adjust `modelTypes` in `AtlasApp`.
- `Workout.swift` — SwiftData model marking completed workout days for calendar dots. Change only if you handle migrations; normalize dates to start-of-day when saving.

### Routine templates (JSON)
- `RoutineStore.swift` — Codable routines saved to `Documents/routines.json` (custom URL optional for tests). Used by routine views via `@EnvironmentObject`. Change filename or fields carefully; never drop properties without migration. Example: add a `notes` field by extending `Routine`, updating decoding defaults, and regenerating JSON save.
- `RoutineListView.swift` — Lists routines with edit/delete menu and start navigation. Mutations go through `RoutineStore`. Keep `routineMenuTarget` resets to avoid stuck menus. Example: add a “Duplicate” action that calls a new store helper.
- `CreateRoutineView.swift` — Form for title + workout text; triggers AI parsing. Guards duplicate generates with `isGenerating`. Example: add validation before calling AI to require at least one exercise string.
- `ReviewRoutineView.swift` — Edit AI-parsed workouts and save via `RoutineStore`, generating a summary first. Keep `isSaving` guard to prevent double saves. Workout pills are name + remove only; add workouts via the inline field (AI-cleaned via `RoutineAIService.cleanWorkoutName`). Example: allow reordering by adding move support to the ForEach.
- `EditRoutineView.swift` — Simple edit form for existing routines. Calls `onSave` with the draft. Keep trims so blank workouts are prevented. Example: add a toggle to mark favorite routines before saving.
- `RoutinePreStartView.swift` — Pre-start summary of a routine; navigates into `WorkoutSessionView`. Change copy/layout freely; keep `showSession` navigation intact. Example: add a “Regenerate summary” button that re-calls AI before starting.
- `RoutineAIService.swift` — High-level AI pipeline (generate → repair → parse, coaching, summaries). Called by creation/logging flows. Includes title/workout name cleaners (`cleanRoutineTitle`, `cleanWorkoutName`, `cleanExerciseNameAsync`). Change prompts/defaults, but keep error handling and caching. Example: tweak `defaultSets`/`defaultReps` to change auto-filled targets.
- `OpenAIChatClient.swift` — Low-level AI client (Supabase Edge Function proxy to OpenAI), shared prompts, repair/parse helpers. Used by `RoutineAIService`. Change prompts or temperatures; keep JSON parsing and fence stripping aligned with callers. Example: adjust `repairSystemPrompt` if models start returning markdown.
- `OpenAIConfig.swift` — Routes AI calls through the Supabase Edge Function (`openai-proxy`) and sets the default model. Change model name safely; keep auth-required guardrails intact.

### Workout sessions & history (SwiftData)
- `Models/HistoryModels.swift` — SwiftData models (`WorkoutSession`, `ExerciseLog`, `SetLog`, `SetTag`, format helpers). Deleting fields breaks stored data; add new optionals with defaults. Example: add `mood` to `WorkoutSession` with a default value and migrate.
- `Data/HistoryStore.swift` — Single source of truth for history CRUD + queries. All writes go through here. Keep `saveContext()` calls and zero-set discard logic. Example: change `computeTotals` if volume rules need to ignore warm-ups.
- `Views/SessionHistoryStackView.swift` — Collapsed/expanded stack of recent sessions (not currently shown on Home).
- `Views/AllHistoryView.swift` — Full history list with expand/collapse sets. Uses `@Query` sorted newest first. Example: add a filter to hide in-progress sessions by checking `endedAt`.
- `Views/DayHistoryView.swift` — Sessions for a specific day; filters `endedAt` within day window and hides zero-set drafts. Example: add navigation to open a session detail screen.
- `SessionHistoryDetailSheetView.swift` — Session detail sheet showing per-exercise set breakdown (weights/reps/tags) and soft delete (sets `isHidden=true` via HistoryStore).
- `WorkoutSessionView.swift` — Live logger for sets + coaching + summary sheet. Writes via `HistoryStore`, stores sets in kg, and handles alternate set tags. Pager uses `exerciseIndex` + `exerciseRefreshToken` to refresh coaching/last-session/timer as you swipe; timer sheet lives here. Queue pill replaces “Next” and supports swipe/chevron navigation + sheet jump. Avoid breaking `isAddingSet` guard or `completedSessionId` summary trigger. Example: add a “Bodyweight” quick-fill that sets weight to nil.
- `PostWorkoutSummaryView.swift` — Shows AI or cached summaries for a completed session. Loads session by ID, reuses cached JSON/text. Keep cache-first logic to avoid repeat calls. Example: adjust line spacing or add a share button without touching fetch logic.
- `Dev/DevHistorySeeder.swift` — DEBUG-only seeder for fake sessions. Controlled by a UserDefaults flag. Do not enable in release builds. Example: add more seed days for UI testing.
- `StatsView.swift` — Stats tab with Week/Month/All-time toggle, muscle coverage, workload summary, and coach navigator. Uses `StatsMetrics` to aggregate SwiftData sessions.
- Week boundaries: Monday→Sunday via `DateRanges.isoCalendar()` helpers (`DateRanges.startOfWeekMonday` / `weekRangeMonday`); StatsStore and MuscleCoverageScoring use these for filtering and streaks.

- Auth/Supabase files are currently unused; core app flow does not depend on them. Minimal stubs exist (`AuthStore`, `SupabaseClientProvider`) but are not wired into UI yet.

### AI prompts, summaries, and models
- `Models/PostWorkoutSummaryModels.swift` — Codable schema for AI summary JSON. Add optional fields when expanding prompts; keep compatibility with cached data.
- `Models/ExerciseMuscleMap.swift` — Keyword-based muscle lookup fallback for summaries. Extend with new keyword-to-muscle mappings as needed.

### Supabase AI function (openai-proxy)
- Deploy: `tools/deploy_openai_proxy.sh` (uses linked project; falls back with `supabase link --project-ref <PROJECT_REF>` if needed).
- Manual deploy: `supabase functions deploy openai-proxy` (project ref must match `SUPABASE_URL` in Info.plist).
- Health verify: `curl -i https://<PROJECT_REF>.supabase.co/functions/v1/openai-proxy/health` → expect HTTP 200 with `{ "ok": true, "function": "openai-proxy" }`.
- NOT_FOUND means the function name is wrong or the app points at a different project ref.

### Design System / shared UI
- `DesignSystem/AppStyle.swift` — Typography, spacing, padding tokens. Changing values adjusts the entire app; avoid deleting tokens used by views.
- `DesignSystem/AtlasControls.swift` — Shared controls (glass pills, header icons, menus) and sizing tokens. Keep tap targets and modifiers intact when restyling.
- `DesignSystem/GlassCard.swift` — Reusable frosted card container. Tweak corner radius/shadows carefully; many screens rely on it.
- `DesignSystem/PressableGlassButtonStyle.swift` — Glass CTA button styling and press animation. Change padding/scale to retune CTAs.
- `DesignSystem/Haptics.swift` — Light/medium haptic helpers. Simulator won’t vibrate; test on device.
- `DesignSystem/RestTimerHaptics.swift` — CoreHaptics + fallback pattern for the rest timer completion vibration. Call `RestTimerHaptics.playCompletionPattern()` when the timer hits zero.
- `DesignSystem/AppMotion.swift` — Shared animation curves for springs and transitions. Changing values retunes all animations.
- `FriendsView.swift` — Friends tab UI (add friend card, friends list, requests). Uses `FriendsStore` + `AuthStore`; glass cards and pill buttons. Add friend uses inline text field + “Send request” pill.
- `FriendDetailView.swift` — Friend profile compare screen. No calendar; segmented Week/Month/All-time. Compares your `StatsStore` metrics vs friend summaries (workload + placeholder muscle coverage) from `FriendDetailModel` (Supabase fetch). Remove friend confirmation via glass popup.
- `FriendDetailModel.swift` — Fetches friend sessions/stats via `FriendHistoryService`. Holds sessions list; view computes range-filtered metrics.

### Config, secrets, and supporting files
- Supabase app config — Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_REDIRECT_URL` in Info.plist. AI/auth rely on this client being present.
- Supabase Edge Function secrets — `supabase/functions/openai-proxy` reads `OPENAI_API_KEY` from Supabase secrets. No LocalSecrets/Secrets plist is required in the app bundle.
- `OpenAIConfig.swift` (also in AI section) — Holds the default model and Edge Function name for AI calls.
- `Atlas.entitlements` — Empty entitlements plist. Add capabilities here via Xcode if needed; avoid hand-editing XML.
- `Info.plist` — Minimal app plist (background modes array empty). Add permissions/capabilities here via Xcode; malformed XML will break builds.
- `Assets.xcassets/` (AppIcon, AccentColor, Contents.json) — App icons and colors managed by Xcode’s asset catalog. Edit with the asset editor; keep JSON structure intact.
- Project files (.xcodeproj/.xcworkspace) — Not checked into this folder. Open the project from Xcode; edit targets/capabilities there instead of hand-editing pbxproj files.

### Dev docs and notes
- `Dev/DEV_MAP.md` — This guide. Update whenever files/flows change so newcomers can navigate quickly.
- `ExerciseMuscleHeuristics.swift` — Keyword-based mapping from exercise names to muscle groups for stats coverage. Update weights/keywords here; swap with real metadata later.
- `MuscleTargets` (in `StatsView`) — Weekly set targets per muscle; tweak to retune coverage goals and coach suggestions.
- Routine grouping/titles: `RoutineStore.groupDisplayNames` persists group headers (in routines.json). Coach group id is `coach_suggested` and always shows “Coach Suggested”. Start Workout grouping/rename UI lives in `RoutineListView` (`GroupHeaderView` + edit sheet).
- Home history detail: tapping a day summary now presents `DayHistoryView` → `SessionHistoryDetailSheetView`. Session delete is a soft delete via `HistoryStore.deleteSession` (local only); sheet shows exercises, sets/reps/volume (single unit).
- Supabase sync schema/RLS: migrations under `supabase/migrations/` (step4 constraints/RLS in `20260113_step4_rls_constraints.sql`). Session/routine payloads attach `user_id` + `local_id`; routine delete is synced via `SyncService.deleteRoutineRemote(routine:)` (soft delete flag).

## Common “How do I…?” Recipes
- Add fake history sessions for testing: enable `DevHistorySeeder.seedIfNeeded(...)` in DEBUG (e.g., call from `AtlasApp`), tweak `seedDays`, then delete the UserDefaults flag to reseed.
- Change history volume calculation: edit `Data/HistoryStore.computeTotals` to adjust how volumeKg is derived (remember weight is stored in kg).
- Change calendar marks logic: adjust `HomeView.activeSessionDays` (for SwiftData sessions) and `workoutDays` (for `Workout` markers) to include/exclude drafts or other conditions.
- Find where routines get saved: `RoutineStore.fileURL` writes `routines.json` in Documents; `addRoutine`/`updateRoutine`/`deleteRoutine` call `save()`.
- Update OpenAI prompts: edit prompt constants and repair prompts in `OpenAIChatClient.swift` and keep schemas in sync with `Models/PostWorkoutSummaryModels.swift`; high-level orchestration lives in `RoutineAIService.swift`.
- Adjust set logging rules: edit `WorkoutSessionView.addSet` and `HistoryStore.endSession` (discard zero-set sessions) together to avoid inconsistent history.
- Swap weight units default: change `@AppStorage("weightUnit")` default in `WorkoutSessionView`/`SettingsView`; keep kg storage conversion intact.

## Debugging Guide
- Boot logs: `[BOOT]` printed from `AtlasApp`/`AtlasPersistence` when the SwiftData container initializes (shows persistence mode and session count).
- History logs: `[HISTORY]` messages from `HistoryStore` (start/addSet/endSession/repairs) help confirm writes and totals.
- Persistence flush: DEBUG logs print the SwiftData store URL on boot, verify saved sessions after `endSession`, log the most recent ended session on first appear, and log `[HISTORY] flush ok` when the scene goes inactive/background.
- Persistence QA: On device, run without the debugger attached (Xcode Run > “Wait for the executable to be launched”), start and end a session, force-quit, relaunch, and confirm the session remains. Repeat with an archived/installed Release build.
- AI logs: `[AI]`, `[AI][SUMMARY]`, `[AI][COACH]` from `RoutineAIService` + `OpenAIChatClient` show request stages, status codes, and timing; auth/config issues short-circuit with fallback text or user-facing errors.
- Routine logs: `[ROUTINE]` debug prints in routine list/menu actions.
- Where to view: Xcode console while running on device/simulator. If summaries fail, check `errorMessage` in `PostWorkoutSummaryView` and OpenAI status codes. If SwiftData queries look empty, verify `modelContainer` is shared and inspect Application Support for `Atlas.store`.

## Supabase setup (dashboard)
- Auth providers: Enable Apple, Google, and Email. Add redirect URL `atlas://auth-callback` to each provider and to the project-wide Redirect URLs list.
- Profiles SQL: Apply `supabase/schema.sql` in the Supabase SQL Editor (or via `supabase db push`). It creates `public.profiles` (id/email/display_name/avatar_url/created_at/updated_at), enables RLS, adds select/insert/update self policies, auto-updates `updated_at` via trigger, lowers emails via trigger, and adds an auth.users trigger to upsert the profile row on signup.
- App config: Add the Supabase Swift package to the Xcode project and fill `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_REDIRECT_URL` in Info.plist (match the URL scheme in Info.plist).
- Profile service: `Auth/ProfileService.swift` upserts `public.profiles` via the shared Supabase client. `AuthStore` calls it after auth changes or session restores (guarded, idempotent). DEBUG logs: `[AUTH] ensureProfile begin userId=...`, `[AUTH] ensureProfile ok`, `[AUTH][ERROR] ensureProfile failed: ...`.
- Verify: After applying SQL, sign up and confirm `public.profiles` has the user id/email; log out/in and see the row persists; on fresh install with a valid session, ensure restore triggers profile ensure.
- Profiles RLS SQL: `supabase/atlas_profiles.sql` creates `public.profiles` (id/email/display_name/avatar_url + timestamps), enables RLS, and adds self-only select/insert/update policies, email lowercase trigger, and an `updated_at` trigger. Apply via Supabase SQL editor. Table/columns match the iOS `ProfileService` upsert target. Friends/broader access will be added later.
- Friends backend: `supabase/friends.sql` provisions profiles (with normalization triggers), friend_requests + friends tables, RLS policies, and RPCs (`lookup_profile_by_email`, `send_friend_request`, `respond_friend_request`, `profiles_public_lookup`). Run in Supabase SQL editor to enable the friends graph.
- Cloud sync: `Data/HistoryStore.endSession` triggers a best-effort Supabase upsert of a workout summary via `CloudSyncService` (RPC `upsert_workout_session`, table `public.workout_sessions`). Wiring happens in `AtlasApp.init` using the shared `AuthStore.supabaseClient`. Offline errors are logged only.
- Cloud sync params: RPC encodable params live in `CloudSyncRPCParams.swift` (top-level, non-@MainActor). Adjust the upsert payload there to match Supabase `upsert_workout_session`.
- Friend history fetch: models (`FriendHistoryModels.swift`), params (`FriendHistoryRPCParams.swift`), service (`FriendHistoryService.swift`), and store (`FriendHistoryStore.swift`) use RPCs `list_workout_sessions_for_user` and `workout_stats_for_user_row` to fetch friend/self summaries + stats. Store is injected via `AtlasApp` for future UI use. Shared date formatter lives in `AtlasDateFormatters.iso8601WithFractionalSeconds` for RPC decoding.
- Cloud sync coordinator/state: `CloudSyncCoordinator` runs per-session sync + backfill using `CloudSyncService`, `AuthStore`, and `HistoryStore` ended sessions. `CloudSyncStateStore` (UserDefaults) dedupes via per-session endedAt + inflight guard to avoid re-upserts. Wired in `AtlasApp` and attached to `HistoryStore`.
- Friend calendar UI: `FriendDetailView` + `FriendDetailModel` render a month grid with workout dots and per-day session list. Month navigation triggers RPC reload; pull-to-refresh calls the same. Update dot/day logic there.
- Supabase workout sync schema/RPCs live in `supabase/migrations/2024_workout_sessions_friend_access.sql` (table `public.workout_sessions`, RLS with friend read, RPCs `upsert_workout_session`, `list_workout_sessions_for_user`, `workout_stats_for_user_row`, helper `are_friends`). Run in Supabase and reload schema if needed.
- Additional migration for summaries: `SupabaseMigrations/001_workout_session_summaries.sql` sets up `public.workout_session_summaries` (owner-only RLS) and `upsert_workout_session` RPC for cloud sync. Apply in Supabase SQL editor and reload schema if PostgREST cache lags.
- Additional migration for cloud storage: `SupabaseMigrations/002_workout_sessions_cloud.sql` creates `public.workout_sessions_cloud` with RLS + `upsert_workout_session` RPC returning the row. Use this for per-user sync storage; apply and reload schema if needed.
- Friend history RPCs (friend-safe): `SupabaseMigrations/003_friend_history_cloud.sql` adds `are_friends`, `list_workout_sessions_for_user`, and `workout_stats_for_user_row` over `public.workout_sessions_cloud`, enforcing self-or-friend access. Run and reload schema if needed.
- Session-to-cloud mapping: `WorkoutSession+CloudSummary.swift` builds `WorkoutSessionCloudSummary` used by `HistoryStore.endSession` to trigger `CloudSyncCoordinator.sync(summary:)` after successful save.
- Supabase sync schema: see `supabase/atlas_workout_sessions.sql` for `public.workout_sessions` table, RLS policies, and `upsert_workout_session` RPC. Run in Supabase SQL editor, then reload schema (notify pgrst, 'reload schema').


### Auth / Onboarding
- Sign-in UI: `Auth/AuthGateView.swift` (AuthLandingView). Fields: username, email, password, glass inputs.
- Training onboarding sheet: `Auth/TrainingProfileOnboardingView.swift` presented from `AuthGateView` when `AuthStore.needsOnboarding`.
- Training profile state/persistence: `Auth/AuthStore.swift` (trainingProfile), `Auth/ProfileService.swift` (Supabase fields), `Auth/TrainingProfileStore.swift` (local fallback), `Auth/TrainingProfile.swift` model.
- Supabase profile fields migration: `supabase/migrations/20260114_profiles_training_fields.sql`.

### Start Workout / Routine Grouping
- Grouped routine UI & gradient: `RoutineListView.swift` (Start Workout screen). Sections are pill cards with per-group add menu.
- Routine groups persistence & helpers: `RoutineStore.swift` (`groupDisplayNames`, `createGroup`, `deleteGroup`, `setGroup`). Coach group id `coach_suggested`, default user group `user_default`.
- Per-group add flow passes `initialGroupId` into `ReviewRoutineView` via `ContentView` routes.
- Gradient is local (`StartWorkoutGradientBackground`) and easy to remove.
- Group delete action lives in `RoutineListView` edit group sheet (uses `RoutineStore.deleteGroup`, reassigns routines to default group).

### Background Themes / Gradients
- Theme enum & modifier: `DesignSystem/AtlasBackground.swift` (`BackgroundTheme`, `atlasBackgroundTheme`, `atlasBackground`).
- Tab roots set themes via `RootTabShellView` (Home/Friends/Stats). Workout flow uses `.workout` in `RoutineListView`/`WorkoutSessionView`. Auth/onboarding use `.auth` in `AuthGateView`, `UsernamePromptView`, `TrainingProfileOnboardingView`.
- Apply `atlasBackground()` to major screens; nested sheets inherit via environment unless overridden.
