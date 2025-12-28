# Repository Guidelines

## Project Structure & Module Organization
- `*.html` in the repo root are individual demo entrypoints (open them in a browser).
- `js/` contains shared runtime code (for example `InitCommon.js`, `PathTracingCommon.js`) plus per-demo scripts (for example `js/Cornell_Box.js`).
- `shaders/` contains GLSL, typically `*_Fragment.glsl` paired with a demo.
- Assets live in `models/`, `textures/`, `css/`, and `readme-Images/`.

## Build, Test, and Development Commands
This is a static, browser-run project (ES modules + import maps). Serve the repo root over HTTP instead of using `file://`.

- `python3 -m http.server 8080` — start a local server, then open `http://localhost:8080/Cornell_Box.html`
- `npx http-server -p 8080` — alternative Node-based static server

## Coding Style & Naming Conventions
- Match existing formatting (tab-indented JS/HTML, minimal reformatting).
- Keep demo files aligned: `Demo_Name.html` ↔ `js/Demo_Name.js` ↔ `shaders/Demo_Name_Fragment.glsl`.
- Prefer browser-friendly JavaScript (no Node-only APIs); vendored deps live under `js/` (for example `js/three.module.min.js`).

## Testing Guidelines
There is no automated test suite in this repo. Validate changes by:
- Loading the affected demo pages and watching the browser console for errors (especially shader compile issues).
- Checking for visual regressions (camera controls, sample accumulation, lighting/material changes) and obvious performance drops.

## Commit & Pull Request Guidelines
- Follow existing history: short, imperative subjects (for example `Update Classic_Torus.js`, `update three.js to r181`).
- PRs should include: a clear description, the list of affected demos, and screenshots/GIFs or a short recording for visual changes.
- If adding/altering assets, note the source and license and keep file sizes reasonable.

## Agent-Specific Notes (Optional)
- Prefer `rg` for searching and avoid sweeping formatting-only diffs.
- If CI exists on your fork/PR, watch checks with `gh pr checks <number> --watch --interval 5 --required`.
- When a rebase prompts for an editor, use `GIT_EDITOR=true git rebase --continue`.
