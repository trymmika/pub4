# MASTER TODO — Ordered Work Queue

## Context
- MASTER2 was renamed to MASTER. All findings below apply to the `MASTER/` folder.
- MASTER/ lives on branch: `origin/refactor/comprehensive-quality-improvements`
- Commit/push to: `claude/pub4-code-review-btGKK`
- Platform: OpenBSD 7.8, Ruby 3.4, zsh. NEVER use bash/awk/sed/python/sudo.
- Rules: no `rescue nil`, no swallowed errors (FAIL_VISIBLY), files <300 lines, Result Ok/Err monad,
  data/*.yml + lib/config/ is single source of truth, no hardcoded fallbacks, SELF_APPLY axiom.
- The face3d / Rails web UI log is from a DIFFERENT project — do NOT implement it here.
- Upstream anon987654321/pub4 is 403 blocked. Use trymmika/pub4 only.
- Validate changes: `cd MASTER && bundle exec ruby bin/master scan <path>`

---

## PRIORITY 1 — Self-corruption fixes (START HERE)
These are the paths that can brick the gem's own source. Fix the fixers first.

### 1a. MASTER/lib/review/fixer.rb:19 — freeze_constants greedy /m regex
**Bug**: `code.gsub(/^(\s*[A-Z][A-Z_]*\s*=\s*[\[{].*)$/m)` — the `/m` flag makes `.*` match to
EOF. Appends `.freeze` to the wrong expression. Passes `valid_syntax?` because `end.freeze` is
valid Ruby, so corruption is silent.
**Fix**: Replace with Ripper-based AST constant detection, or at minimum drop the `/m` flag and
match a single line only. Do NOT run a greedy regex across multi-line Ruby structures.

### 1b. MASTER/lib/evolve.rb:91-94 — Evolve writes LLM output without syntax check
**Bug**: `File.write(file, clean)` with no validation. Can corrupt MASTER's own lib/ source.
MultiRefactor correctly calls `valid_refactor?` (SyntaxValidator) before writing; Evolve forgot.
**Fix**: Add `unless SyntaxValidator.valid?(clean)` guard before File.write. On failure, log the
error visibly and return `Result.err("Syntax invalid after LLM refactor")`.

### 1c. MASTER/lib/reflow.rb:43-58 — line-reordering corrupts Ruby
**Bug**: Sorts "sections" line-by-line with no def/end/do tracking. Interleaves method bodies and
separates `def` from `end`. Writes in-place with no backup.
**Fix**: Either (a) restrict reflow to `.json`/`.yml` and never touch `.rb`, or (b) parse with
Ripper to find true section boundaries before reordering. Write a `.bak` backup before any write
and run SyntaxValidator after the rewrite; restore the backup on failure.

---

## PRIORITY 2 — Codify uploaded governance files into MASTER runtime
Restore/merge content from the 5 uploaded files into `MASTER/lib/config/` and `MASTER/data/`.

### Source files (in /root/.claude/uploads/7d733fc6-8078-55ac-92eb-5b3eccd41245/):
- `069d18bb-master_yml_monolithic.txt` — Universal Quality Framework v16.0.0 (1093 lines YAML)
- `f46e087a-critical_restoration_config.json` — restoration config v64.1 (487 lines)
- `2ef087d2-master_json_final.json` — compact governance JSON (146 lines)
- `e5c60c7d-comprehensive_design_final.json` — design analysis v1 (495 lines)
- `1d124be9-our_comprehensive_design_analysis.json` — design analysis v2/expanded (663 lines)

### 2a. Restore adversarial clusters (4 clusters, full structure)
Target: `MASTER/lib/config/adversarial_personas.yml`
- architect: contrarian_architect, elegance_purist, resilience_engineer, complexity_theorist
- operator: frugal_innovator, speed_demon, ops_realist, automation_engineer
- guardian: security_paranoid, privacy_guardian, code_official, compliance_auditor
- advocate: ux_poet, accessibility_advocate, ethics_reviewer, user_researcher
Each cluster: focus_areas, active_phases, expertise_domains, veto_powers.
(Source: critical_restoration_config.json /process/adversarial_clusters)

### 2b. Restore question bank (10 categories, 6 questions each)
Target: new `MASTER/lib/config/question_bank.yml` (or merge into framework config).
Categories: assumptions, failure_modes, attacker, scale, degradation, edge_cases, ops_maint,
compliance_ethics, a11y_ux, economics.
(Source: critical_restoration_config.json /process/question_bank — verbatim text available)

### 2c. Restore workflow phases with question + cluster assignments
Target: `MASTER/lib/config/phases.yml`
Phases (restoration config, 7): discover, analyze, design, implement, validate, document, reflect.
Phases (monolithic v16, 8) also include `deliver`. Reconcile to one canonical list; each phase
gets: clusters, output, trigger_conditions, questions (drawn from question_bank categories).

### 2d. Restore decision_framework
Target: `MASTER/lib/config/framework/workflow_engine.yml`
- consensus_mechanisms: cluster_voting (weighted_by_expertise_and_stake), tie_breaking
  (escalation_to_meta_level_principles), veto_powers (security/compliance/accessibility absolute),
  time_boxing.
- escalation_protocols: technical_deadlock, resource_conflict, compliance_violation,
  quality_failure (plus security_threat, accessibility_barrier from v16).

### 2e. Merge anti-pattern detection
Target: `MASTER/lib/config/framework/universal_standards.yml` (or new `detect.yml`).
- Rails: erb_sprawl, divitis, stimulus_antipatterns, hotwire_misuse
- Solidus: deface_overrides, deep_partial_nesting, checkout_flow_complexity, taxon_trees
- PWA: offline_capability, cache_invalidation, stimulus_reflex_offline
- Marketplace: affiliate_tracking, price_intelligence, deal_curation

### 2f. Merge quality standards / metrics
Target: `MASTER/lib/config/framework/quality_gates.yml`
- complexity: cyclomatic max 8/50/100, nesting max 3, method max 15 lines, class max 200 lines/20 methods
- test_coverage: line 95%, branch 90%, function 100%
- naming_conventions, redundancy_elimination (ABSOLUTE_ZERO tolerance)
- constants (master_json_final): coverage 0.8, complexity 10, convergence 0.01, iterations 10,
  coupling 5, duplication 0.03, nesting_depth 4, section_count 15

### 2g. Merge compact principles (17)
Target: `MASTER/data/principles.yml`
dry(3_dup→abstract,h), kiss(cx>10→simplify,h), yagni(unused→remove,m), solid(cp>5→decouple,c),
composition(deep_inherit→compose,m), evidence(assumption→validate,c),
reversible(irreversible→add_rollback,c), explicit(implicit→explicit,h),
orthogonal(coupled→split,h), minimalism(bloat→subtract,m), clarity(synonym→unify,m),
flatten(wrapper→flatten,h), pola(surprise→predictable,h), unix(multi_resp→one_thing,h),
anti_divitis(div_soup→semantic,m,html/css), anti_sectionitis(scattered→consolidate,h,json/yaml),
geometric(visual_confuse→simplify_geo,m,viz/ui).

### 2h. Merge adversarial intelligence (11 personas + bias + pitfall catalogs)
Target: `MASTER/lib/config/adversarial_personas.yml`
- Personas (lens): skeptic(question), minimalist(remove_all), perf(microsec), security(attack),
  maintainer(3am_debug), junior(clarity), architect(long_term), cost(spend), user(needs),
  chaos(break), fowler(classic_refactor). alt_min: 15.
- Biases (9): recency, confirm(h), anchor(h), available, sunk(h), optimism(h), dunning(c),
  authority, bandwagon.
- Pitfalls: code[off_by_1,null,race,leak,inject,overflow], design[circular,hidden_cp,shotgun,envy],
  cog[false_assume,premature,scope_creep,halluc,ctx_loss,over_mitigate].

### 2i. Restore design system knowledge (5 platforms)
Target: `MASTER/lib/config/plugins/design_system.yml`
- x_twitter: 3-col CSS Grid, system fonts, #E1E8ED borders, IntersectionObserver
- tiktok: 100vh/vw, thumb zone 20%/30-70%, Roboto 18px 700, neon #FF2D55 / #00F2EA
- medium: max-width 680px, Georgia 18px / 1.6 line-height, #FAF9F6 bg, #03A87C links
- substack: 2-section, 10 content blocks CSS Grid, Google Fonts API, #FF5733 CTA
- new_yorker: 3-col 16px gaps, Times New Roman, #C8102E accents, 40px margins
Include implementation prompts, cross-platform principles, prompt-engineering techniques.
(Source: comprehensive_design_final.json + our_comprehensive_design_analysis.json)

### 2j. Wire Ruby runtime to LOAD and USE the restored configs
Verify the Ruby files in `MASTER/lib/` that load `lib/config/*.yml` actually parse and use the
new/restored sections. Add loading code where a config exists but nothing reads it (SELF_APPLY:
dead config is a violation).

---

## PRIORITY 3 — Security fixes

### 3a. lib/speech/backends.rb:19-27 — TTS command injection (RCE)
Replace `system(cmd)` (shell string with interpolated text) with array/popen form:
`IO.popen(["piper", "--model", model, "--output_file", output]) { |io| io.write(text) }` — no shell.

### 3b. lib/executor/tools.rb:150-169 — shell_command via `sh -c`
Replace `Open3.capture3("sh", "-c", cmd)` with array form. Replace the 6-pattern denylist with a
real allowlist of permitted commands.

### 3c. lib/executor/tools.rb:171-195 — code_execution regex denylist
Trivially bypassed (`send(:system,...)`, `eval`, `File.write` not listed). Use a real subprocess
sandbox: pledge/unveil on OpenBSD; otherwise reject, or run in a restricted subprocess with no
network and filesystem confined to a temp sandbox dir.

### 3d. lib/review/enforcer.rb:258-264 — eval() on reviewed source
Replace `eval(code, binding_obj)` with a subprocess syntax check only:
`Open3.capture3(RbConfig.ruby, "-c", stdin_data: code)`. Never execute reviewed source in-process.

### 3e. lib/server.rb — timing attack + exposure + token leakage
- Line 109: `token == AUTH_TOKEN` → `Rack::Utils.secure_compare(token.to_s, AUTH_TOKEN.to_s)`
- Line 74: `http://0.0.0.0:#{@port}` → `http://127.0.0.1:#{@port}`
- Line 108: remove `?token=` query-param acceptance; Bearer header only
- Line 114: never interpolate AUTH_TOKEN into served HTML

### 3f. lib/server/websocket.rb — no Origin check
Before opening the WebSocket:
`origin = env["HTTP_ORIGIN"]; return [403,{},[]] unless origin&.start_with?("http://127.0.0.1")`

### 3g. lib/web.rb:22-41 + lib/replicate/media.rb:80-98 — SSRF
Add to download_file and Web.browse: scheme allowlist (http/https only) and host blocklist
(127.0.0.1, localhost, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16). Re-check the
host after every redirect.

### 3h. lib/auto_install.rb:72 — shell injection
`system("pkg_info -e '#{name}-*' > /dev/null 2>&1")` →
`system("pkg_info", "-e", "#{name}-*", out: File::NULL, err: File::NULL)` with a validated name.

---

## PRIORITY 4 — Broken / dead code

### 4a. lib/session/memory.rb:54 — session restore bug
`JSON.parse(File.read(path, symbolize_names: true), symbolize_names: true)` →
`JSON.parse(File.read(path), symbolize_names: true)` (File.read has no symbolize_names option).

### 4b. lib/queue.rb:142 — checkpoint load bug
Same File.read kwarg fix as 4a.

### 4c. lib/llm/request.rb:79 — REASONING_EFFORT undefined
Define `REASONING_EFFORT = %w[low medium high max].freeze` at top of file, or load from
data/models.yml. Currently every reasoning request raises NameError (swallowed).

### 4d. lib/commands.rb:225-229 — five missing command methods
creative_chamber, scan_code, manage_queue, harvest_data, manage_workflow. Either implement them or
remove the routes from COMMAND_TABLE/dispatch and update help text. No silent NoMethodError.

### 4e. lib/learnings/reflection.rb:16-30 — Memory.remember/recall missing
Change to use Memory.store/fetch, or define remember/recall as aliases.

### 4f. lib/code_review/engine.rb:76,136 — Smells.detect missing
Change `Smells.detect` → `Smells.analyze` (only .analyze is defined; deep scan is a silent no-op).

### 4g. lib/db_jsonl.rb:14 — missing require
Add `require "monitor"` at top of file (uses Monitor.new).

### 4h. lib/hooks.rb:144-177 — hook actions are no-ops
security_scan, lint_check, log_context, suggest_fix, run_affected_tests, full_test_suite,
offer_rollback, check_principles, break_deadlock, summarize_session are declared but unimplemented;
the else-branch returns true ("success"). Implement, or `Logging.warn`/raise NotImplementedError
(FAIL_VISIBLY) instead of reporting green. A security scan that does nothing must not report pass.

### 4i. lib/chamber.rb:21-25 — MODELS constant all nil
Populate from data/models.yml strong/fast tiers, or use LLM.select_model with explicit tiers.
Currently "multi-model deliberation" runs one model.

---

## PRIORITY 5 — Constitution violations (self-apply compliance)
- Replace pervasive `rescue nil` / `rescue StandardError => e` (unused e) with visible logging.
- Unify file-size threshold to 300 everywhere (engine.rb and selftest use 600). Make it data-driven
  from smells.yml.
- Remove hardcoded `default_config` fallback in lib/quality_gates.rb:148-191; fail visibly if YAML missing.
- Remove inline `|| 120`, `|| 50`, `|| 5` threshold fallbacks in enforcement/scopes.rb and
  enforcement/layers.rb.
- data/budget.yml: either read it in lib/llm/budget.rb or delete it (currently dead config).
- lib/llm/budget.rb: Float::INFINITY serializes as non-standard JSON; use nil or a high integer.
- semantic_cache.rb:101: include `tier:` in the SHA256 cache key to prevent cross-tier collisions.
- scripts/openbsd_preflight.zsh:20: replace `awk` (banned) with zsh builtins, e.g.
  `arr=(${(z)$(ruby -v)}); print -r -- $arr[1] $arr[2]`.
- scripts/openbsd_preflight.zsh:39: replace `timeout 20s` (not in OpenBSD base) with a zsh alarm or remove.
- MultiRefactor: add rollback if `rubocop -A` corrupts the file after the syntax check passed.

---

## Git workflow
- Work on branch: `claude/pub4-code-review-btGKK`
- MASTER/ content is on `origin/refactor/comprehensive-quality-improvements` — check it out or cherry-pick.
- Push: `git push -u origin claude/pub4-code-review-btGKK`
- Commit style: `fix(fixer): replace greedy /m regex with Ripper AST in freeze_constants`
- NEVER push to main/master without explicit permission. NEVER commit .env files or API keys.
