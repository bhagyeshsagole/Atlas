# Dev Map (Atlas)

Update Protocol:
- Whenever you add/edit a new feature or file, update this Dev Map with:
  - new file name
  - what it does
  - where dev edits should happen
- Last updated: 2025-02-15

## A) App Entry + Navigation
- What it controls: App bootstrap, root navigation, settings presentation.
- Where to edit:
  - `Atlas/AtlasApp.swift`: App entry; injects `RoutineStore`, sets SwiftData ModelContainer.
  - `Atlas/ContentView.swift`: NavigationStack routes (Home → routines → create/review → settings fullScreenCover).
- SwiftData container init + fallback lives in `Atlas/AtlasApp.swift` (`PersistenceController.makeContainer()`), which retries disk, resets store, then falls back to in-memory with DEBUG logs.
- What to change: Add routes, adjust root environment objects, change preferred color scheme mapping in `resolvedColorScheme`.
- Example: To add a new route, extend `Route` enum in `ContentView` and add a `.navigationDestination` case.

## Session History v1 — Pass 2
- History models: `Atlas/Models/HistoryModels.swift` (WorkoutSession, ExerciseLog, SetLog, SetTag).
- History store: `Atlas/Data/HistoryStore.swift` (CRUD + queries, discard-if-zero-sets, volume calc, date helpers). No `#Predicate` macros; filtering is in Swift.
- Calendar marks/query data come from `HistoryStore.activeDays(in:)`; day sessions from `HistoryStore.sessions(on:)`.
- DayHistoryView wiring not present yet; add consumption later when UI hooks up.
- Dev seeding: `Atlas/DevHistorySeeder.swift` (toggle `DevFlags.seedHistory`, expected Session/Exercise/Set format inline).
- Persistence: SwiftData store lives in Application Support (`Atlas.sqlite`). Verify persistence by logging a session, killing the app, and reopening to see it still present. Boot logs (DEBUG) print store path and history session count.
- Home session deck UI lives in `Atlas/Views/SessionHistoryStackView.swift` (collapsed stack + expand-on-swipe); sessions fed via `@Query` filtering in `Atlas/HomeView.swift`.
- Home session deck visibility: rendered directly under the calendar in `Atlas/HomeView.swift`; sizing handled in `SessionHistoryStackView` (min height). Completed-session filtering occurs in HomeView (`endedAt != nil && totalSets > 0`), and a placeholder card is shown when empty.
- All history screen: `Atlas/Views/AllHistoryView.swift`; route added in `ContentView` as `.history`; Home placeholder card navigates to it.

## B) Routines (templates)
- What it controls: Routine templates (name + workouts), persistence via JSON.
- Where to edit:
  - `Atlas/RoutineStore.swift`: Routine and RoutineWorkout models (Codable), load/save to `routines.json`.
  - `Atlas/ReviewRoutineView.swift`: Finalizes routine save; generates and stores routine `summary`.
- What to change: Add fields to routines (update Codable/migration defaults); adjust save/load paths; tweak summary storage hook.
- Example format (Routine JSON):
  ```json
  [
    {
      "id": "UUID",
      "name": "Push",
      "createdAt": "ISO8601",
      "workouts": [
        { "id": "UUID", "name": "Bench Press", "wtsText": "135 lb", "repsText": "4x8" }
      ],
      "summary": "Focus: Chest..."
    }
  ]
  ```

## C) Workout Sessions / History (real performance logs)
- What it controls: Actual performed sessions, exercises, sets (SwiftData).
- Where to edit:
  - `Atlas/Models/WorkoutSessionModels.swift`: SwiftData models `WorkoutSession`, `ExerciseLog`, `SetLog`; formatting helpers; AI summary cache fields.
  - `Atlas/WorkoutSessionView.swift`: Logs sets, session-only exercises, queries last session history; routes to post-workout summary.
  - `Atlas/DevHistorySeeder.swift` (DEBUG): Optional fake history seeding.
  - `Atlas/PostWorkoutSummaryView.swift`: Post-session TL;DR layout and loading/caching of AI summary.
  - `Atlas/Models/ExerciseMuscleMap.swift`: Exercise → primary/secondary muscle lookup for summaries.
- What to change: Add fields to logs; adjust history queries; tweak set logging UI; edit seed data when testing; adjust summary display spacing.
- Example format (SetLog stored canonically in kg):
  - `SetLog(tag: "S", weightKg: 60.0, reps: 8, createdAt: Date())`

## D) AI / OpenAI
- What it controls: Model name, prompts, parsing/repair, summary/coaching generation.
- Where to edit:
  - `Atlas/OpenAIConfig.swift`: Model name (`gpt-4o-mini`), API key loader (from `LocalSecrets`).
  - `Atlas/OpenAIChatClient.swift`: Request building, prompts (generation/repair/summary/coaching), parsing/repair JSON logic.
  - `Atlas/RoutineAIService.swift`: Request vs explicit parsing, salvage, summary and exercise coaching cache.
  - API key is read on-demand inside AI calls; missing keys only fail when a request is made (no launch-time assertions).
  - API key source: `Atlas/Config/LocalSecrets.swift` (do not commit real keys).
- How to test key works (non-UI):
  - Run a generate/repair flow; look for logs `[AI][REQ] stage=generate` and HTTP status 200 in DEBUG console.
  - Missing/invalid key prints `[AI] Key present: false` or throws `Missing OpenAI API key.`.

## Post-Workout Summary (AI)
- What it controls: AI-generated TL;DR summary after session completion.
- Where to edit:
  - Prompt/schema: `Atlas/OpenAIChatClient.swift` (`postSummary...` prompts), `Atlas/RoutineAIService.swift` (`generatePostWorkoutSummary`), models in `Atlas/Models/PostWorkoutSummaryModels.swift`.
  - Layout + spacing: `Atlas/PostWorkoutSummaryView.swift` (`tldrCardPadding`, `sectionSpacing`, `exerciseRowMaxLines`).
  - Muscle lookup: `Atlas/Models/ExerciseMuscleMap.swift`.
  - Caching fields on session: `WorkoutSession.aiPostSummaryJSON`, `.aiPostSummaryGeneratedAt`, `.aiPostSummaryModel`, `.durationSeconds`.
- What to change: Tweak TL;DR lines/section spacing, edit muscle map entries, adjust rating/target wording in the prompt.

## E) Design System / UI Consistency
- What it controls: Typography scale, spacing, glass styling, shared controls.
- Where to edit:
  - `Atlas/DesignSystem/AppStyle.swift`: AppTypeScale, font sizes, spacing, animation tokens.
  - `Atlas/DesignSystem/AtlasControls.swift`: Pill/card/menu sizing, header icon sizes, glass modifiers.
  - `Atlas/DesignSystem/GlassCard.swift`: Glass card stroke/shadow.
- What to change: Global font sizes, padding, pill heights, icon sizes. If something looks off-size, check `AppStyle` and `AtlasControls` first.

## F) Popups / Menus / Haptics
- What it controls: Alternate popup, popup styling, haptic utilities.
- Where to edit:
  - `Atlas/WorkoutSessionView.swift`: Alternate popup position/style (menu background opacity/tone), anchored to the Alternate button.
  - `Atlas/DesignSystem/AtlasControls.swift`: Popup animations/sizing tokens.
  - `Atlas/DesignSystem/Haptics.swift`: Haptic strength (`playLightTap`, `playMediumTap`).
- What to change: Adjust popup opacity/tone, anchor math, or haptic styles.

## G) Common “I want to change X” shortcuts
- Change global font sizes → `Atlas/DesignSystem/AppStyle.swift` → AppTypeScale/font constants.
- Change header icon size → `Atlas/DesignSystem/AtlasControls.swift` → `headerIconSize`.
- Change popup opacity/tone → `Atlas/WorkoutSessionView.swift` → `menuBackgroundOpacity` + `menuBackgroundColorDark/Light`.
- Change AI routine format/prompts → `Atlas/OpenAIChatClient.swift` and `Atlas/RoutineAIService.swift`.
- Change history storage models → `Atlas/Models/WorkoutSessionModels.swift`.
- Change routine storage path/shape → `Atlas/RoutineStore.swift`.
- Seed fake history → `Atlas/DevHistorySeeder.swift` → toggle `DevFlags.seedHistory` and edit `sampleSessions()`.
