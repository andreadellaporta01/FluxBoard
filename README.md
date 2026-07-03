# FluxBoard — the FlutterCon demo app

> Compute-heavy Flutter Web dashboard demo comparing the default JavaScript build vs `--wasm` — from the talk *"The JavaScript Exit: Flutter Web Beyond JavaScript."*

A deliberately **compute-heavy** Flutter Web dashboard, built to show the difference
between the default JavaScript build and the `--wasm` build in the talk
*"The JavaScript Exit: Flutter Web Beyond JavaScript."* The heavy work is Dart on the
main thread (allocation/collection churn) — the workload where dart2wasm beats dart2js.

It's a fake real-time analytics dashboard:

- a **custom-painted candlestick chart** (160 candles + volume + 14-period moving average),
- a **heatmap** of 48×22 = 1,056 cells recomputed with trig every frame,
- a **5,000-row scrollable table**, each row with its own custom-painted sparkline,
- everything animating off one 60fps `Ticker`,
- a **frame overlay** (top-right) reading *real* engine timings via
  `SchedulerBinding.addTimingsCallback`. Hero = **measured FPS** (from frame cadence),
  with a **build** (UI/Dart thread — what dart2wasm speeds up) vs **raster** split as
  diagnostic, and a frame-interval bar graph (green = smooth, red = dropped). On the
  web the win shows up as **build dropping and FPS holding** — not as raster, which
  stays ~0.

A **Load 1×–40×** slider multiplies the per-frame Dart work (heatmap + 5k instruments)
so you can dial the jank up until the JS build drops below 60fps even on a fast machine.

> **Zero third-party dependencies** — pure Flutter. That's intentional: it means the
> whole app is Wasm-compatible with nothing to migrate, and `flutter build web` even
> prints *"Wasm dry run succeeded"*. Good line for the talk.

The renderer badge in the overlay reads `JS · CANVASKIT` or `WASM · SKWASM`,
driven by `const bool.fromEnvironment('dart.tool.dart2wasm')` — so the same code
labels itself correctly in both builds.

---

## Prerequisites

- Flutter 3.24+ (built and verified on 3.38.6 / Dart 3.10.7).
- Chrome / Chromium desktop (the only place Skwasm reliably runs as of mid-2026).
- Python 3 (for the local header-serving script). Optional: Firebase CLI for hosting.

```bash
flutter pub get
flutter analyze          # clean
flutter test             # smoke test
```

---

## The two builds

```bash
# 1) Default: compiles to JavaScript, runs CanvasKit.
flutter build web --release
#    → build/web/main.dart.js   (no .wasm)

# 2) The exit: compiles to WebAssembly (Skwasm), ships a JS fallback too.
flutter build web --wasm --release
#    → build/web/main.dart.wasm  AND  build/web/main.dart.js
```

Note after build (2): the output contains **both** `main.dart.wasm` *and*
`main.dart.js`. That's the JS fallback for non-WasmGC browsers — and the reason a
`--wasm` build's total wire size is usually **larger**, not smaller. Show the
`build/web` folder listing in the video; it makes the "Wasm ≠ smaller bundle" point
for you.

---

## Recording the demo (local, reliable — no conference wifi)

Multithreaded Skwasm needs cross-origin isolation, which needs two HTTP headers.
`serve.py` sets them and serves `build/web`.

```bash
# JS baseline (segment A of the video)
flutter build web --release
python3 serve.py            # → http://localhost:8000  (badge: JS · CANVASKIT)

# Wasm, multithreaded (segment B)
flutter build web --wasm --release
python3 serve.py            # → http://localhost:8000  (badge: WASM · SKWASM)
```

Verify multithreading is actually on: open Chrome DevTools console and run

```js
self.crossOriginIsolated   // must be true → SharedArrayBuffer available → Skwasm goes multi-threaded
```

If it's `false`, you're serving without the headers and Skwasm falls back to
**single-threaded** (still Wasm, just not the full win) — re-check you launched via
`serve.py`, not `flutter run`.

### Suggested capture beats (match slides 26–31)

1. **Segment A — JS build.** Badge `JS · CANVASKIT`. Load **40×**, scroll the 5k table
   while charts animate. Overlay: **~34fps · build ~26ms · ~89 dropped**, red bars.
   Build is the bottleneck; raster ~0 — it's Dart choking the main thread, not drawing.
2. **Segment B — Wasm build.** Same Load, same scroll (avoid clicking the controls —
   those are one-off `setState` spikes, not a perf signal). Overlay: **~60fps · build
   ~16.5ms · 0 dropped**, green. Same Dart, ~**1.6× faster** compiled to Wasm — enough
   to cross the 60fps line. The story is **execution speed** (build drops), NOT
   multithreading (raster is ~0 on web).
3. **Segment C (optional) — Network tab.** Reload with DevTools open; show
   `main.dart.wasm` downloading, and the `build/web` listing proving both the
   `.wasm` and the `.js` fallback shipped.

Tips: record at the projector's resolution; the overlay is legible from the back
row at 1080p+. Grab stills of each beat for the slide-deck fallback (slides 27–30).
Numbers vary by machine — capture on the same laptop you'll present from. Cite your
own measured **~1.6×** (build 26.6→16.5ms) plus the official Wonderous 2×/3×; don't
inflate beyond what the overlay shows.

---

## Hosting (if you'd rather demo a live URL)

Any host that lets you set response headers works. Config for two common ones is
included.

**Firebase Hosting** (`firebase.json` is in the repo):

```bash
flutter build web --wasm --release
firebase deploy --only hosting
```

**Netlify / Cloudflare Pages:** the `web/_headers` file is copied into `build/web`
automatically by `flutter build`, so the COOP/COEP headers ship with the deploy.
Publish directory: `build/web`.

**GitHub Pages:** can't set custom headers → no multithreaded Wasm (single-threaded
Skwasm still works). Fine for *this* demo — its win is execution speed, which doesn't
need multithreading; only heavy multithreaded-rendering apps would miss it.

> Live-URL caveat for the talk: `Cross-Origin-Opener-Policy: same-origin` breaks
> OAuth popups (`signInWithPopup`). FluxBoard has no auth, so it's a non-issue here —
> but it's the exact production gotcha called out on slide 49.

---

## Knobs

- **Load slider (1×–40×):** multiplies per-frame heatmap + 5k-instrument Dart work (build/CPU).
- `MarketData(loadMultiplier: N)` in `lib/ui/dashboard.dart` sets the startup default.
- `instrumentCount`, `heatCols/heatRows`, `candleCount` in `lib/data/market_data.dart`.

## Files

```
lib/main.dart              MaterialApp entry
lib/data/market_data.dart  in-place mutable state; allocation-heavy per-frame tick()
lib/ui/dashboard.dart      layout + 60fps Ticker + Load control + renderer badge
lib/ui/painters.dart       candlestick / heatmap / sparkline / ambient glow CustomPainters
lib/ui/frame_stats.dart    measured-FPS overlay + build/raster frame-timing collector
web/_headers               COOP/COEP for Netlify/Cloudflare (auto-copied into build)
firebase.json              COOP/COEP for Firebase Hosting
serve.py                   local static server that sets COOP/COEP
```
