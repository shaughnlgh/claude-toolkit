#!/usr/bin/env bash
# Hermetic suite for the execute-flow section 2b command forms. Each command is kept as the template text the skill
# writes, checked verbatim against execute-flow SKILL.md, filled with fixture values and run on fixture repos under
# mktemp -d. Needs git, jq and python3. No network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../../../skills/execute-flow/SKILL.md"
CAP="$HERE/../../slice-capture.py"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(cd "$(mktemp -d -t several.XXXXXX)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
printf '[user]\n\temail = t@t.invalid\n\tname = t\n[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T"

# fill: a template, then '<token>=value' pairs, replaced in order.
fill() { python3 -c 'import sys
s = sys.argv[1]
for a in sys.argv[2:]:
    k, v = a.split("=", 1)
    s = s.replace(k, v)
sys.stdout.write(s)' "$@"; }
# runin: run a filled command in a directory, keeping stdout in OUT and the exit code in RC.
runin() { OUT="$(cd "$1" && bash -c "$2" 2>"$T/err")"; RC=$?; }

T_ROOT='git rev-parse --path-format=absolute --git-common-dir'
T_GITDIR="test -d '<projects root>/<repo>/.git'"
IFS= read -r T_LOCK <<'EOF'
jq -r --arg p '<name>' '[.packages[]?, ."packages-dev"[]?] | map(select(.name == $p)) | .[0].source.url // empty' '<cr>composer.lock'
EOF
T_ORIGIN='git remote get-url origin'
T_RULES="find CLAUDE.md AGENTS.md .claude/rules -name '*.md'"
T_HOOKS="jq -c '.hooks // {}'"
T_HEAD='git symbolic-ref --short refs/remotes/origin/HEAD'
T_FETCH="cd '<main>' && git fetch origin '<default>'"
T_ADD="cd '<main>' && git worktree add --no-track -b '<branch>' '<main>/.claude/worktrees/<name>' 'origin/<default>'"
T_LIST='git worktree list --porcelain'
T_PROBE="cd '<project wt>' && printf '%s\n' '<payload>' | CLAUDE_PROJECT_DIR='<main>' sh -c '<hook command>'"
T_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"<m>/composer.json"}}'
T_MFETCH_BRANCH="git fetch origin '<branch>'"
T_MSWITCH="git switch '<branch>'"
T_MFETCH_DEFAULT="git fetch origin '<default>'"
T_MNEW="git switch --no-track -c '<branch>' 'origin/<default>'"
T_STATUS="git -c core.quotePath=false status --porcelain -uall -- ':(exclude,top).claude/worktrees/' ':(exclude,top)<path>/'"

missing=""
for t in "$T_ROOT" "$T_GITDIR" "$T_LOCK" "$T_ORIGIN" "$T_RULES" "$T_HOOKS" "$T_HEAD" "$T_FETCH" "$T_ADD" "$T_LIST" \
  "$T_PROBE" "$T_PAYLOAD" "$T_MFETCH_BRANCH" "$T_MSWITCH" "$T_MFETCH_DEFAULT" "$T_MNEW" "$T_STATUS"; do
  grep -qF -- "$t" "$SKILL" || missing="$missing [$t]"
done
[ -z "$missing" ] && ok "every template the suite runs appears verbatim in execute-flow SKILL.md" || no "templates missing from SKILL.md:$missing"

# origin: seed a work tree with the files a function writes there, commit on main, and keep a bare copy.
origin() {
  local s="$T/seed/$1"; mkdir -p "$s"; git -C "$s" init -q
  "seed_$1" "$s"
  git -C "$s" add -A; git -C "$s" commit -qm c1 --no-verify
  git clone -q --bare "$s" "$T/origins/$1.git"
}
seed_plain() { printf 'one\n' > "$1/README"; }
seed_ship() { seed_plain "$1"; }
seed_tax() { seed_plain "$1"; }
seed_pay() { seed_plain "$1"; }
seed_beta() { printf 'Beta rules.\n' > "$1/CLAUDE.md"; }
seed_alpha() {
  printf '/vendor/\n' > "$1/.gitignore"
  printf '{"packages":[{"name":"acme/module-ship","source":{"type":"git","url":"%s"}}],"packages-dev":[]}\n' "$T/origins/ship.git" > "$1/composer.lock"
  printf 'Alpha rules.\nSeveral-repos hooks: fixture\nModule checkout path: mods/<repo>\n' > "$1/CLAUDE.md"
  mkdir -p "$1/.claude/rules" "$1/.claude/hooks"
  printf 'Fixture rule.\n' > "$1/.claude/rules/10-fixture.md"
  cat > "$1/.claude/hooks/guard.sh" <<'EOF'
p="$(jq -r '.tool_input.file_path // empty')"
case "$p" in */vendor/*) echo "guard: vendor edit refused" >&2; exit 2;; esac
exit 0
EOF
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\""}]}]}}' > "$1/.claude/settings.json"
}
for o in ship pay tax alpha beta; do origin "$o"; done
git -C "$T/seed/pay" switch -q -c feat/fixture-plan
printf 'branch\n' >> "$T/seed/pay/README"; git -C "$T/seed/pay" commit -qam c2 --no-verify
git -C "$T/seed/pay" push -q "$T/origins/pay.git" feat/fixture-plan

R="$T/root"; mkdir -p "$R/mods"
git clone -q "$T/origins/alpha.git" "$R/alpha"
git clone -q "$T/origins/beta.git" "$R/beta"
git clone -q "$T/origins/ship.git" "$R/mods/ship"
PLAN=fixture-plan; BRANCH=feat/fixture-plan

runin "$R" "$T_ROOT"
[ "$RC" -ne 0 ] && ok "the projects root check exits non-zero in a projects root that is no repo" || no "projects root check in root (rc=$RC): $OUT"

runin "$R/alpha" "$T_ROOT"
[ "$RC" -eq 0 ] && ok "the projects root check exits 0 inside a checkout" || no "projects root check in alpha (rc=$RC): $(cat "$T/err")"

runin "$R" "$(fill "$T_GITDIR" "<projects root>=$R" "<repo>=gamma")"
[ "$RC" -ne 0 ] && ok "the .git check fails for a repo the projects root does not hold" || no ".git check for gamma (rc=$RC)"

runin "$R/alpha" "$(fill "$T_LOCK" "<name>=acme/module-ship" "<cr>=")"
[ "$OUT" = "$T/origins/ship.git" ] && ok "the lock read prints the module's source url" || no "lock read (rc=$RC): $OUT $(cat "$T/err")"

runin "$R/mods/ship" "$T_ORIGIN"
[ "$OUT" = "$T/origins/ship.git" ] && ok "the external checkout's origin url equals the lock's source url" || no "origin url: $OUT"

runin "$R/alpha" "$T_RULES"
[ "$(printf '%s\n' "$OUT" | sort)" = "$(printf '%s\n' .claude/rules/10-fixture.md CLAUDE.md)" ] \
  && ok "the rules read lists CLAUDE.md and the rules file with no AGENTS.md" || no "alpha rules: $OUT"

runin "$R/beta" "$T_RULES"
[ "$OUT" = "CLAUDE.md" ] && ok "the rules read in a repo with no rules folder lists only CLAUDE.md" || no "beta rules: $OUT"

runin "$R/alpha" "$T_HOOKS '.claude/settings.json'"
HOOKS="$OUT"
printf '%s' "$HOOKS" | jq -e 'has("PreToolUse")' >/dev/null 2>&1 && ok "the hooks read prints an object with a PreToolUse entry" || no "hooks read (rc=$RC): $HOOKS"

# worktree: run the second-case commands in a main checkout and print the branch line of the new worktree's entry.
worktree() {
  local main="$1" default
  runin "$main" "$T_HEAD"; default="${OUT#origin/}"
  runin "$main" "$(fill "$T_FETCH" "<main>=$main" "<default>=$default")"
  runin "$main" "$(fill "$T_ADD" "<main>=$main" "<branch>=$BRANCH" "<name>=$PLAN" "<default>=$default")"
  runin "$main" "$T_LIST"
  printf '%s\n' "$OUT" | awk -v w="$main/.claude/worktrees/$PLAN" '$0 == "worktree " w {f=1; next} /^worktree /{f=0} f && /^branch /{print $2}'
}
for repo in alpha beta mods/ship; do
  got="$(worktree "$R/$repo")"
  [ "$got" = "refs/heads/$BRANCH" ] && ok "the worktree commands give $repo a $PLAN worktree on refs/heads/$BRANCH" || no "$repo worktree branch: $got $(cat "$T/err")"
done

AW="$R/alpha/.claude/worktrees/$PLAN"
PAY="$AW/vendor/acme/module-pay"; TAX="$AW/vendor/acme/module-tax"
git clone -q "$T/origins/pay.git" "$PAY"
git clone -q "$T/origins/tax.git" "$TAX"
HOOK_CMD="$(printf '%s' "$HOOKS" | jq -r '.PreToolUse[0].hooks[0].command')"

probe() { runin "$AW" "$(fill "$T_PROBE" "<payload>=$(fill "$T_PAYLOAD" "<m>=$1")" "<project wt>=$AW" "<main>=$R/alpha" "<hook command>=$HOOK_CMD")"; }
probe "$PAY"
[ "$RC" -eq 2 ] && ok "the edit probe exits 2 for a module path under vendor/" || no "probe under vendor/ (rc=$RC): $(cat "$T/err")"

probe "$AW/src"
[ "$RC" -eq 0 ] && ok "the edit probe exits 0 for a path outside vendor/" || no "probe outside vendor/ (rc=$RC): $(cat "$T/err")"

runin "$TAX" "$(fill "$T_MFETCH_DEFAULT" "<default>=main")"
runin "$TAX" "$(fill "$T_MNEW" "<branch>=$BRANCH" "<default>=main")"
{ [ "$(git -C "$TAX" branch --show-current)" = "$BRANCH" ] && [ "$(git -C "$TAX" rev-parse HEAD)" = "$(git --git-dir="$T/origins/tax.git" rev-parse main)" ]; } \
  && ok "the new-branch module commands put module-tax on $BRANCH at origin's default branch" || no "module-tax branch (rc=$RC): $(cat "$T/err")"

runin "$PAY" "$(fill "$T_MFETCH_BRANCH" "<branch>=$BRANCH")"
runin "$PAY" "$(fill "$T_MSWITCH" "<branch>=$BRANCH")"
{ [ "$(git -C "$PAY" branch --show-current)" = "$BRANCH" ] && [ "$(git -C "$PAY" rev-parse HEAD)" = "$(git --git-dir="$T/origins/pay.git" rev-parse "$BRANCH")" ]; } \
  && ok "the existing-branch module commands put module-pay on the branch origin holds" || no "module-pay branch (rc=$RC): $(cat "$T/err")"

printf 'alpha-new\n' > "$AW/a.txt"
printf 'pay-change\n' >> "$PAY/README"
printf 'tax-change\n' >> "$TAX/README"
printf 'beta-new\n' > "$R/beta/.claude/worktrees/$PLAN/b.txt"
printf 'ship-new\n' > "$R/mods/ship/.claude/worktrees/$PLAN/s.txt"

runin "$AW" "$(fill "$T_STATUS" "<path>=vendor/acme/module-pay") ':(exclude,top)vendor/acme/module-tax/'"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "?? a.txt" ]; } && ok "the nested-module status read lists no path under either module" || no "status read (rc=$RC): $OUT $(cat "$T/err")"

OUT="$(python3 "$CAP" --scratch "$T/scratch" --base HEAD --root "$R" --repo "$AW" --repo "$PAY" --repo "$TAX" \
  --repo "$R/beta/.claude/worktrees/$PLAN" --repo "$R/mods/ship/.claude/worktrees/$PLAN" 2>"$T/err")"
WANT="['alpha/.claude/worktrees/$PLAN/a.txt', 'alpha/.claude/worktrees/$PLAN/vendor/acme/module-pay/README', 'alpha/.claude/worktrees/$PLAN/vendor/acme/module-tax/README', 'beta/.claude/worktrees/$PLAN/b.txt', 'mods/ship/.claude/worktrees/$PLAN/s.txt']"
[ "$(python3 -c 'import json,sys; print(sorted(json.loads(sys.argv[1])["paths"]))' "$OUT" 2>/dev/null)" = "$WANT" ] \
  && ok "the five-root capture lists each edited path once under its own root's prefix" || no "five-root capture: $OUT $(cat "$T/err")"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
