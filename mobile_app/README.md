# Child Activities – Flutter app

Mobile client for the content-based activity recommender in this repository.
Parents and caregivers can:

- **Sign in** with email + password, or with Google.
- **Create child profiles** (name, birth date, interests) and edit or delete them.
- **See recommended activities** for each child, ranked by
  `backend/activity_recommender.py` using the child's age and interests, and
  narrow or widen the interests used for a search.
- **Rate** each activity (1–5 stars) and **add comments** on how it went.

```
lib/
  main.dart                      app entry, theme, auth gate
  config.dart                    API URL + Google client IDs (--dart-define)
  constants.dart                 interest list, age formatting
  models/                        caregiver, child, activity, feedback
  services/api_client.dart       typed client for backend/Api.py
  services/auth_service.dart     session state, secure token storage, Google
  screens/login_screen.dart      sign in / create account / Google
  screens/children_screen.dart   list of child profiles (home)
  screens/child_profile_screen.dart     create / edit / delete a profile
  screens/recommendations_screen.dart   recommended activities + quick rating
  screens/activity_detail_screen.dart   activity details, rating, comments
```

## 1. Run the backend

From the repository root:

```bash
pip install -r backend/requirements.txt

# Database, once, in this order:
psql "$DATABASE_URL" -f sql/schema.sql
psql "$DATABASE_URL" -f sql/children_schema.sql
psql "$DATABASE_URL" -f sql/feedback_schema.sql
python backend/activity_recommender.py ingest Child-Activity-Data-Filled.csv

export JWT_SECRET="a-long-random-string"
export GOOGLE_CLIENT_IDS="<web-client-id>.apps.googleusercontent.com"   # for Google sign-in
uvicorn backend.Api:app --reload --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` lets a phone on the same Wi-Fi reach the server.

## 2. Run the app

```bash
cd mobile_app
flutter pub get
flutter run                                    # emulator/simulator, local backend
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000   # physical device
```

Default API URL: `http://10.0.2.2:8000` on the Android emulator (the host
machine), `http://localhost:8000` elsewhere.

## 3. Google sign-in setup

Email/password works without any of this. For Google:

1. In Google Cloud Console → *APIs & Services → Credentials*, create OAuth
   client IDs:
   - **Web application** – its ID is the *server client ID*.
   - **Android** – package `com.cbfrecommender.child_activities` plus the
     SHA-1 of your signing key (`cd android && ./gradlew signingReport`).
   - **iOS** (if building for iOS) – bundle ID from `ios/Runner.xcodeproj`.
2. Backend: set `GOOGLE_CLIENT_IDS` to the web client ID (comma-separate the
   iOS client ID too if you don't pass a server client ID on iOS).
3. App: pass the IDs at build time:
   ```bash
   flutter run \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com \
     --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com
   ```
4. iOS only: in `ios/Runner/Info.plist`, replace
   `com.googleusercontent.apps.REPLACE_WITH_IOS_CLIENT_ID` with your iOS
   client's *reversed* client ID.

The app sends Google's ID token to `POST /auth/google`; the backend verifies it
and links it to an existing account with the same (verified) email, or creates
a new one.

## Tests

```bash
flutter analyze
flutter test
```

## Production notes

- The Android manifest allows plain HTTP (`usesCleartextTraffic`) and iOS
  allows local-network HTTP so the app can reach a development server. Serve
  the API over HTTPS and remove these before release.
- Always set `JWT_SECRET` on the server; the default is for development only.
