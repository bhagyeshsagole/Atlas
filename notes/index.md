## Notes Index

- **Privacy manifest:** `Atlas/PrivacyInfo.xcprivacy` (declare tracking/data access; ensure target membership in Xcode).
- **Permission usage strings:** `Atlas/Info.plist` (currently only URL schemes; no runtime permissions requested).
- **Reviewer access:** Demo mode is available on the sign-in screen (`Auth/AuthGateView.swift` → “Continue in Demo Mode”). No backend required.
- **App review template:** `notes/app_review_notes_template.md` (fill before submission with contacts, demo creds, and review steps).
- **Data/History:** Single shared SwiftData container built in `AtlasApp.swift`; history CRUD in `Data/HistoryStore.swift`.
- **Stats/coverage:** Computed in `StatsStore.swift` + `MuscleCoverageScoring.swift` (shared with Stats tab and Friend compare).
