<div align="center">
  <h3>Last.fm for YouTube Music (iOS)</h3>
  <p>Last.fm Now Playing and Scrobbling tweak for the YouTube Music iOS app.</p>
</div>

---

## Overview

- **Companion-mode by default:** `Sideload.x` is excluded from the default build so the tweak can be injected alongside **YTMusicUltimate** without double-hooking keychain/bundle-ID selectors or crashing on launch.
- **Guarded player state polling:** Reads `contentVideoID`, `currentVideoMediaTime`, and `currentVideoTotalMediaTime` from `YTPlayerViewController` using selector-checked KVC and `MLHAMPlayerItem` state hooks.
- **Dual metadata resolution:** Reads track, artist, album, and duration from `MPNowPlayingInfoCenter` first (supporting featured artists and user-uploaded library tracks), falling back to YouTube's oEmbed API. Includes an in-app toggle to prefer oEmbed (`Accept-Language: en-US`) for unlocalized titles.
- **Last.fm API spec compliance:**
  - Tracks must be **> 30 seconds** and played for at least **min(50% duration, 240 seconds)** of accumulated play time (pauses and forward seeks do not count).
  - Persistent offline scrobble queue (`NSDocumentDirectory/lfm_scrobble_queue.plist`) flushes in batches of up to 50 oldest-first and drops entries older than 14 days.
  - All network requests run asynchronously on a serial background queue (`com.lfm.net`).
- **In-app Settings UI:** Accessible from the YouTube Music account menu (`Last.fm Scrobbler`).

---

## Requirements

- Last.fm API key & shared secret (<https://www.last.fm/api/account/create>, callback URL `http://localhost:3000`)
- [Theos](https://theos.dev) (for local builds) or GitHub Actions with repository secrets

---

## Building

### Local Build (Companion Mode — Default)

```bash
make clean package FINALPACKAGE=1 \
  LASTFM_API_KEY=your_api_key \
  LASTFM_API_SECRET=your_api_secret
```

The resulting rootless `.deb` is written to `packages/`.

### Standalone Sideload Mode (Optional)

Only use when injecting **without** YTMusicUltimate:

```bash
make clean package FINALPACKAGE=1 \
  SIDELOAD_FIXES=1 \
  LASTFM_API_KEY=your_api_key \
  LASTFM_API_SECRET=your_api_secret
```

### GitHub Actions Build

1. Add repository secrets under **Settings → Secrets and variables → Actions**:
   - `LASTFM_API_KEY`
   - `LASTFM_API_SECRET`
2. Push to `main` or run **Build and Release Tweak** from the **Actions** tab to build the rootless `.deb` and publish a GitHub Release.

---

## Licensing

GPL-3.0-or-later. See [LICENSE](/LICENSE).
