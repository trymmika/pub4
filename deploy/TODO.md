# DEPLOY TODO — Bring the Rails apps to completion

## Context
- Source of truth: latest `anon987654321/pub4` (mirrored into `trymmika/pub4` main via merge
  `8b5b78a`, 2026-02-21; upstream is 403-blocked in this environment so the mirror is canonical).
- Commit/push to: `claude/pub4-code-review-btGKK`. NEVER push to main/master without permission.
- Platform: OpenBSD 7.8, Ruby 3.4, **zsh only**. BANNED: bash-isms, sed/awk/tr/cut, python, sudo.
  Use zsh builtins + parameter expansion. `doas` for privilege, not sudo.
- Server: `185.52.176.18` (the value hardcoded in every app script AND in openbsd.sh:157).
- These are **generator scripts**: each `app.sh` builds a Rails 8 app from scratch, then the app is
  uploaded and `deploy/openbsd/openbsd.sh` provisions the OpenBSD host (NSD/DNSSEC, relayd, acme, pf,
  smtpd) and runs each app under Falcon.
- Stack target (per rails/README.md): Rails 8, Solid Queue/Cache/Cable (no Redis), Hotwire
  (Turbo + Stimulus), PWA, Falcon. PostgreSQL is used by the generators but NOT installed by the
  infra script — see P1.4 (must be reconciled).

### Apps inventory (deploy/rails/)
| App | Port | Script | Domain | In openbsd.sh? |
|-----|------|--------|--------|----------------|
| brgen | 10001 | brgen/brgen.sh (+ marketplace, dating, takeaway, tv, playlist) | brgen.no (+35 cities) | yes |
| amber | 10001* | amber/amber.sh | amberapp.com | yes |
| bsdports | 10003 | bsdports/bsdports.sh | bsdports.org | yes |
| blognet | 10007 | blognet/blognet.sh | — | **NO** |
| privcam | 10005 | privcam/privcam.sh | privcam.no | **NO** |
| hjerterom | 10004 | hjerterom/hjerterom.sh | — | **NO** |
| baibl | — | baibl/baibl.sh | — | **NO** |
> *amber and brgen both hardcode APP_PORT=10001 — port collision, see P1.3.

---

## P0 — BLOCKERS (nothing deploys until these are fixed)

### P0.1 — Broken shared-library source path in every sub-directory app
Every app in a subfolder does:
```zsh
SCRIPT_DIR="${0:a:h}"                          # = deploy/rails/<app>/
source "${SCRIPT_DIR}/@shared_functions.sh"    # looks in deploy/rails/<app>/  ← WRONG
```
But `@shared_functions.sh` lives in the PARENT `deploy/rails/`. The source fails immediately, so
`setup_full_app`, `log`, `check_app_exists`, etc. are all undefined → script aborts on line ~17-19.
Affected: amber/amber.sh:19, baibl/baibl.sh:19, blognet/blognet.sh:17, bsdports/bsdports.sh:17,
privcam/privcam.sh:17, hjerterom/hjerterom.sh:19, brgen/brgen_*.sh:19 (all six).
**Fix**: `source "${SCRIPT_DIR}/../@shared_functions.sh"` (or compute repo-relative path). Verify
each app actually runs `rails new` after the fix.

### P0.2 — README documents a module system that does not exist
`deploy/rails/README.md` describes `__shared/@core.sh`, `@helpers.sh`, `@features.sh`,
`@integrations.sh`, `@rails8_stack.sh`, `@rails8_propshaft.sh`, `@frontend_*.sh`, plus a
"22 files → 10 modules" consolidation. **None of these files exist** — only `@shared_functions.sh`
is present. Either (a) split `@shared_functions.sh` into the documented modules, or (b) rewrite the
README to describe the single-file reality. Pick one; the README must match the tree.

---

## P1 — Infrastructure completeness (deploy/openbsd/openbsd.sh)

### P1.1 — openbsd.sh deploys only 3 of 7 apps
`ALL_APPS` (openbsd.sh:200) = brgen, amber, bsdports, + `ai` service (8787). blognet, privcam,
hjerterom, baibl have generators but no rc.d / relayd / domain entry. Decide per app: deploy
(add to ALL_APPS + relayd backend + zone) or mark explicitly out-of-scope. Document the decision.

### P1.2 — brgen sub-apps are not wired to their subdomains
openbsd.sh:218 routes brgen.no subdomains `markedsplass,playlist,dating,tv,takeaway,maps,ai`, but
`brgen/brgen.sh` never sources or invokes brgen_marketplace/dating/takeaway/tv/playlist.sh, and
nothing maps a generated sub-app to each subdomain backend. Add an orchestrator (brgen.sh runs the
sub-generators, or a top-level runner) and bind each sub-app to its relayd subdomain + port.

### P1.3 — Port collisions / unassigned ports
amber (APP_PORT=10001) and brgen (10001) collide. Governance port map: brgen 10001, pubattorney
10002, bsdports 10003, hjerterom 10004, privcam 10005, amber 10006, blognet 10007. Reconcile each
script's APP_PORT to a unique value and make openbsd.sh relayd backends use the same map (single
source of truth — emit the map once, reference it).

### P1.4 — PostgreSQL vs SQLite contradiction
`setup_full_app` runs `rails new . --database=postgresql` (@shared_functions.sh:457), but
openbsd/README.md states "Database services (PostgreSQL, Redis) removed… Use SQLite or external
database" and openbsd.sh installs no postgres. Result: generated apps boot with a pg adapter and no
server DB. Decide: install/provision PostgreSQL in openbsd.sh, OR switch generators to sqlite3 +
Solid Queue/Cache/Cable on SQLite. Apply consistently across all apps and the infra script.

### P1.5 — openbsd/README.md has the wrong server IP
README says primary `46.23.95.45` (lines 109, 178, 181, 218, 314) but the script uses
`185.52.176.18` (openbsd.sh:157). Fix the README to 185.52.176.18 throughout, and update the verify
commands (`dig @…`, `telnet …`) to match.

### P1.6 — Verify infra generation end-to-end
Confirm the script actually produces, for each deployed app: an `rc.d/<app>` service, a relayd
backend + TLS keypair per domain, a PF rule set, an acme-client entry, and a signed NSD zone.
Spot-check that Stage 1 (`openbsd.sh`) and Stage 2 (`openbsd.sh --resume`) both run without
undefined-variable aborts under `setopt no_unset`.

---

## P2 — Shared library gaps (deploy/rails/@shared_functions.sh)

### P2.1 — setup_full_app is thinner than the README claims
README says setup_full_app sets up auth, Solid Stack, **and Falcon production config**. The actual
body (lines 448-470) only does `rails new` + appends Solid gems + runs the solid installers. It does
**not** call `setup_authentication` (defined separately at :395), does **not** generate a Falcon
config (`generate_falcon_config`/`setup_devise_guests` are referenced in the README but absent), and
does **not** run `db:create`/`db:migrate`. Either call these from setup_full_app or document that
each app must call them. Make README and code agree.

### P2.2 — No Falcon production config generator exists
README references `generate_falcon_config()` and `setup_devise_guests()`; neither is defined.
openbsd.sh expects each app to serve under Falcon. Add a `generate_falcon_config` that writes the
Falcon binding (`tcp://127.0.0.1:<port>`) consistent with the rc.d script openbsd.sh creates.

### P2.3 — CSS strategy conflict: tailwind vs BEM/SCSS
setup_full_app uses `rails new --css=tailwind`, but the repo ships `__common_patterns.css` and
`generate_application_scss()` (@shared_functions.sh:9), and governance mandates BEM. Pick one CSS
strategy and apply it uniformly; remove the unused path.

### P2.4 — Solid installers swallow errors
Lines 467-469 run `bin/rails generate solid_*:install 2>/dev/null || true` — failures are hidden
(violates FAIL_VISIBLY). Log the failure and stop, or assert the migrations exist afterward.

### P2.5 — `grep -q` for control flow
@shared_functions.sh:460 uses `grep -q "solid_queue" Gemfile`. Governance bans grep for text
processing; for a membership test prefer zsh: `[[ "$(<Gemfile)" == *solid_queue* ]]`.

---

## P3 — Per-app completion

### P3.1 — Tests are absent everywhere except bsdports
Only `bsdports/bsdports.sh` generates any test artifacts. Governance gate: line coverage ≥ 0.8 (95%
target), function 100%. For each app, generate minitest model/controller/system tests as part of the
script, and have the script run `bin/rails test` before reporting success.

### P3.2 — Per-app review checklist (run after P0.1 fix)
For each of brgen(+5 sub-apps), amber, baibl, bsdports, blognet, privcam, hjerterom verify the
generator produces a coherent app and boots:
- models + migrations consistent (no dangling associations, FKs present)
- controllers + routes wired; every referenced action exists
- views render (Hotwire/Turbo/Stimulus targets match controllers)
- seeds present where the app needs reference data (baibl texts, bsdports ports, brgen cities)
- i18n: hjerterom/baibl ship Norwegian locale keys — confirm all `t("…")` keys are defined
- `bin/rails db:prepare && bin/rails test && bin/rails server` smoke test passes
Record findings inline per app; convert each gap into a checklist item here.

### P3.3 — App-specific notes captured during audit
- amber: idempotency guard present (`check_app_exists … app/models/wardrobe_item.rb`) — good pattern;
  replicate to every app so reruns are safe.
- brgen sub-apps (marketplace/dating/takeaway/tv/playlist) are large (1.4k–1.8k lines) and
  standalone — confirm none assume a shared parent app schema that brgen.sh hasn't created.
- bsdports: needs a ports data import/seed path — confirm the source of the ports list is defined,
  not assumed.

---

## P4 — Hygiene / repo cleanliness

### P4.1 — modernize_zsh.sh uses banned `sed -i`
`rails/modernize_zsh.sh:14-23` is a meta-script that rewrites other scripts using `sed -i`
(banned). Either reimplement with zsh parameter expansion / `${(s/…/)}` + file rewrite, or delete it
if its job is already done.

### P4.2 — Remove committed backup duplicate
`rails/amber/amber_v1_backup.sh` (3044 lines) is a byte-identical-size backup of `amber.sh`. Backups
belong in git history, not the tree. Delete it.

### P4.3 — Large binary in the tree
`rails/social_web.pdf` is ~12.9 MB committed to the repo. Confirm it's needed; if it's reference
material, move it out of the deploy path or to release assets.

### P4.4 — README "master.yml" references point to a non-existent file
Both READMEs cite `master.yml` (v74.2.0 / v206) and paths like `/home/runner/work/pub4/pub4/master.yml`.
No `master.yml` exists in the repo. Update references to the actual governance source (MASTER gem /
lib/config) or drop the version claims.

---

## Definition of done
1. P0 fixed: every app script sources the shared lib and runs `rails new` to completion.
2. P1 fixed: openbsd.sh provisions every in-scope app with unique ports, a coherent DB strategy, and
   correct IP everywhere; Stage 1 + Stage 2 run clean under `no_unset`.
3. P2 fixed: setup_full_app + Falcon + auth + DB setup match the README; no swallowed errors.
4. P3: each app boots and `bin/rails test` passes with generated tests.
5. P4: no banned commands, no backup/binary cruft, READMES match the tree.
6. Validate scripts against MASTER: `cd MASTER && bundle exec ruby bin/master scan ../deploy`.

## Git workflow
- Branch: `claude/pub4-code-review-btGKK`; push `git push -u origin claude/pub4-code-review-btGKK`.
- Commit style: `fix(deploy): correct shared-lib source path in app generators`.
- Never commit .env files, API keys, or the server's private keys.
