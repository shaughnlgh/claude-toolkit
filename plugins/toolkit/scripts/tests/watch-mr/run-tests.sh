#!/usr/bin/env bash
# Hermetic behavior suite for watch-mr.sh. Stub gh and glab executables on PATH answer
# from per-case fixture files, keyed by argument pattern with a per-pattern round counter,
# so a case can change its answer between polling rounds. No network. Everything lives
# under a mktemp dir cleaned on exit.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$HERE/../../watch-mr.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

W="$(mktemp -d -t watchmr)"
trap 'rm -rf "$W"' EXIT
export GITLAB_TOKEN=fake-gl-token-123 GH_TOKEN=fake-gh-token-456
SHA=1111111111111111111111111111111111111111
NEW=2222222222222222222222222222222222222222
ALT=1111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export SHA

# The stub answers <key>.<round> before <key>; a .err file answers on stderr with exit 1.
mkdir "$W/bin"
cat > "$W/bin/stub" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$CASE/calls"
case "$(basename "$0") $*" in
  "glab api projects/g%2Fsub%2Fr/merge_requests/7") k=mr ;;
  "glab api projects/g%2Fsub%2Fr/pipelines/55/jobs?per_page=100 --paginate") k=jobs ;;
  "glab api projects/g%2Fsub%2Fr/merge_requests/7/notes?per_page=100 --paginate") k=notes ;;
  "glab api projects/g%2Fsub%2Fr/repository/commits/$SHA") k=commit ;;
  "gh pr view 7 -R o/r --json headRefOid") k=head ;;
  "gh pr checks 7 -R o/r --json name,bucket") k=checks ;;
  "gh run list --commit $SHA -R o/r --limit 100 --json status,conclusion") k=runs ;;
  "gh api repos/o/r/pulls/7/reviews --paginate") k=reviews ;;
  "gh api repos/o/r/issues/7/comments --paginate") k=comments ;;
  *) echo "stub: unexpected call: $(basename "$0") $*" >&2; exit 1 ;;
esac
n=$(( $(cat "$CASE/.n.$k" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CASE/.n.$k"
for f in "$k.$n" "$k"; do
  [ -f "$CASE/$f.err" ] && { cat "$CASE/$f.err" >&2; exit 1; }
  [ -f "$CASE/$f" ] && { cat "$CASE/$f"; exit 0; }
done
echo "stub: no fixture for $k" >&2; exit 1
STUB
chmod +x "$W/bin/stub"; cp "$W/bin/stub" "$W/bin/gh"; cp "$W/bin/stub" "$W/bin/glab"
export PATH="$W/bin:$PATH"

# new: fresh case dir in $C; fx <file> <content>: one fixture file
new() { C="$(mktemp -d "$W/case.XXXXXX")"; }
fx() { printf '%s\n' "$2" > "$C/$1"; }
run() { CASE="$C" bash "$WATCH" "$@" >"$C/out" 2>"$C/err"; rc=$?; cat "$C/out" "$C/err" >> "$W/all"; }
# expect <name> <exit> <line> <args...>: exit code, exact stdout line, exactly one line
expect() {
  local name=$1 want_rc=$2 want=$3; shift 3
  run "$@"
  local got lines; got=$(cat "$C/out"); lines=$(wc -l < "$C/out" | tr -d ' ')
  { [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ] && [ "$lines" = 1 ]; } && ok "$name" || no "$name (exit $rc, stdout '$got', $lines lines, stderr '$(head -c 200 "$C/err")')"
}
# expect_err <name> <exit> <stderr substring> <args...>: exit code, empty stdout, stderr names the cause
expect_err() {
  local name=$1 want_rc=$2 needle=$3; shift 3
  run "$@"
  { [ "$rc" = "$want_rc" ] && [ ! -s "$C/out" ] && grep -qF -- "$needle" "$C/err"; } && ok "$name" || no "$name (exit $rc, stdout '$(cat "$C/out")', stderr '$(head -c 200 "$C/err")')"
}

GL=(gitlab g/sub/r 7)
GH=(github o/r 7)
glmr() { printf '{"sha":"%s","head_pipeline":{"id":55,"sha":"%s","status":"%s","created_at":"2026-10-01T08:00:00.000-02:00"}}' "${3:-$SHA}" "${2:-$SHA}" "$1"; }
job() { printf '{"name":"%s","stage":"%s","status":"%s","allow_failure":%s}' "$1" "$2" "$3" "${4:-false}"; }
note() { printf '{"system":%s,"created_at":"%s","author":{"username":"%s","bot":%s},"body":"%s"}' "$1" "$2" "$3" "$4" "${5:-}"; }
ghuser() { printf '{"login":"%s","type":"%s"}' "$1" "$2"; }
ghcomment() { printf '{"user":%s,"body":"%s"}' "$(ghuser "$1" "$2")" "$3"; }
ghreview() { printf '{"commit_id":"%s","user":%s,"body":"%s"}' "$1" "$(ghuser "$2" Bot)" "$3"; }
COPILOT='copilot-pull-request-reviewer[bot]'
QUOTA='Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.'
ERRORED='Copilot encountered an error and was unable to review this pull request.\nYou can try again by re-requesting a review.'
NOFILES="Copilot wasn't able to review any files in this pull request."
# The live CodeRabbit summary comment carries this marker line while a review runs.
BUSY='<!-- This is an auto-generated comment: review in progress by coderabbit.ai -->\n\nCurrently processing new changes in this PR.'
DONE='<!-- This is an auto-generated comment: summarize by coderabbit.ai -->\n\nWalkthrough.'

echo "== usage errors =="
new; expect_err "missing --sha exits 2" 2 "missing --sha" "${GL[@]}" pipeline --interval 1
new; expect_err "unknown host exits 2" 2 "unknown host" bitbucket o/r 7 pipeline --sha "$SHA"
new; expect_err "unknown mode exits 2" 2 "unknown mode" "${GH[@]}" reviews --sha "$SHA"
new; expect_err "non-numeric number exits 2" 2 "bad number" github o/r seven pipeline --sha "$SHA"
new; CASE="$C" PATH="$W/bin" "$BASH" "$WATCH" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 2s >"$C/out" 2>"$C/err"; rc=$?
{ [ "$rc" = 3 ] && [ ! -s "$C/out" ] && grep -qF "jq not found" "$C/err"; } && ok "no jq on PATH exits 3 before any API call" || no "no jq on PATH exits 3 before any API call (exit $rc, stdout '$(cat "$C/out")')"
new; expect_err "non-numeric bound exits 2" 2 "bad duration" "${GH[@]}" pipeline --sha "$SHA" --bound ten
new; expect_err "a non-hex sha exits 2" 2 "bad sha" "${GH[@]}" pipeline --sha zzzzzzz
new; expect_err "a remotePath with a space exits 2" 2 "bad remotePath" github "o/r r" 7 pipeline --sha "$SHA"
new; expect_err "--none outside pipeline mode exits 2" 2 "--none applies to pipeline mode only" "${GH[@]}" review --sha "$SHA" --none 2

echo "== gitlab pipeline =="
new; fx mr "$(glmr success)"
expect "success is GREEN" 0 "GREEN $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr "$(glmr manual)"; fx jobs "[$(job unit test success),$(job deploy deploy manual)]"
expect "a manual pipeline is not terminal and is BOUND" 12 "BOUND $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 2s
new; fx mr "$(glmr failed)"; fx jobs "[$(job build build failed),$(job lint test failed true),$(job unit test success),$(job deploy deploy canceled)]"
expect "failed is RED naming failed and cancelled jobs, not allow_failure ones" 10 "RED $SHA build,deploy" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr.1 "$(glmr skipped)"; fx mr "$(glmr success)"
expect "skipped is NONE on the first round" 13 "NONE $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr "{\"sha\":\"$SHA\",\"head_pipeline\":null}"
expect "no pipeline is NONE at the bound" 13 "NONE $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 2s
new; fx mr.1 "{\"sha\":\"$SHA\",\"head_pipeline\":null}"; fx mr "$(glmr success)"
expect "a pipeline that appears inside the --none window is watched to GREEN" 0 "GREEN $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --none 3s --bound 30s
new; fx mr.1 "$(glmr running)"; fx mr "$(glmr success)"; fx jobs "[$(job unit test running)]"
expect "running then success is GREEN" 0 "GREEN $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr "$(glmr running)"; fx jobs "[$(job unit test success),$(job lint test skipped),$(job coderabbit external running)]"
expect "terminal jobs with a hung external job are STUCK" 11 "STUCK $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s
new; fx mr "$(glmr running)"; fx jobs "[$(job unit test success),$(job lint test skipped),$(job coderabbit external running)]"
expect "the same jobs inside the stuck window are BOUND" 12 "BOUND $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --stuck 60 --bound 2s
new; fx mr "$(glmr running)"; fx jobs "[$(job unit test success),$(job e2e test running)]"
expect "a running job at the bound is BOUND" 12 "BOUND $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s --bound 2s
new; fx mr.1 "$(glmr success "$SHA" "$NEW")"; fx mr "$(glmr success)"
expect "a different MR sha is MOVED on the first round" 14 "MOVED $SHA $NEW" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr "$(glmr running)"; fx jobs '[]'
expect "an empty job list on a running pipeline is BOUND, not STUCK" 12 "BOUND $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s --bound 2s
new; fx mr "$(glmr running)"; fx jobs "[$(job coderabbit external running)]"
expect "only external-stage jobs on a running pipeline is BOUND, not STUCK" 12 "BOUND $SHA 0" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s --bound 2s
new; fx mr "$(glmr failed)"; printf '[%s]\n[%s]\n' "$(job build build failed)" "$(job deploy deploy canceled)" > "$C/jobs"
expect "paginated job pages merge and RED names jobs from both pages" 10 "RED $SHA build,deploy" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr "$(glmr running)"; fx jobs "[$(job e2e test running)]"
run "${GL[@]}" pipeline --sha "$SHA" --interval 0 --bound 2s
{ [ "$rc" = 12 ] && [ "$(cat "$C/.n.mr")" -le 4 ]; } && ok "--interval 0 polls at most once a second" || no "--interval 0 polls at most once a second (exit $rc, $(cat "$C/.n.mr") rounds)"
new; fx mr.1.err "connection reset by peer"; fx mr "$(glmr success)"
expect "a transient failure then success is GREEN" 0 "GREEN $SHA" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx mr.err "HTTP 502 bad gateway"
expect_err "five failed rounds exit 3 with the last error" 3 "HTTP 502 bad gateway" "${GL[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s

echo "== github pipeline =="
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pass"},{"name":"docs","bucket":"skipping"}]'
expect "passing checks are GREEN" 0 "GREEN $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pass"},{"name":"test","bucket":"fail"},{"name":"e2e","bucket":"cancel"},{"name":"lint","bucket":"pending"}]'
expect "a failed check is RED naming failed and cancelled checks" 10 "RED $SHA test,e2e" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks.1 '[{"name":"ci","bucket":"pending"}]'; fx checks '[{"name":"ci","bucket":"pass"}]'; fx runs '[{"status":"in_progress","conclusion":""}]'
expect "pending then pass is GREEN" 0 "GREEN $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pass"},{"name":"CodeRabbit","bucket":"pending"}]'; fx runs '[{"status":"completed","conclusion":"success"}]'
expect "completed runs with a pending check are STUCK" 11 "STUCK $SHA 0" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s
new; fx head.1 "{\"headRefOid\":\"$NEW\"}"; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pass"}]'
expect "a different headRefOid is MOVED on the first round" 14 "MOVED $SHA $NEW" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"circleci","bucket":"pending"}]'; fx runs '[]'
expect "no Actions runs with a pending check is BOUND, not STUCK" 12 "BOUND $SHA 0" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pending"}]'; fx runs '[{"status":"in_progress","conclusion":""}]'
expect "an in-progress Actions run with a pending check is BOUND, not STUCK" 12 "BOUND $SHA 0" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --stuck 0s --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"unit\ntests","bucket":"fail"}]'
expect "a check name with a newline stays on one status line" 10 "RED $SHA unit tests" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 30s
new; fx head '{"headRefOid":"abcdef0123456789abcdef0123456789abcdef01"}'; fx checks '[{"name":"ci","bucket":"pass"}]'
expect "an uppercase --sha matches the lowercase head" 0 "GREEN abcdef0123456789abcdef0123456789abcdef01" "${GH[@]}" pipeline --sha ABCDEF0123456789ABCDEF0123456789ABCDEF01 --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks.err "no checks reported on the 'feat' branch"
expect "no checks reported is NONE at the bound" 13 "NONE $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[]'
expect "an empty checks list is NONE at the bound" 13 "NONE $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks.1 '[]'; fx checks '[{"name":"ci","bucket":"pass"}]'
expect "a check that appears inside the --none window is watched to GREEN" 0 "GREEN $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --none 3s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks.1 '[]'; fx checks.2 '[]'; fx checks.3 '[]'; fx checks '[{"name":"ci","bucket":"pass"}]'
expect "no checks is NONE once --none passes, before a later check" 13 "NONE $SHA" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --none 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx checks '[{"name":"ci","bucket":"pending"}]'; fx runs '[{"status":"in_progress","conclusion":""}]'
expect "a pending check seen before --none runs on to BOUND" 12 "BOUND $SHA 0" "${GH[@]}" pipeline --sha "$SHA" --interval 1 --none 1s --bound 3s

echo "== gitlab threads =="
new; expect_err "gitlab threads without --bot exits 2" 2 "gitlab threads needs --bot" "${GL[@]}" threads --sha "$SHA" --interval 1
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z alice false),$(note false 2026-10-01T10:31:00.000Z review-svc false)]"
expect "a --bot login note is LANDED" 0 "LANDED $SHA review-svc" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot review-svc
new; fx mr "$(glmr running)"; fx notes "[$(note true 2026-10-01T10:30:00.000Z coderabbitai true)]"
expect "a bot system note is not landed" 12 "BOUND $SHA 0" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot coderabbitai
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T09:00:00.000Z coderabbitai true)]"
expect "a bot note before the pipeline anchor is not landed" 12 "BOUND $SHA 0" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot coderabbitai
new; fx mr "{\"sha\":\"$SHA\",\"head_pipeline\":null}"; fx commit '{"committed_date":"2026-10-01T12:00:00.000+02:00"}'; fx notes "[$(note false 2026-10-01T10:30:00.000Z coderabbitai true)]"
expect "without a pipeline the commit date anchors and a later bot note is LANDED" 0 "LANDED $SHA coderabbitai" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot coderabbitai
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z sonar true),$(note false 2026-10-01T10:31:00.000Z coderabbitai false)]"
expect "under --bot only the listed login's note is LANDED, an unlisted bot note is skipped" 0 "LANDED $SHA coderabbitai" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot coderabbitai
new; fx mr "$(glmr running)"; fx notes "[{\"system\":false,\"created_at\":\"2026-10-01T10:30:00.000Z\",\"author\":{\"username\":\"coderabbitai\"},\"position\":{\"head_sha\":\"$NEW\"}}]"
expect "a listed login's DiffNote on an earlier commit is not landed" 12 "BOUND $SHA 0" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot coderabbitai
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z coderabbitai false "$BUSY")]"
expect "gitlab threads skips a listed note that carries the in-progress marker" 12 "BOUND $SHA 0" "${GL[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot coderabbitai

echo "== github threads =="
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a Bot review on the sha is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$NEW\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a Bot review on another sha is not landed" 12 "BOUND $SHA 0" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$NEW\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "the listed login's review on an earlier commit under --bot is BOUND" 12 "BOUND $SHA 0" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot 'coderabbitai[bot]'
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a bare --bot login lands the [bot]-suffixed review" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot coderabbitai
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'github-actions[bot]' Bot)}]"
expect "an unlisted Bot review on the sha under --bot is BOUND" 12 "BOUND $SHA 0" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot 'coderabbitai[bot]'
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'github-actions[bot]' Bot)},{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "the listed login's review on the sha is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot 'coderabbitai[bot]'
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a short --sha matches the head by prefix and the review on the full sha" 0 "LANDED 1111111 coderabbitai[bot]" "${GH[@]}" threads --sha 1111111 --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[{\"commit_id\":\"1111111\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a review whose commit_id is the literal short sha is not landed" 12 "BOUND 1111111 0" "${GH[@]}" threads --sha 1111111 --interval 1 --bound 2s
new; fx head.1 "{\"headRefOid\":\"$SHA\"}"; fx head "{\"headRefOid\":\"$ALT\"}"; fx reviews '[]'
expect "a new head sharing the short prefix in round two is MOVED" 14 "MOVED 1111111 $ALT" "${GH[@]}" threads --sha 1111111 --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews.1 "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA"),$(ghreview "$SHA" "$COPILOT" Overview.)]"
expect "a refusal from the only listed bot is UNREVIEWED in round one" 16 "UNREVIEWED $SHA $COPILOT $QUOTA" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot copilot-pull-request-reviewer
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews.1 "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA"),$(ghreview "$SHA" 'coderabbitai[bot]' Walkthrough.)]"
expect "a refusal from one listed bot waits for the other listed bot's review in a later round" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot copilot-pull-request-reviewer --bot coderabbitai
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"
expect "a refusal from one of two listed bots is UNREVIEWED at the bound" 16 "UNREVIEWED $SHA $COPILOT $QUOTA" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 3s --bot copilot-pull-request-reviewer --bot coderabbitai
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$ERRORED")]"
expect "a refusal with no --bot is UNREVIEWED at the bound with its text cut after the refusal sentence" 16 "UNREVIEWED $SHA $COPILOT Copilot encountered an error and was unable to review this pull request." "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "## Pull request overview\\nThis PR treats a review that says Copilot was unable to review this pull request as no review.")]"
expect "a real review that quotes the refusal wording past its opening is LANDED" 0 "LANDED $SHA $COPILOT" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s --bot copilot-pull-request-reviewer
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA"),$(ghreview "$SHA" 'coderabbitai[bot]' Walkthrough.)]"
expect "a real bot review after a refusal on the sha is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$NEW" "$COPILOT" "$QUOTA")]"
expect "a refusal on another sha is BOUND" 12 "BOUND $SHA 0" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"
expect "a refusal by an unlisted bot under --bot is BOUND" 12 "BOUND $SHA 0" "${GH[@]}" threads --sha "$SHA" --interval 1 --bound 2s --bot coderabbitai

echo "== github review =="
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx reviews '[]'
expect "a Bot comment with the marker keeps the wait busy until BOUND" 12 "BOUND $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 1s --bound 3s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments '[]'; fx reviews '[]'
expect "no marker and no review is QUIET after the settle window" 15 "QUIET $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$DONE")]"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "no marker and a Bot review on the head is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments.1 "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$DONE")]"; fx reviews '[]'
expect "the marker in round one and gone in round two ends QUIET" 15 "QUIET $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments "[$(ghcomment alice User "$BUSY")]"; fx reviews '[]'
expect "the marker in a comment by a non-Bot user is ignored" 15 "QUIET $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments '[]'; fx reviews.1 '[]'; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a Bot review that lands inside the settle window is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 3s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments '[]'; fx reviews "[{\"commit_id\":\"$NEW\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a Bot review on an earlier commit is QUIET, not LANDED" 15 "QUIET $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a Bot review on the head while the marker is present stays busy until BOUND" 12 "BOUND $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 1s --bound 3s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments.1 '[]'; fx comments.2 "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx comments.3 "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx comments '[]'
fx reviews.1 '[]'; fx reviews.2 '[]'; fx reviews "[{\"commit_id\":\"$SHA\",\"user\":$(ghuser 'coderabbitai[bot]' Bot)}]"
expect "a marker after a quiet poll restarts the settle window" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$NEW\"}"; fx comments '[]'; fx reviews '[]'
expect "a moved head in review mode is MOVED" 14 "MOVED $SHA $NEW" "${GH[@]}" review --sha "$SHA" --interval 1 --bound 30s
new; expect_err "a bad --settle exits 2" 2 "bad duration" "${GH[@]}" review --sha "$SHA" --settle soon
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments '[]'; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$NOFILES")]"
expect "a refusal with no marker is UNREVIEWED after the settle window" 16 "UNREVIEWED $SHA $COPILOT $NOFILES" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments '[]'; fx reviews.1 "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"; fx reviews.2 "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"
fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA"),$(ghreview "$SHA" 'coderabbitai[bot]' Walkthrough.)]"
expect "a real review that lands inside the settle window after a refusal is LANDED" 0 "LANDED $SHA coderabbitai[bot]" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 3s --bound 30s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"
expect "a marker beside a refusal keeps the wait busy until BOUND" 12 "BOUND $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 1s --bound 3s
new; fx head "{\"headRefOid\":\"$SHA\"}"; fx comments.1 '[]'; fx comments "[$(ghcomment 'coderabbitai[bot]' Bot "$BUSY")]"; fx reviews "[$(ghreview "$SHA" "$COPILOT" "$QUOTA")]"
expect "a refusal read in a quiet round does not survive a later busy round to the bound" 12 "BOUND $SHA 0" "${GH[@]}" review --sha "$SHA" --interval 1 --settle 3s --bound 4s

echo "== gitlab review =="
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z coderabbitai false "$BUSY")]"
expect "a gitlab note with the marker keeps the wait busy until BOUND" 12 "BOUND $SHA 0" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 1s --bound 3s
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z coderabbitai false "$DONE")]"
expect "gitlab review without --bot runs and ends QUIET" 15 "QUIET $SHA 0" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z alice false),$(note false 2026-10-01T10:31:00.000Z review-svc false)]"
expect "gitlab review with --bot lands a listed note" 0 "LANDED $SHA review-svc" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s --bot review-svc
new; fx mr "$(glmr running)"; fx notes.1 '[]'; fx notes "[$(note false 2026-10-01T10:31:00.000Z review-svc false)]"
expect "gitlab review lands a listed note that arrives inside the settle window" 0 "LANDED $SHA review-svc" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 3s --bound 30s --bot review-svc
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T09:00:00.000Z review-svc false)]"
expect "gitlab review with --bot skips a listed note before the pipeline anchor and ends QUIET" 15 "QUIET $SHA 0" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s --bot review-svc
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z coderabbitai false "$BUSY"),$(note false 2026-10-01T10:31:00.000Z coderabbitai false)]"
expect "a listed note on the head while the marker is present stays busy until BOUND" 12 "BOUND $SHA 0" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 1s --bound 3s --bot coderabbitai
new; fx mr "$(glmr running)"; fx notes "[$(note false 2026-10-01T10:30:00.000Z alice false "$BUSY")]"
expect "under --bot the marker in an unlisted author's note is ignored" 15 "QUIET $SHA 0" "${GL[@]}" review --sha "$SHA" --interval 1 --settle 2s --bound 30s --bot coderabbitai

echo "== secrets =="
grep -qE 'fake-gl-token-123|fake-gh-token-456' "$W/all" "$W"/case.*/calls && no "a token value reached output or a CLI argument" || ok "no token value in any output or CLI argument"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
