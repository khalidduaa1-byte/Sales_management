# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Production sales-tracking PWA for the Dolce & Gabbana Egypt Brand Ambassador (BA) team. **~20 BAs use it daily** across three teams: Cairo (Terminals 1/2/3 + seasonal), Sharm El Sheikh, and Hurgadah (Russian shop + European shop). Every change ships to live users — treat the `main` branch as production.

## Who uses this

- **~20 BAs in the field** (Egypt), roughly even split between iPhone and Android. PWA install paths differ — iOS users must use Share → Add to Home Screen; Android users get the install banner via `beforeinstallprompt`. Test on both before shipping install/UI changes.
- **Mostly on mobile data, no shop WiFi**. Connections can be slow or flaky. Avoid heavy assets, hidden retries, or features that assume always-online. Long synchronous Supabase queries on the BA side will feel broken.
- **Usage is spread across the day**, no clear peak — there's no "safe" deploy window. Push only when the change is verified locally, since any deploy can land mid-shift.
- **2 managers**: Duaa (primary, the user) and Rania. Test BA `duaa.khalid@dolcegabbana.it` exists and is excluded from the dashboard via `DASHBOARD_EXCLUDED_BA_NAME_KEYS` / `DASHBOARD_EXCLUDED_BA_IDS` in `manager.html`.

## Invariants

Hard rules. Violate any of these and live users break.

1. **The Supabase anon key and URL in `index.html`, `ba.html`, `manager.html` are public on purpose.** Security is RLS. Don't try to hide them, don't move them to a build-time env var — there is no build step.
2. **Never commit the service_role key, ever.** Not in code, not in a file, not in comments, not in this CLAUDE.md. Anything done with service_role lives in a script the user runs locally and discards.
3. **`sales_entries` rows from the BA app (`ba_id` populated) and from historical Excel imports (`ba_id` null) must not collide on the same date.** Excel is canonical up to day N of a month; BA app takes over from day N+1. Always count rows before and after any import.
4. **RLS on `profiles` has a history of `infinite recursion detected in policy` errors.** Don't write policies that select from `profiles` to authorize access to `profiles`. Test BA login AND manager login after any RLS change.
5. **`web_app/setup.sql` is the canonical schema.** Schema changes go there AND get a dated file in `web_app/sql/` for running on the live Supabase. Never edit live schema without updating setup.sql.

## Stack

- **Python ingestion** (pandas/openpyxl/plotly): one-shot scripts to parse supervisor Excel sheets and produce CSV for Supabase import.
- **Static HTML/JS PWA** under `web_app/`: no build step, no bundler — three pages share a single Supabase client via the `@supabase/supabase-js` CDN script tag.
- **Supabase Postgres** with Row Level Security: all auth, data, and authorization live there.
- **Vercel** auto-deploys from `main`. Live URL: `https://sales-management-phi-blue.vercel.app`. **Vercel project ID `prj_JLK7tYCTHu6wSJS2LQg7duDE6Lim` already exists — never create a new one.**

## Commands

```bash
# Python deps (one-time)
pip install -r requirements.txt

# Standalone HTML report from Excel (legacy/offline view, separate from the web app)
python dashboard.py
# → reads sales_data.xlsx in repo root, writes report.html

# Strict daily-grain importer — validates dates, blocks monthly-summary data
python import_daily_sales.py
python import_daily_sales.py --file other.xlsx --sheet "Sheet1"
# → writes normalized_daily_sales.csv for manual paste into Supabase

# Inspect Excel column headers before configuring config.py
python inspect_excel.py

# Serve the PWA locally (no build needed)
cd web_app && python -m http.server 8000
```

No test suite, no linter, no formatter. Deploy is `git push origin main` — Vercel handles the rest.

## Architecture in one diagram

```
Supervisor Excel ──► import_daily_sales.py ──► normalized_*.csv ──► (manually paste in Supabase SQL editor)
                                                                              │
                                                                              ▼
BA's phone (PWA) ──► ba.html (supabase-js) ──────────────────► Supabase Postgres ◄── manager.html
                                                                  ▲      RLS gates everything
                                                                  │
Manager (Duaa)   ──► manager.html (supabase-js) ──────────────────┘
```

**Two data paths feeding one table** (`public.sales_entries`):
1. **Historical**: Excel from supervisors → Python normalizer → CSV → manual Supabase import. Used for past months. `ba_id` is `null`; uniqueness falls back to `lower(ba_name)`.
2. **Live**: BAs enter sales in `ba.html` → directly inserted into Supabase via `supabase-js`. `ba_id` is populated.

These two paths **must not collide** for overlapping dates. See Invariant #3.

## Web app structure

All three HTML files include `@supabase/supabase-js@2` from CDN and instantiate one `sb = createClient(...)` with the public anon key (hardcoded — see Invariant #1).

- **`index.html`** — login + role router. After successful sign-in, queries `profiles.role` and redirects to `ba.html` or `manager.html`. Handles password-reset deeplinks (`detectSessionInUrl: true`).
- **`ba.html`** — BA-facing app: log sale (store + shift + amount + PCs), log attendance/leave, see own sales history + target progress + greeting. Egypt time (`Africa/Cairo`) for greetings.
- **`manager.html`** — manager dashboard (Duaa + Rania): KPIs, per-BA performance, targets/commissions, daily drill-down, BA profiles, missing-sales calendar, per-shop analytics. **~2700 lines of vanilla JS in one file by choice** — see Intentional non-choices.
- **`pwa.js`** + **`sw.js`** + **`manifest.webmanifest`** — installable PWA logic, including iOS "Add to Home Screen" hints and in-app-browser detection (WhatsApp/Instagram/FB can't install — `pwa.js` shows a hint to open in Safari instead).

## Database (Supabase)

Schema lives in `web_app/setup.sql` — the canonical source. Core tables:

- **`profiles`** — extends `auth.users` with `role` (`manager`|`ba`), `team`, `store`
- **`sales_entries`** — one row per BA per shift; `working_days` lets historical monthly rows carry a count instead of duplicating
- **`monthly_targets`** — manager-configurable per-team-per-month; `target_type` = `per_ba` (× active BAs) or `team_total`
- **`ba_attendance_entries`** — leave/off-day tracking; status ∈ `off_day | annual_leave | public_holiday | sick_leave | other`; unique `(ba_id, entry_date)`

Two uniqueness indexes on `sales_entries`: one for live BA-app rows (`ba_id, entry_date, store, shift`), one for legacy rows where `ba_id is null` (falls back to `lower(ba_name)`). Both are critical — duplicate prevention is the most common source of bugs.

RLS is on for everything. BAs can read/write own rows (+ read same-team peer profiles); managers read everything. See Invariant #4 on the `profiles` recursion landmine.

## Excel parsing quirks

Supervisor Excel sheets have inconsistent layouts month-to-month. `import_daily_sales.py` and `dashboard.py` both hardcode per-sheet config (row indices for BA names, total rows, daily date ranges). When a new month arrives, both configs need an entry (see "Definition of done").

**Non-sale cell markers** (treated as 0 sales, may indicate leave):
- `cong` = off day
- `nil` = zero sold (worked but no sale)
- `anual` / `annual` = annual leave
- `sick`, `eid` = other leave
- `xxxxxxx` / `xxxxxxxxx` = unknown, skip
- blank / `nan` = ignore

**Name normalization**: Excel rosters use spelling variants (`basher` vs `Besher`, `eman1`/`eman2`, trailing spaces). `dashboard.py` `CANONICAL` and the Postgres function `public.normalize_ba_name()` handle this. When a BA self-registers with a name that doesn't match the Excel roster, link them via `ba_merge_map` or a manual SQL merge.

## Deployment workflow

1. Make changes in `web_app/` (Python scripts don't deploy — they're local-only)
2. `git add` + `git commit` + `git push origin main`
3. Vercel auto-deploys within ~1 minute
4. Verify on `https://sales-management-phi-blue.vercel.app` on both iOS and Android if the change is UI/PWA-facing
5. For RLS/schema changes, run the SQL in Supabase **before** pushing dependent code

If Vercel CLI is needed: `npx vercel --prod --yes`. Don't `vercel link` to a new project.

## Where things live

- **New BA-facing UI** → `web_app/ba.html`
- **New manager UI** → `web_app/manager.html` (keep monolithic; see Intentional non-choices)
- **Login/auth flows** → `web_app/index.html`
- **DB schema changes** → BOTH `web_app/setup.sql` (canonical) AND a new dated file in `web_app/sql/` (for running on live)
- **One-off data fixes** → new file in `web_app/sql/`, verb-first name (`fix_*`, `link_*`, `merge_*`, `restore_*`, `confirm_*`, `check_*`)
- **Adding a new month to Excel ingest** → update BOTH `SHEET_CONFIG` in `dashboard.py` AND `MATRIX_SHEET_CONFIG` in `import_daily_sales.py` — two separate configs that must stay in sync
- **PWA install / service worker** → `web_app/pwa.js`, `web_app/sw.js`, `web_app/manifest.webmanifest`
- **Static assets** → `web_app/icons/`
- **Never put code in repo root** except the existing Python scripts (`dashboard.py`, `import_*.py`, `config.py`, `targets.py`, `inspect_excel.py`). New Python work also goes in repo root for now; no `src/` reshuffle without a real reason.

## Definition of done

**Fixing a data bug (incorrect totals, duplicates, wrong assignments):**
1. Diagnose with a `select` query first — never edit before counting
2. Write a new file `web_app/sql/<verb>_<thing>.sql` with a header comment explaining what's broken and why this fix is correct
3. Run in Supabase SQL Editor; capture row counts before and after
4. Verify in `manager.html` AND from a BA's perspective (the same data is shown differently)
5. Commit the SQL file with a message describing the fix

**Shipping a UI change:**
1. Make the edit
2. Open the file in a browser via `python -m http.server` and click through the path that changed
3. `git push origin main`
4. Wait ~1 minute, then verify on `https://sales-management-phi-blue.vercel.app`
5. If it touches the BA app, hard-reload on both iOS and Android (service worker can serve stale)

**Adding a new month of Excel data:**
1. `python inspect_excel.py` against the new file to see column layout
2. Add an entry to `SHEET_CONFIG` (dashboard.py) AND `MATRIX_SHEET_CONFIG` (import_daily_sales.py)
3. `python import_daily_sales.py --file <new>.xlsx --sheet <name>` — must NOT error with "monthly-shape detected"
4. Manually verify the CSV before pasting into Supabase
5. Count rows in Supabase before and after import

**Onboarding a new BA who signed up but doesn't match Excel roster:**
1. Find the unlinked Excel rows: `select * from sales_entries where ba_id is null and lower(ba_name) like '%<name>%'`
2. Write `web_app/sql/link_<name>.sql` with a header comment showing the count of rows to be linked
3. Run, then verify the new BA can see their own past sales in the app

## Intentional non-choices

These look like gaps; they're decisions. Don't "fix" them without asking.

- **No build step, no bundler.** CDN imports for `supabase-js` are deliberate — BAs install once and stay on it; no rebuild churn, no cache busting beyond `sw.js`. Don't introduce Vite/webpack/etc.
- **No test suite.** Team is small enough that manual verification on the live URL is the workflow. Don't introduce Jest/Playwright/etc.
- **No env vars file.** Supabase URL + anon key are hardcoded in `index.html`, `ba.html`, `manager.html`. Rotating means find-and-replace in 3 files. Don't move them to `.env` — there's no build to read it.
- **`manager.html` is one giant file by choice.** Splitting it has been tried; it broke filter state and duplicated data on the dashboard. Keep it monolithic until there's a concrete refactor plan that solves state sharing.
- **`web_app/sql/*.sql` is not a migration directory.** It's a log of one-off fixes already run in production. Don't try to "replay" them, don't add a numbering scheme, don't add a runner.
- **Black/white branding was reverted.** D&G colors-and-accents (blue/green for status, etc.) are the current design. If asked to "simplify the colors," check with the user first — going monochrome was tried and reverted.

## Common pitfalls

- **Don't run destructive SQL without confirming.** Supabase's "Run query" button is the only safety net; a bad `where` on `delete from sales_entries` wipes live data.
- **Service worker can serve stale.** After deploys to `ba.html`, a BA who already has the PWA installed may see old code until they hard-reload or `sw.js` cache version is bumped.
- **`profiles` RLS recursion** — see Invariant #4.
- **Don't refactor `manager.html` lightly** — see Intentional non-choices.
- **The anon key in HTML is public on purpose** — see Invariant #1.
- **iOS PWA install is finicky.** The "green install button" only shows on Chrome/Android via `beforeinstallprompt`; iOS users must Share → Add to Home Screen. In-app browsers (WhatsApp/Instagram) can't install at all — `pwa.js` detects these and shows a hint to open in Safari.

## Gitignore quirks worth knowing

`*.xlsx` is ignored globally — Excel data files should never be committed. `report.html`, `__pycache__`, and root-level `/normalized_*.csv` are also ignored. `import_historical.py` is in `.gitignore` because earlier versions held secrets; the file in the repo is the cleaned version, but verify before committing edits to it.
