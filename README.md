# SpotifyMe (iOS)

An iPhone app that reads your Spotify listening history and builds mood playlists, then saves them to your Spotify account:

| Mood | What it picks | Order |
|---|---|---|
| **Slow Down** | 60–100 BPM, low energy, acoustic-leaning | Winds down: calmest track last |
| **Speed Up** | 100–150 BPM, energy ≥ 0.6 | Tempo and energy climb |
| **Running 180 bpm** | 175–185 BPM, or 87–93 BPM (half-time); energy ≥ 0.65 | Gentlest tracks first and last |
| **Running 170 bpm** | 165–175 BPM, or 82–88 BPM (half-time); energy ≥ 0.65 | Same as above |
| **Feeling Good** | Positivity (valence) ≥ 0.65, energy 0.5–0.85, danceability ≥ 0.6 | No artist twice in a row |
| **Surprise Me** | ~40% "forgotten favorites" (all-time top tracks you haven't played lately) + ~60% new recommendations | Shuffled |

Each playlist has about 30 tracks, with at most 2 per artist. For a running mood, if there aren't enough tracks at ±5 BPM, the window widens to ±8 BPM. If your own tracks don't fill a mood's playlist (30 tracks, or a custom mood's track count), the app fetches recommendations aimed at that mood's tempo, energy and positivity and fills the remaining slots with the ones that fit best, even if they miss a strict rule. They're labeled **Recommended** in the track list. Spotify no longer offers recommendations to new apps, so these come from ReccoBeats, seeded with your Spotify tracks. Saving a mood again **updates the same playlist** rather than creating a duplicate.

## How it works

```
Spotify (your history) ──► track pool ──► audio features ──► mood rules ──► save playlist to Spotify
  top tracks (3 ranges)                    1. ReccoBeats (tempo, energy, valence, …)
  recently played                          2. GetSongBPM (BPM only; running moods)
  Liked Songs (200)                        3. Deezer by ISRC (BPM only; running moods)
  top artists → search
  ReccoBeats recommendations
```

Spotify no longer gives new apps tempo/mood data (audio features) or recommendations. Those were removed in November 2024, so this app gets them from the free services above. Results are cached on the device (`features.json` in Application Support), so each track is only looked up once.

### Project layout

```
project.yml                        XcodeGen project definition
Config.example.xcconfig            copy to Config.xcconfig and add your keys
SpotifyMe/                         the iOS app (SwiftUI, iOS 17+)
  App/        app entry, config, shared state
  Auth/       Spotify sign-in (authorization code + PKCE), Keychain token storage
  Views/      mood grid, playlist preview/save, about
Packages/SpotifyMeCore/            Swift package with all non-UI logic
  Models/     Track, AudioFeatures, Mood
  Engine/     MoodEngine (mood rules), PlaylistService, FeatureCache
  API/        Spotify, ReccoBeats, GetSongBPM, Deezer clients
  Tests/      unit tests for the mood rules
```

## Setup

You need a Mac with Xcode 16 or later.

1. **Create a Spotify app** at <https://developer.spotify.com/dashboard>:
   - Redirect URI: `spotifyme://callback`
   - API: tick **Web API**
   - Copy the **Client ID**. No client secret is needed: the app uses PKCE.
   - Under **User Management**, add the Spotify email address of everyone who will use the app (including yourself).
2. *(Optional)* Get a free GetSongBPM API key at <https://getsongbpm.com/api>. It improves BPM coverage for the running moods.
3. Configure:
   ```sh
   cp Config.example.xcconfig Config.xcconfig
   # edit Config.xcconfig: SPOTIFY_CLIENT_ID, GETSONGBPM_API_KEY, DEVELOPMENT_TEAM, APP_BUNDLE_ID
   ```
4. Generate the Xcode project and open it:
   ```sh
   brew install xcodegen
   xcodegen generate
   open SpotifyMe.xcodeproj
   ```
5. Choose your iPhone or a simulator and press **Run**.

On first launch the app asks for a **Spotify Client ID** (and an optional GetSongBPM key) and stores them on the device, so each person can use their own Spotify developer app. You can change them later under **About → Change Client ID or API keys**. Values in `Config.xcconfig` are optional and only act as defaults.

Run the unit tests with `swift test` in `Packages/SpotifyMeCore`, or with ⌘U in Xcode.

## Continuous integration

`.github/workflows/ios.yml` runs the unit tests and builds the app for the iOS Simulator on every push. It needs no setup.

## Install on your iPhone with TestFlight (no Mac needed)

`.github/workflows/testflight.yml` signs the app and uploads it to TestFlight. It needs a paid Apple Developer Program membership ($99/year). There are four one-time steps.

### 1. Register the app with Apple
1. In [Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list), click **+**, choose **App IDs → App**, and register an explicit Bundle ID, e.g. `com.yourname.spotifyme`.
2. In [App Store Connect → Apps](https://appstoreconnect.apple.com/apps), click **+ → New App**:
   - Platform: iOS
   - Name: e.g. "SpotifyMe Personal". The name must be unique on the App Store, and Apple may reject names containing "Spotify".
   - Bundle ID: the one you just registered
   - SKU: anything, e.g. `spotifyme`

### 2. Create an App Store Connect API key
In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api), click **Generate API Key**.
- Give it **Admin** access. Admin is needed so the build can create signing certificates in Apple's cloud; with lower access, the archive step fails with a signing error.
- Download the `.p8` file. Apple only lets you download it once.
- Note the **Key ID** and the **Issuer ID**, which is shown above the list of keys.

Your **Team ID** is under [Membership details](https://developer.apple.com/account#MembershipDetailsCard).

### 3. Add GitHub secrets
In GitHub, go to **Settings → Secrets and variables → Actions**.

**Secrets** tab:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `ASC_KEY_ID` | the API key's Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_PRIVATE_KEY` | the full contents of the `.p8` file, including the `BEGIN`/`END` lines |
| `SPOTIFY_CLIENT_ID` | your Spotify app's Client ID |
| `GETSONGBPM_API_KEY` | *(optional)* your GetSongBPM key |

**Variables** tab:

| Variable | Value |
|---|---|
| `APP_BUNDLE_ID` | the Bundle ID from step 1 |

### 4. Run it
1. Go to **Actions → Upload to TestFlight → Run workflow**. You can also push a tag such as `v1.0.1`.
2. After about 10 minutes, plus Apple's processing time, the build appears under **App Store Connect → your app → TestFlight**.
3. Add yourself as an **internal tester**. Internal testing needs no Apple review.
4. Install the **TestFlight** app on your iPhone and accept the invite.

Each run gets a new build number (the GitHub run number). TestFlight builds expire after 90 days, so run the workflow again for a fresh one.

## Spotify limits to know about

Since February/March 2026, apps in Spotify's **Development Mode** have these restrictions:
- The app owner needs an active **Spotify Premium** subscription.
- At most **5 authorized users** per app, added under User Management.
- One Development Mode Client ID per developer.
- Some endpoints were removed or renamed. The app already uses the new ones:
  - `POST /me/playlists` to create playlists
  - `/playlists/{id}/items` to change playlist contents
  - Search instead of the removed "artist top tracks" endpoint

If saving a playlist fails with a 400 or 403 error, check Spotify's
[February 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
and compare the request body in `SpotifyAPI.replacePlaylistItems` (`{"uris": [...]}`).

## Third-party data terms

- **ReccoBeats**: free, no key, rate-limited. The app waits and retries automatically.
- **GetSongBPM**: free, but a visible link back to GetSongBPM.com is **required**. It's on the About screen.
- **Deezer**: free public catalog lookups. A BPM of 0 means "unknown" and is ignored.
