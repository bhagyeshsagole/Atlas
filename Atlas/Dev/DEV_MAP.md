# Dev Map (Atlas)

Update Protocol: When you add/edit features, update this map with what changed and where to work.

## Start Here
- Atlas is a minimalist “liquid-glass” iOS workout logger: routines live in JSON, history in SwiftData, and AI helps parse routines + summarize sessions.
- Boot path: `AtlasApp` builds a single SwiftData `ModelContainer`, injects `RoutineStore` + `HistoryStore`, then shows `ContentView`.
- UI start: `ContentView` roots a `NavigationStack` with `HomeView` (calendar + session deck) and presents Settings as a full-screen cover.
- Data storage: routines/templates persist to `Documents/routines.json` via `RoutineStore`; performed sessions/sets persist in SwiftData models (`WorkoutSession`, `ExerciseLog`, `SetLog`, `Workout` for calendar dots).

## Big Picture Architecture
- Templates vs History: `RoutineStore` (Codable + JSON) powers routine builder screens; `HistoryStore` (SwiftData) powers session logging, calendar underlines, and summaries.
- Single shared `ModelContainer`: built once in `AtlasApp` and reused everywhere so `@Query` and manual fetches see the same data; avoid creating extra containers.
- Navigation: `ContentView.Route` drives flows (Home → RoutineList → Create/Review/PreStart → WorkoutSession → PostWorkoutSummary; Home → AllHistory/DayHistory; Home → Settings).
- AI pipeline: `RoutineAIService` orchestrates generate → repair → parse using `OpenAIChatClient`; prompts and schemas live in `OpenAIChatClient` + `Models/PostWorkoutSummaryModels`..
. . 
## Every File / Folder Inventory

### Root app + navigation
- `AtlasApp.swift` — Launch entry; builds SwiftData container, creates `RoutineStore`/`HistoryStore`, injects into `ContentView`. Change when adding models or new environment objects. Do not drop models from `modelTypes` without migration (data loss). Example: add a new `@Model` type to `modelTypes` to persist new data.
- `ContentView.swift` — Root `NavigationStack` and settings cover. Manages intro overlay and routes into routines/history. Change to add routes or adjust path handling. Avoid removing Route cases without updating destinations. Example: add `.history` navigation to push `AllHistoryView`.
- `HomeView.swift` — Calendar, session deck entry, Start Workout pill. Reads SwiftData via `@Query` for calendar marks and session deck. Change for calendar logic or entry points. Keep filters `endedAt != nil && totalSets > 0` so drafts stay hidden. Example: adjust `activeSessionDays` if you want to include in-progress sessions.
- `SettingsView.swift` — Appearance + weight unit selectors stored in `@AppStorage`. Runs as fullScreenCover from `ContentView`. Change to add new settings rows. Keep dismiss callbacks so Home can close settings. Example: add a “Reset intro” toggle by extending `DropdownType` and the card rows.
- `Item.swift` — Template SwiftData model from Xcode; currently unused. Remove or repurpose only if you also adjust `modelTypes` in `AtlasApp`.
- `Workout.swift` — SwiftData model marking completed workout days for calendar dots. Change only if you handle migrations; normalize dates to start-of-day when saving.

### Routine templates (JSON)
- `RoutineStore.swift` — Codable routines saved to `Documents/routines.json` (custom URL optional for tests). Used by routine views via `@EnvironmentObject`. Change filename or fields carefully; never drop properties without migration. Example: add a `notes` field by extending `Routine`, updating decoding defaults, and regenerating JSON save.
- `RoutineListView.swift` — Lists routines with edit/delete menu and start navigation. Mutations go through `RoutineStore`. Keep `routineMenuTarget` resets to avoid stuck menus. Example: add a “Duplicate” action that calls a new store helper.
- `CreateRoutineView.swift` — Form for title + workout text; triggers AI parsing. Guards duplicate generates with `isGenerating`. Example: add validation before calling AI to require at least one exercise string.
- `ReviewRoutineView.swift` — Edit AI-parsed workouts and save via `RoutineStore`, generating a summary first. Keep `isSaving` guard to prevent double saves. Example: allow reordering by adding move support to the ForEach.
- `EditRoutineView.swift` — Simple edit form for existing routines. Calls `onSave` with the draft. Keep trims so blank workouts are prevented. Example: add a toggle to mark favorite routines before saving.
- `RoutinePreStartView.swift` — Pre-start summary of a routine; navigates into `WorkoutSessionView`. Change copy/layout freely; keep `showSession` navigation intact. Example: add a “Regenerate summary” button that re-calls AI before starting.
- `RoutineAIService.swift` — High-level AI pipeline (generate → repair → parse, coaching, summaries). Called by creation/logging flows. Change prompts/defaults, but keep error handling and caching. Example: tweak `defaultSets`/`defaultReps` to change auto-filled targets.
- `OpenAIChatClient.swift` — Low-level OpenAI HTTP client, shared prompts, repair/parse helpers. Used by `RoutineAIService`. Change prompts or temperatures; keep JSON parsing and fence stripping aligned with callers. Example: adjust `repairSystemPrompt` if models start returning markdown.
- `OpenAIConfig.swift` — Reads API key from `LocalSecrets` and sets default model. Change model name safely; keep empty-key guard to avoid crashes.

### Workout sessions & history (SwiftData)
- `Models/HistoryModels.swift` — SwiftData models (`WorkoutSession`, `ExerciseLog`, `SetLog`, `SetTag`, format helpers). Deleting fields breaks stored data; add new optionals with defaults. Example: add `mood` to `WorkoutSession` with a default value and migrate.
- `Data/HistoryStore.swift` — Single source of truth for history CRUD + queries. All writes go through here. Keep `saveContext()` calls and zero-set discard logic. Example: change `computeTotals` if volume rules need to ignore warm-ups.
- `Views/SessionHistoryStackView.swift` — Collapsed/expanded stack of recent sessions on Home. Change spacing/animation; keep drag thresholds to avoid jitter.
- `Views/AllHistoryView.swift` — Full history list with expand/collapse sets. Uses `@Query` sorted newest first. Example: add a filter to hide in-progress sessions by checking `endedAt`.
- `Views/DayHistoryView.swift` — Sessions for a specific day; filters `endedAt` within day window and hides zero-set drafts. Example: add navigation to open a session detail screen.
- `WorkoutSessionView.swift` — Live logger for sets + coaching + summary sheet. Writes via `HistoryStore`, stores sets in kg, and handles alternate set tags. Avoid breaking `isAddingSet` guard or `completedSessionId` summary trigger. Example: add a “Bodyweight” quick-fill that sets weight to nil.
- `PostWorkoutSummaryView.swift` — Shows AI or cached summaries for a completed session. Loads session by ID, reuses cached JSON/text. Keep cache-first logic to avoid repeat calls. Example: adjust line spacing or add a share button without touching fetch logic.
- `Dev/DevHistorySeeder.swift` — DEBUG-only seeder for fake sessions. Controlled by a UserDefaults flag. Do not enable in release builds. Example: add more seed days for UI testing.

### AI prompts, summaries, and models
- `Models/PostWorkoutSummaryModels.swift` — Codable schema for AI summary JSON. Add optional fields when expanding prompts; keep compatibility with cached data.
- `Models/ExerciseMuscleMap.swift` — Keyword-based muscle lookup fallback for summaries. Extend with new keyword-to-muscle mappings as needed.

### Design System / shared UI
- `DesignSystem/AppStyle.swift` — Typography, spacing, padding tokens. Changing values adjusts the entire app; avoid deleting tokens used by views.
- `DesignSystem/AtlasControls.swift` — Shared controls (glass pills, header icons, menus) and sizing tokens. Keep tap targets and modifiers intact when restyling.
- `DesignSystem/GlassCard.swift` — Reusable frosted card container. Tweak corner radius/shadows carefully; many screens rely on it.
- `DesignSystem/PressableGlassButtonStyle.swift` — Glass CTA button styling and press animation. Change padding/scale to retune CTAs.
- `DesignSystem/Haptics.swift` — Light/medium haptic helpers. Simulator won’t vibrate; test on device.
- `DesignSystem/AppMotion.swift` — Shared animation curves for springs and transitions. Changing values retunes all animations.

### Config, secrets, and supporting files
- `Config/LocalSecrets.swift` — Local-only API keys. Do not commit real credentials. Missing keys cause AI calls to throw.
- `Secrets.plist` — Plist placeholder with `OPENAI_API_KEY`. Useful for plist-based loading if needed; keep real keys out of source control.
- `OpenAIConfig.swift` (also in AI section) — Reads the key above; keep trimming logic.
- `Atlas.entitlements` — Empty entitlements plist. Add capabilities here via Xcode if needed; avoid hand-editing XML.
- `Info.plist` — Minimal app plist (background modes array empty). Add permissions/capabilities here via Xcode; malformed XML will break builds.
- `Assets.xcassets/` (AppIcon, AccentColor, Contents.json) — App icons and colors managed by Xcode’s asset catalog. Edit with the asset editor; keep JSON structure intact.
- Project files (.xcodeproj/.xcworkspace) — Not checked into this folder. Open the project from Xcode; edit targets/capabilities there instead of hand-editing pbxproj files.
- `.gitignore` — Not present in this repo; add one at the root if you need to ignore DerivedData or build artifacts (does not affect runtime logic).

### Dev docs and notes
- `Dev/DEV_MAP.md` — This guide. Update whenever files/flows change so newcomers can navigate quickly.

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
- AI logs: `[AI]`, `[AI][SUMMARY]`, `[AI][COACH]` from `RoutineAIService` + `OpenAIChatClient` show request stages, status codes, and timing; missing API key logs `[AI] Key present: false` before throwing.
- Routine logs: `[ROUTINE]` debug prints in routine list/menu actions.
- Where to view: Xcode console while running on device/simulator. If summaries fail, check `errorMessage` in `PostWorkoutSummaryView` and OpenAI status codes. If SwiftData queries look empty, verify `modelContainer` is shared and inspect Application Support for `Atlas.store`.
