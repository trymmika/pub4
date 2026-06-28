# DEPLOY TODO — Rails apps + OpenBSD infra to completion

## Context
- Source of truth: latest `anon987654321/pub4` (mirrored to `trymmika/pub4`; upstream is 403-blocked
  here so the mirror is canonical). Push to `claude/pub4-code-review-btGKK` (PR #1).
- Platform: OpenBSD 7.8, Ruby 3.4, **zsh only**. BANNED: bash-isms, sed/awk/tr/cut, python, sudo
  (use zsh builtins + `doas`).
- Server IP: `185.52.176.18` (in every app script and `openbsd.sh:157`).
- These are **generators**: each `deploy/rails/<app>/<app>.sh` builds a Rails 8 app, then
  `deploy/openbsd/openbsd.sh` provisions the host (NSD/DNSSEC, relayd, acme, pf, smtpd) and runs each
  app under Falcon. Shared library: `deploy/rails/@shared_functions.sh`.

### ⚠️ Hard constraint — do NOT reintroduce extracted Rails views
Rails view markup that was deliberately moved **out** of the old `*.sh` generators must not be
pasted back in. When editing any generator, only touch the shell/orchestration logic; never restore
view heredocs that were extracted. If a change seems to require re-adding views, stop and ask.

### Apps inventory
| App | Port | Script | Domain | In openbsd.sh? |
|-----|------|--------|--------|----------------|
| brgen | 10001 | brgen/brgen.sh (+ marketplace, dating, takeaway, tv, playlist) | brgen.no (+cities) | yes |
| amber | 10001* | amber/amber.sh | amberapp.com | yes |
| bsdports | 10003 | bsdports/bsdports.sh | bsdports.org | yes |
| blognet | 10007 | blognet/blognet.sh | — | no |
| privcam | 10005 | privcam/privcam.sh | privcam.no | no |
| hjerterom | 10004 | hjerterom/hjerterom.sh | — | no |
| baibl | — | baibl/baibl.sh | — | no |
> *amber and brgen both hardcode APP_PORT=10001 — collision (P1.3).

---

## ✅ Done (landed on this branch)
- **P0.1** — broken shared-lib source path fixed in all 11 sub-dir scripts
  (`${SCRIPT_DIR}/../@shared_functions.sh`). They no longer abort on startup.
- **P1.5** — `openbsd/README.md` corrected from the stale `46.23.95.45` to `185.52.176.18` (5 spots).
- **P4.2** — removed committed backup duplicate `rails/amber/amber_v1_backup.sh`.

---

## P0 — Blockers / correctness

### P0.2 — README documents a `__shared/` module system that doesn't exist
`rails/README.md` describes `__shared/@core.sh`, `@helpers.sh`, `@features.sh`, `@rails8_stack.sh`,
`@frontend_*.sh`, and a "22→10 files" consolidation. **Only `@shared_functions.sh` exists.**
**Fix**: rewrite the README to the single-file reality (cheap), or split the lib into the documented
modules (real refactor). README must match the tree.

### P0.3 — `setup_full_app` is thinner than the README claims
`@shared_functions.sh:448-470` does `rails new` + appends Solid gems + runs the solid installers
(`… 2>/dev/null || true`, swallowing failures). It does **not** call `setup_authentication` (defined
at :395), generates **no** Falcon config (README's `generate_falcon_config`/`setup_devise_guests` are
absent), and never runs `db:create`/`db:migrate`. **Fix**: make setup_full_app actually do what the
README promises, or correct the README; stop swallowing installer errors.

---

## P1 — Infrastructure (deploy/openbsd/openbsd.sh)

### P1.1 — Only 3 of 7 apps are deployed
`ALL_APPS` (openbsd.sh:200) = brgen, amber, bsdports, + an `ai` service (8787). blognet, privcam,
hjerterom, baibl have generators but no rc.d/relayd/zone entry. **Fix**: decide per app — deploy
(add to ALL_APPS + relayd backend + zone) or mark out-of-scope. Document it.

### P1.2 — brgen sub-apps not wired to subdomains
openbsd.sh:218 routes `markedsplass,playlist,dating,tv,takeaway` subdomains, but `brgen/brgen.sh`
never sources/invokes the sub-generators (and brgen.sh doesn't even source `@shared_functions.sh`).
**Fix**: add an orchestrator that runs each sub-generator and binds it to its relayd subdomain+port.

### P1.3 — Port collisions / unassigned ports
amber and brgen both `APP_PORT=10001`. Canonical map: brgen 10001, pubattorney 10002, bsdports 10003,
hjerterom 10004, privcam 10005, amber 10006, blognet 10007. **Fix**: unique port per script; emit the
map once and have openbsd.sh relayd backends reference the same source.

### P1.4 — PostgreSQL vs SQLite contradiction
Generators do `rails new --database=postgresql` but `openbsd/README.md` says Postgres was removed
(use SQLite/external) and the script installs no DB. Apps would boot with a pg adapter and no server
DB. **Fix**: choose one DB strategy and apply it across generators + infra.

### P1.5 — ✅ done (see above)

### P1.6 — Verify infra generation end-to-end
Confirm each deployed app gets: `rc.d/<app>`, relayd backend + per-domain TLS keypair, PF rules,
acme-client entry, signed NSD zone. Spot-check Stage 1 (`openbsd.sh`) and Stage 2 (`--resume`) run
without undefined-variable aborts under `setopt no_unset`.

---

## P2 — Shared library (@shared_functions.sh)
- **P2.1** — no Falcon production-config generator exists though openbsd.sh expects Falcon; add one
  binding `tcp://127.0.0.1:<port>` consistent with the rc.d script.
- **P2.2** — CSS strategy conflict: `rails new --css=tailwind` vs the repo's `__common_patterns.css`
  + `generate_application_scss()` (BEM). Pick one, apply uniformly.
- **P2.3** — `grep -q "solid_queue" Gemfile` for control flow; prefer zsh
  `[[ "$(<Gemfile)" == *solid_queue* ]]`.

---

## P3 — Per-app completion
- **P3.1** — tests absent everywhere except bsdports. Gate target: line coverage ≥ 0.8. Generate
  minitest model/controller/system tests per app and run `bin/rails test` before reporting success.
- **P3.2** — after P0.1, smoke-test each app: models/migrations consistent, routes↔actions exist,
  i18n keys defined (hjerterom/baibl ship Norwegian), `db:prepare && test && server` boots.
  **Reminder:** verifying views must not mean re-adding extracted view markup to the `*.sh` files.
- **P3.3** — replicate amber's idempotency guard (`check_app_exists …`) to every app so reruns are
  safe; confirm bsdports has a defined ports-data source, not an assumed one.

---

## P4 — Hygiene
- **P4.1** — `rails/modernize_zsh.sh:14-23` uses banned `sed -i`. Reimplement with zsh parameter
  expansion or delete if its job is done.
- **P4.2** — ✅ done (backup removed).
- **P4.3** — `rails/social_web.pdf` (~12.9 MB) committed in the deploy path; move it out / to release
  assets if it's reference material.
- **P4.4** — both READMEs cite a `master.yml` (v74.2.0 / v206) and `/home/runner/...` paths that don't
  exist in the repo. Point to the real governance source (MASTER `lib/config`) or drop the claims.

---

## Definition of done
1. P0: every app generator runs `rails new` to completion and setup_full_app matches its README.
2. P1: openbsd.sh provisions every in-scope app with unique ports, one DB strategy, correct IP;
   Stage 1 + Stage 2 run clean under `no_unset`.
3. P2/P3: Falcon config generated; each app boots and `bin/rails test` passes.
4. P4: no banned commands, no committed cruft, READMEs match the tree.
5. No extracted Rails views reintroduced into any `*.sh` generator.
6. Validate: `cd MASTER && bundle exec ruby bin/master scan ../deploy`.

## Git workflow
- Branch `claude/pub4-code-review-btGKK`; commit style `fix(deploy): <scope> <change>`.
- Never commit `.env`/keys.
