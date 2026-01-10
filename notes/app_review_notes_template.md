## App Review Notes (Template)

Fill the placeholders before submitting to App Store Connect.

### Contact
- Name: <review contact name>
- Email: <review contact email>
- Phone (optional): <review contact phone>

### How to review (fresh install)
1. Launch the app (no account required for demo).
2. On the sign-in screen, tap **Continue in Demo Mode** to enter read-only demo.
3. Explore:
   - Home: calendar + start workout pill.
   - Stats: Week/Month/All-time toggle updates cards.
   - Routines: Open a routine, start a session, log a few sets.
   - Friends: UI visible; networking features require auth.
4. Coach Chat (optional): open Muscle Coverage detail → tap a muscle → chat. If the OpenAI key is missing, you’ll see a graceful fallback message.

### Demo credentials (if you want to test Supabase auth)
- Email: <demo email>
- Password: <demo password>

### Feature flags / toggles
- Demo Mode: available on the sign-in screen; no backend required.
- AI: requires `OPENAI_API_KEY` in LocalSecrets/Info.plist; absent → fallback text.

### Permissions
- None requested at launch. App does not access location, camera, microphone, photos, or Health data.

### Known limitations
- Friends actions require a valid Supabase backend session.
- If network is unavailable, AI replies fall back to local suggestions; stats use on-device history only.

### Export/Encryption
- Uses standard HTTPS only; no custom encryption.
