# The Yantra shell — plan (2026-09-28)

Yantra is the whole desktop. On Yantra OS (Linux) it is the session; on Windows it runs fullscreen
on top. Values (look, motion, binds, bar modules, OS features) come from `PLAN.md` (this plan).

## Screen (2026-09-29: the Owner asked for a genuine desktop to macOS standards)

Default: a thin translucent menu bar (Yantra menu with Exit, the focused app's name, the space;
right: spaces in use, tiling, sidebar, Spotlight, agent, date and time), a centred dock (app
icons with running dots, minimised windows, Launchpad), windows with traffic lights that float by
default and tile with one toggle, Spotlight with keyboard selection, Launchpad, an optional
sidebar (windows and folders), a calm wallpaper. One system-blue accent, used for selection only.
Every surface stays a toggle; other layouts (the earlier sidebar/dock designs) become presets.

## Windows
Keyboard tiling (Dusky binds) and mouse floating (drag, title bars); one-click toggle per desktop,
per-window override. Apps may open several windows. Per-window rules: title bar / close button
or none, opacity, size, pin, keep on top.

## Everything is data
- Desktop profile (many, editable): theme + bar/sidebar design + rules + pins + binds.
- Theme: tokens (colours, fonts, radius, gaps, blur, bezier curves); later generated from wallpaper.
- Bar module: `modules/<name>.nim`, one fixed interface.
- OS feature: one `y_sys` call, Windows + Linux backends.

## Addresses: `y:`
`y:draw` (our servers), `y:draw.example.com` (any domain). Fetched, cached, hot-updated, run sandboxed.

## Passport (identity) and Warden (enforcement)
Passport is the pane: accounts, passkeys, sign-in to apps, per-app grants (files, network domains,
mic, camera, system controls, notifications, agent control), later payments. Warden is the host
side that enforces the grants. Apps list wanted grants in a signed manifest; first use asks.

## Agent (build later, design for now)
A system service: any API model or local (ggml); chat + voice; drives apps through AccessKit
trees + SDK actions; files, terminal, browser. Warden limits it. Rule now: every app and shell
feature exposes its actions and state machine-readably.

## Phases
1. Me: shell core — profiles/themes/modules, tiling + floating, multi-window, left pane, right dock, new tab page, power menu, control-centre UI, grants in `app.json`.
2. Flash: `y_sys` backends (wifi, bt, volume, brightness, battery, media, power, notifications).
3. Flash, my design: `y:` fetch/cache/signing, Passport + Warden.
4. Agent. 5. Yantra OS session. Always: Muse makes themes, bar designs, modules, apps.

## More decided (2026-09-28)
- Scale: user-made apps and games as a full Steam-level alternative; the platform must support a LOT (as much as the web, more).
- Websites are first-class tabs beside y: apps (native WebView: WebView2 on Windows, WebKitGTK on Linux), same pane, same tiling, same Passport grants. Open code base.
- Search bar = Spotlight (apps, y: addresses, tabs, commands, files, web). Tab groups are folders.
- Storage: settings/profiles/themes/layouts/pins are JSON files (human- and agent-editable, hot-reloaded); history/frecency/search indexes in SQLite in the host; app data in each app's sandboxed store. Every surface has its own toggles; presets are saved toggle sets.
- Files: apps never see the real file system — only folders/files granted in Passport, as handles; Warden enforces and logs every access; revocable; the agent obeys the same rules.
- Yantra shell (beats bash): commands are wasm apps with manifests; pipes carry typed data (tables/JSON/files); output can render as UI; every command permission-checked and logged; real Linux tools on Yantra OS behind the same grants.
- IDE mode: an app opens as blocks + graph nodes + assets (n8n-like, better), backed by a plain folder that agents read like any code; multi-user editing.

## Platform (2026-09-28)
- Addresses: `y:name` via our registry (short names, search); `y:app.example.com` from anyone's domain
  (`/.well-known/yantra.json`). We are not a gatekeeper.
- Manifest: name, version, icon, grants, content hashes of every file, publisher signature.
- Delivery: content-addressed files on a CDN, cached forever; compile while downloading; first frame
  first, assets on demand; compiled-module cache; prefetch on hover; background updates, hot swap.
- Trust: signatures, Warden grants, "verified" for reproducible builds from public source, revocation.
- Our servers: registry, publish (`yantra publish`), CDN, Passport accounts + E2E sync, optional app
  backend (db, realtime, files), later payments/payouts, crash reports.
- Social layer: our own X/Reddit-like network where people post and share everything on the Yantra
  web — apps, sites, games, videos, themes/desktops — with profiles, feeds, communities, comments.
  It is itself a Yantra app on the same platform.
- Stages: 1) JSON registry in git + static CDN + publish script; 2) real registry/publish service in
  Nim; 3) accounts, sync, backend, social, payments. The protocol is open.

## Library and registries (2026-09-29)
- Our own massive, AI-generated app library, made for Yantra: the default registry
  (github.com/Yantra-lab/yantra-web today).
- Users, companies and communities run their own registries (an index.json on any host) and apps
  on their own domains; the Library reads every registry the user added (Settings), Discover shows
  them side by side, labelled by source. Every app runs sandboxed, whoever made it.
