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
- What to change: Add routes, adjust root environment objects, change preferred color scheme mapping in `resolvedColorScheme`.
- Example: To add a new route, extend `Route` enum in `ContentView` and add a `.navigationDestination` case.

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
  - `Atlas/Models/WorkoutSessionModels.swift`: SwiftData models `WorkoutSession`, `ExerciseLog`, `SetLog`; formatting helpers.
  - `Atlas/WorkoutSessionView.swift`: Logs sets, session-only exercises, queries last session history.
  - `Atlas/DevHistorySeeder.swift` (DEBUG): Optional fake history seeding.
- What to change: Add fields to logs; adjust history queries; tweak set logging UI; edit seed data when testing.
- Example format (SetLog stored canonically in kg):
  - `SetLog(tag: "S", weightKg: 60.0, reps: 8, createdAt: Date())`

## D) AI / OpenAI
- What it controls: Model name, prompts, parsing/repair, summary/coaching generation.
- Where to edit:
  - `Atlas/OpenAIConfig.swift`: Model name (`gpt-4o-mini`), API key loader (from `LocalSecrets`).
  - `Atlas/OpenAIChatClient.swift`: Request building, prompts (generation/repair/summary/coaching), parsing/repair JSON logic.
  - `Atlas/RoutineAIService.swift`: Request vs explicit parsing, salvage, summary and exercise coaching cache.
  - API key source: `Atlas/Config/LocalSecrets.swift` (do not commit real keys).
- How to test key works (non-UI):
  - Run a generate/repair flow; look for logs `[AI][REQ] stage=generate` and HTTP status 200 in DEBUG console.
  - Missing/invalid key prints `[AI] Key present: false` or throws `Missing OpenAI API key.`.

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
