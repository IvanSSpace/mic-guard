# Brand-specific device icons from Simple Icons — feasibility research

Researched 2026-08-20. Scope: can MicGuard show brand logos (Sony, Sennheiser, JBL, Bose, etc.)
next to matched device names, sourced from [simple-icons/simple-icons](https://github.com/simple-icons/simple-icons),
given the project's constraints (plain `swiftc` build via `build.sh`, no `.xcodeproj`, no SPM, zero
dependencies)?

## Verdict

**Easy. No conversion step is required.** macOS's AppKit has been able to load a raw `.svg` file
straight into an `NSImage` — no Asset Catalog, no `actool`, no third-party SVG library — since at
least **macOS 14.0 Sonoma** (2023), and it still works exactly the same way on macOS 26.2 (verified
live on this machine today, see §1). Simple Icons ships nothing but raw `.svg` files under CC0-1.0,
and its per-file sizes are trivial (hundreds of bytes to ~7 KB each). The whole feature is: vendor a
handful of `.svg` files into the repo, add two lines to `build.sh` to copy them into
`Contents/Resources`, and call `NSImage(contentsOf:)` at runtime with a nil-fallback to the existing
SF Symbol.

Two corrections to the brief worth flagging up front:

- **License is CC0-1.0, not MIT.** Simple Icons' own `package.json` and `LICENSE.md` both say CC0-1.0
  (see §3). This is actually more permissive than MIT for this use (no attribution requirement), but
  the doc/PR description should say the right name.
- **Shure and Rode are not in Simple Icons.** A full-text search of the current icon dataset
  (`data/simple-icons.json`, 3,453 icons) found no entry for either brand — not under `Shure`, `Rode`,
  or `Røde`. Of the 11 brands listed in the task, only **9 are actually available**: Sony, Sennheiser,
  JBL, Bose, Audio-Technica, HyperX, Razer, Corsair, Elgato. (fifine, Blue Yeti, Beyerdynamic were
  already correctly identified as absent.)

The one real caveat: this SVG-loading behavior is **undocumented by Apple** (absent from the official
`NSImage` reference and from the AppKit release notes) and is implemented via a private
`_NSSVGImageRep` class. It has been reliable since Sonoma in practice, but MicGuard's
`Info.plist` declares `LSMinimumSystemVersion` 13.0 (Ventura), one major version before the earliest
confirmed-working release — so the code must treat the load as optional and fall back to the current
SF Symbol, which it would need to do anyway for unmatched device names.

---

## 1. Rendering path: does macOS have a native way to load raw SVG?

**Yes, empirically confirmed — but undocumented.**

I tested this live on the actual machine (macOS 26.2, Build 25C56, Swift 6.2.3 — confirmed via
`sw_vers`) rather than relying on secondhand claims. I downloaded `sony.svg` from the real
simple-icons repo and compiled a small AppKit test program against it:

```swift
NSImage(contentsOfFile: path)   // -> LOADED, size=(24.0, 24.0), rep type: _NSSVGImageRep
NSImage(contentsOf: url)        // -> LOADED, size=(24.0, 24.0), rep type: _NSSVGImageRep
NSImage(data: svgData)          // -> LOADED, size=(24.0, 24.0), rep type: _NSSVGImageRep
NSImage.imageTypes.contains("public.svg-image")            // -> true
NSImage.imageUnfilteredTypes.contains("public.svg-image")  // -> true
CGImageSourceCreateWithURL(url, nil)                        // -> nil (ImageIO does NOT support SVG)
```

All three standard `NSImage` initializers load the raw SVG directly and report the correct
intrinsic size taken from the SVG's `viewBox`. `NSImage.imageTypes` (the list of UTIs AppKit's image
loading machinery accepts) already includes `public.svg-image` — this is a real, if privately backed,
image representation, not a lucky no-op.

Note the asymmetry: **`CGImageSourceCreateWithURL` (ImageIO) returns nil for the same file.** SVG
support lives in AppKit's `NSImage` loading path specifically, not in the lower-level ImageIO/Core
Graphics stack. So this only helps for `NSImage`/`Image(nsImage:)`, not for anything built on
`CGImageSource` or `CIImage`.

**When did this appear, and is it official?**

- The official [`NSImage` Apple Developer Documentation page](https://developer.apple.com/documentation/appkit/nsimage)
  contains **zero mentions of "SVG"** anywhere in its content (confirmed by fetching Apple's own
  documentation JSON payload and grep'ing it) — Apple has not documented this capability on the class
  reference.
- The [AppKit Release Notes for macOS 12](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-12)
  and [AppKit Release Notes for macOS 14](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)
  also contain no mention of SVG (same JSON-payload check) — it was never announced as a feature.
- The earliest first-hand confirmation is an [Apple Developer Forums thread](https://developer.apple.com/forums/thread/740218),
  "NSImage with SVG support - official?" (Oct 2023): a developer reports *"I just tried on macOS 14.0
  Sonoma to load SVG and it works. There is no parity on iOS17."*, loading a raw SVG string via
  `NSImage(data:)` and getting back `RepProvider=<NSImageArrayRepProvider: ..., reps:("_NSSVGImageRep
  ...")>`. A follow-up reply (Nov 2024) confirms macOS 15 Sequoia works the same way, iOS 18 still
  returns `nil`. **No Apple engineer/DTS reply appears in the thread** — the question of official
  status is left open by Apple itself.
- My own test today adds macOS 26.2 as a third confirmed-working data point, with the same private
  `_NSSVGImageRep` backing.

**Practical read:** this is a real, working, zero-dependency capability on macOS (not iOS), available
at least from macOS 14.0 Sonoma onward, but it is an implementation detail AppKit happens to expose
through the public `NSImage` initializers rather than a committed public API. Given MicGuard's
`LSMinimumSystemVersion` is 13.0, code must not assume it always succeeds — always guard with
`if let` and fall back to the SF Symbol icon (which the code needs anyway for non-matched devices).

Asset-catalog SVG support (via Xcode's `actool`, "Preserve Vector Data") is a separate, older, and
better-documented mechanism — added in Xcode 12 for deployment targets of macOS 10.15+ — but it
requires an `.xcassets` catalog compiled by `actool`, which this project deliberately doesn't have.
It's not relevant here since the raw-file path works without it.

---

## 2. Simple Icons asset format & the simplest pipeline

**The repo ships only raw `.svg` files — no PDF, no PNG, nothing else.**

Verified via the GitHub API listing of the `icons/` directory
(`api.github.com/repos/simple-icons/simple-icons/contents/icons?ref=develop`): every one of the first
1,000 entries has extension `svg`, no other extension appears. The [repo root](https://github.com/simple-icons/simple-icons)
confirms the same — `icons/` (SVGs), `data/simple-icons.json` (metadata: title, hex color, source URL,
optional guidelines/license/aliases), plus JS/TS build tooling. No PDF or PNG assets are published or
needed by consumers; PNG/other formats are something *consumers* generate themselves if they want
them (e.g. via the `cdn.simpleicons.org` web service, which is not relevant to an offline macOS app).

**Given §1, no conversion step is required at all.** The simplest viable pipeline is:

1. Download the chosen `.svg` files from `https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/<slug>.svg`
   and commit them into the repo (e.g. `Resources/BrandIcons/sony.svg`).
2. Add 1-2 lines to `build.sh` to copy that directory into `Contents/Resources/BrandIcons` alongside
   the existing `cp Info.plist ...` line — no `actool`, no asset catalog.
3. At runtime, resolve via `Bundle.main.url(forResource:withExtension:subdirectory:)` and load with
   `NSImage(contentsOf:)`.

No `rsvg-convert`, no `cairosvg`, no Inkscape, no Homebrew install of anything is needed for the
primary path.

**Fallback path, if they want a rasterized PNG for extra safety** (e.g. to also support macOS 13
Ventura where SVG loading is unconfirmed, or to avoid depending on the private `_NSSVGImageRep`
class at all): both `sips` and `qlmanage`, which ship with every Mac, already handle SVG input on
this machine — tested directly:

```
sips -s format pdf -o sony.pdf sony.svg      # -> works, produced a 4.9 KB PDF
sips -s format png -o sony.png sony.svg      # -> works, produced a 405-byte PNG (default size)
qlmanage -t -s 48 -o . sony.svg              # -> works, produced sony.svg.png (Quick Look thumbnail)
```

(Older write-ups from ~2019-2023 claim `sips` doesn't support SVG input at all — that appears to have
been fixed at some point; it works today. `qlmanage -t` has been the long-standing documented
community trick and also still works, with the caveat that it doesn't handle transparency well for
non-square art.) Either tool would let `build.sh` rasterize to 1x/2x/3x PNGs at build time with zero
new dependencies, purely as a belt-and-braces option — but it's not needed for the recommended path.

---

## 3. License terms

**Repo-wide license: CC0-1.0** (not MIT — correction to the task brief). Confirmed three ways:

- `package.json` at repo root: `"license": "CC0-1.0"`.
- `LICENSE.md` at repo root is the verbatim **CC0 1.0 Universal** public domain dedication text,
  fetched directly from `raw.githubusercontent.com/simple-icons/simple-icons/develop/LICENSE.md`.
  Key clauses:
  > "Certain owners wish to permanently relinquish those rights to a Work for the purpose of
  > contributing to a commons of creative, cultural and scientific works ("Commons") that the public
  > can reliably and without fear of later claims of infringement build upon, modify, incorporate in
  > other works, reuse and redistribute as freely as possible..."
  >
  > "4. Limitations and Disclaimers. i. No trademark or patent rights held by Affirmer are waived,
  > abandoned, surrendered, licensed or otherwise affected by this document."
  >
  > "ii. Affirmer offers the Work as-is and makes no representations or warranties of any kind
  > concerning the Work..."

  There is **one license for the whole package** (code + SVG data) — no separate license for the
  icon artwork vs. the tooling.

- Per-icon overrides exist in principle (the JSON schema supports a `"license"` field per icon,
  separate from CC0, for icons whose actual source material carries different terms), but **none of
  the 9 available target brands (Sony, Sennheiser, JBL, Bose, Audio-Technica, HyperX, Razer, Corsair,
  Elgato) have a `license` field set** in `data/simple-icons.json` — confirmed by pulling and
  filtering the actual JSON. So all 9 fall under the default CC0-1.0 declaration for the SVG path
  data.

**Trademark caveat — quoted verbatim from [`DISCLAIMER.md`](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md)**
(fetched directly, not paraphrased):

> "Simple Icons is released under CC0 - though that doesn't mean to imply that all icons within the
> project are also CC0. Please see individual licenses where available."

> "If an icon includes a registered trademark (`®`) or trademark symbol (`™`) the recommendations
> outlined in [the Simple Icons Contributing Guidelines] are followed to decide whether to include
> the symbol or not."

> "Simple Icons cannot be held responsible for any legal activity raised by a brand, or users of the
> package. We ask that our users seek the correct permissions to use the icons relevant to their
> project."

And from `DISCLAIMER.md`'s "Brand Guidelines" section:

> "Simple Icons provides a link to a brand's *branding guidelines* (or similar) if the brand provides
> one. We ask our users read these guidelines and ensure their usage of the brand's icon is in
> accordance with them."

`CONTRIBUTING.md` (fetched directly) adds the enforcement mechanism behind this: an "Icon Guidelines"
section describing exactly when the ® or ™ symbol must be drawn into the path data based on each
brand's own guidelines, and a "Requesting Permission" section:

> "If a brand's terms and conditions state that we need permission to include their brand, we will
> tag related issues and PRs with `permission required`."

Practically: the SVG *artwork* (the specific path data Simple Icons drew) is CC0 — free to use, no
attribution needed, no permission needed from Simple Icons. The **brand names/logos themselves remain
each company's trademark**, same as they would if MicGuard drew its own vector logos from scratch.
Using a small monochrome/brand-accurate logo next to a device name to identify hardware you're
actually detecting (nominative use — "this is a Sony device," not "MicGuard is endorsed by Sony") is
the same low-risk category every icon pack / app that shows OEM device icons already relies on. Two of
the 9 target icons (Bose, Corsair) have a `guidelines` URL on file pointing to the brand's own
logo/press page, which is worth a quick skim before shipping if being maximally careful.

---

## 4. Size impact

Real numbers, not estimates — fetched the actual files via `curl -I` (Content-Length) against
`raw.githubusercontent.com/.../icons/<slug>.svg`:

| Brand | Slug | Raw SVG size |
|---|---|---|
| Sony | `sony` | 2,745 B |
| Sennheiser | `sennheiser` | 427 B |
| JBL | `jbl` | 996 B |
| Bose | `bose` | 1,377 B |
| Audio-Technica | `audiotechnica` | 514 B |
| HyperX | `hyperx` | 814 B |
| Razer | `razer` | 7,200 B (largest — most detailed path) |
| Corsair | `corsair` | 766 B |
| Elgato | `elgato` | 838 B |
| **Total (9 icons)** | | **~15.7 KB** |

Extrapolated to 12-15 icons (if a few more brands get added later), expect roughly **20-30 KB total**
raw SVG — each file is a single `<path>` element with no embedded raster data, so size scales with
logo geometric complexity, not resolution (these are resolution-independent).

If instead rasterizing to PNG at 1x/2x/3x for a 16pt row icon (16px/32px/48px), measured directly via
`qlmanage -t`:

| Brand | 16px | 32px | 48px | 3-size total |
|---|---|---|---|---|
| Sony | 386 B | 741 B | 1,184 B | 2.3 KB |
| JBL | 535 B | 892 B | 1,271 B | 2.7 KB |
| Razer | 635 B | 1,620 B | 2,596 B | 4.7 KB |

Average ≈ 3.2 KB per icon for a full 1x/2x/3x PNG set → roughly **30-50 KB for 9-15 icons**.

Either way this is noise: MicGuard's compiled binary itself and the rest of the app bundle will
dwarf this by orders of magnitude. The SVG-only, no-rasterization path is both simpler to implement
and smaller on disk.

---

## If we do this: concrete steps

1. **Pick the icon set.** Available now (9): `sony`, `sennheiser`, `jbl`, `bose`, `audiotechnica`,
   `hyperx`, `razer`, `corsair`, `elgato`. Drop Shure and Rode from the plan — not in Simple Icons.
   (Optional: watch simple-icons for future additions — Shure/Rode could get added later since Simple
   Icons accepts brand requests via issues.)

2. **Vendor the SVGs.** Download each from
   `https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/<slug>.svg` and commit
   into e.g. `Resources/BrandIcons/<slug>.svg`. Note the simple-icons commit/version pulled from, for
   future updates (CC0 needs no attribution, but noting provenance is good hygiene given their own
   "Update of Brands" process for when logos change).

3. **Bundle them at build time.** In `build.sh`, alongside the existing
   `cp Info.plist "$APP_BUNDLE/Contents/Info.plist"` line, add:
   ```bash
   mkdir -p "$APP_BUNDLE/Contents/Resources/BrandIcons"
   cp Resources/BrandIcons/*.svg "$APP_BUNDLE/Contents/Resources/BrandIcons/"
   ```
   No `actool`, no asset catalog compile step.

4. **Load at runtime with a nil-safe fallback.** In `DeviceRow` (`Sources/MicGuard/main.swift`),
   add a brand-matching layer ahead of the existing transport-based `icon` computed property:
   ```swift
   private var brandImage: NSImage? {
       let name = device.name.lowercased()
       let brands: [(needle: String, slug: String)] = [
           ("sony", "sony"), ("sennheiser", "sennheiser"), ("jbl", "jbl"),
           ("bose", "bose"), ("audio-technica", "audiotechnica"), ("audio technica", "audiotechnica"),
           ("hyperx", "hyperx"), ("razer", "razer"), ("corsair", "corsair"), ("elgato", "elgato"),
       ]
       guard let match = brands.first(where: { name.contains($0.needle) }),
             let url = Bundle.main.url(forResource: match.slug, withExtension: "svg",
                                        subdirectory: "BrandIcons")
       else { return nil }
       return NSImage(contentsOf: url)   // nil on macOS < 14 or any load failure — caller falls back
   }
   ```
   In `body`, swap `Image(systemName: icon)` for a check: `if let brandImage { Image(nsImage:
   brandImage) } else { Image(systemName: icon) }` — same 16pt frame either way.

5. **Sanity-check rendering at 16-20pt** before shipping: these SVGs are brand-colored/black
   silhouettes, not SF Symbol template images, so they won't auto-tint for dark/light menu bar
   backgrounds the way the current SF Symbols do. Glance at each of the 9 in both appearances; accept
   as-is (common pattern — Slack/Discord-style brand chips) or add a subtle background circle if
   contrast is an issue on any one of them.

6. **Skip the PNG/PDF conversion step entirely** for the initial version — it's not needed given §1.
   Keep `sips -s format png` / `qlmanage -t` in your back pocket only if you later decide to support
   macOS 13 Ventura with guaranteed rendering (untested for SVG loading) or want to stop depending on
   the private `_NSSVGImageRep` class altogether.

## Sources

- [`NSImage` — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsimage)
- [AppKit Release Notes for macOS 12](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-12)
- [AppKit Release Notes for macOS 14 (Sonoma)](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)
- [Apple Developer Forums: "NSImage with SVG support - official?"](https://developer.apple.com/forums/thread/740218)
- Live empirical test on this machine: macOS 26.2 (Build 25C56), Swift 6.2.3, compiled AppKit test program against a real simple-icons SVG
- [simple-icons/simple-icons](https://github.com/simple-icons/simple-icons) — repo root, `package.json`, `data/simple-icons.json`, GitHub Contents API listing of `icons/`
- [simple-icons `LICENSE.md`](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md)
- [simple-icons `DISCLAIMER.md`](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md)
- [simple-icons `CONTRIBUTING.md`](https://github.com/simple-icons/simple-icons/blob/develop/CONTRIBUTING.md)
- File sizes: `curl -I` against `raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/*.svg`, and local `sips`/`qlmanage` rasterization tests on this machine
