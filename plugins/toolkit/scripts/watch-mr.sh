#!/usr/bin/env bash
# Waits on one MR or PR until a terminal condition and prints one status line; exit codes 0 and 10 to 16 are outcomes, 2 and 3 script failures.
set -uo pipefail

usage() {
  printf 'watch-mr: %s\nusage: watch-mr.sh <github|gitlab> <remotePath> <number> <pipeline|threads|review> --sha <sha> [--bound <n>] [--stuck <n>] [--settle <n>] [--none <n>] [--interval <seconds>] [--bot <login>]...\n' "$1" >&2
  exit 2
}
# Minutes by default, seconds with a trailing s.
to_secs() {
  [[ $2 =~ ^([0-9]+)(s?)$ ]] || usage "bad duration: $2"
  local n=$((10#${BASH_REMATCH[1]}))
  [ -n "${BASH_REMATCH[2]}" ] || n=$((n * 60))
  printf -v "$1" '%s' "$n"
}
finish() { printf '%s\n' "$2"; exit "$1"; }
command -v jq >/dev/null 2>&1 || { echo "watch-mr: jq not found on PATH" >&2; exit 3; }

[ $# -ge 4 ] || usage "missing arguments"
host=$1 path=$2 num=$3 mode=$4
shift 4
sha="" bound=180 stuck=10 settle=2 interval=30 bots='[]' none=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage "missing value for $1"
  case $1 in
    --sha) sha=$2 ;;
    --bound) bound=$2 ;;
    --stuck) stuck=$2 ;;
    --settle) settle=$2 ;;
    --none) none=$2 ;;
    --interval) interval=$2 ;;
    --bot) bots=$(jq -cn --argjson a "$bots" --arg b "$2" '$a + [$b]') ;;
    *) usage "unknown option: $1" ;;
  esac
  shift 2
done
case $host in github | gitlab) ;; *) usage "unknown host: $host" ;; esac
case $mode in pipeline | threads | review) ;; *) usage "unknown mode: $mode" ;; esac
[ -n "$sha" ] || usage "missing --sha"
[ -z "$none" ] || [ "$mode" = pipeline ] || usage "--none applies to pipeline mode only"
[ "$host$mode" != gitlabthreads ] || [ "$bots" != '[]' ] || usage "gitlab threads needs --bot, because GitLab notes carry no bot flag"
[[ $sha =~ ^[0-9a-fA-F]{7,64}$ ]] || usage "bad sha: $sha"
sha=$(tr 'A-F' 'a-f' <<<"$sha")
[[ $path =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+$ ]] || usage "bad remotePath: $path"
[[ $num =~ ^[0-9]+$ ]] || usage "bad number: $num"
[[ $interval =~ ^[0-9]+$ ]] || usage "bad interval: $interval"
interval=$((10#$interval)); [ "$interval" -ge 1 ] || interval=1
to_secs bound_s "$bound"
to_secs stuck_s "$stuck"
to_secs settle_s "$settle"
none_s=""
[ -z "$none" ] || to_secs none_s "$none"
enc=$(jq -rn --arg p "$path" '$p | @uri')

errf=$(mktemp) || { echo "watch-mr: cannot create a temp file" >&2; exit 3; }
trap 'rm -f "$errf"' EXIT
out="" mr="" at_bound=bound stuck_at="" full=$sha unrev=""
TS='def ts: capture("^(?<d>.{19})(?<f>\\.[0-9]+)?(Z|(?<sg>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2}))$")
  | (.d + "Z" | fromdateiso8601) + ("0" + (.f // "") | tonumber)
    - (if .sg then (if .sg == "-" then -1 else 1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60) else 0 end);
def nb: sub("\\[bot\\]$"; "");
def isbot: if ($bots | length) > 0 then ((.username // .login) | nb) as $l | any($bots[]; nb == $l) else (.bot == true) or (.type == "Bot") end;
# A Copilot refusal opens the body, so only its first 1000 characters are read; a CodeRabbit rate-limit note is keyed on its marker.
def refusal: (.body // "") as $b | first(
  ($b | .[0:1000] | gsub("\\s+"; " ") | capture("^ ?(?<t>Copilot [^.]{0,40}(was unable to review|wasn.t able to review any files in) this pull request[^.]*\\.?)"; "i").t),
  ($b | select(contains("rate limited by coderabbit.ai")) | capture("(?<t>[^.>]*has exceeded the limit for the number of commits or files that can be reviewed[^.]*[.])").t | ltrimstr(" ")));
def refused: [refusal] | length > 0;'

# Paginated output may arrive as several concatenated arrays, so slurp and merge.
get() {
  local raw
  raw=$("$@" 2>"$errf") && out=$(printf '%s' "$raw" | jq -cs 'add' 2>"$errf")
}
MARK='review in progress by coderabbit.ai'
q() { jq -r --arg s "$full" --arg mark "$MARK" --argjson bots "$bots" "$TS $1" <<<"$2" 2>"$errf"; }

stuck_check() {
  if [ "$1" = true ]; then
    [ -n "$stuck_at" ] || stuck_at=$SECONDS
    [ $((SECONDS - stuck_at)) -lt "$stuck_s" ] || finish 11 "STUCK $sha $(((SECONDS - stuck_at) / 60))"
  else
    stuck_at=""
  fi
}

# A short --sha matches the head by prefix; once seen, the full head is what later rounds and reads compare against.
same_head() {
  [[ $1 =~ ^[0-9a-f]{40,64}$ ]] || { echo "watch-mr: unexpected head sha: $1" >"$errf"; return 1; }
  [[ $1 == "$full"* ]] || finish 14 "MOVED $sha $1"
  full=$1
}

gitlab_mr() {
  get glab api "projects/$enc/merge_requests/$num" || return 1
  mr=$out
  local head
  head=$(q '.sha' "$mr") || return 1
  same_head "$head" || return 1
}

github_head() {
  get gh pr view "$num" -R "$path" --json headRefOid || return 1
  local head
  head=$(q '.headRefOid' "$out") || return 1
  same_head "$head" || return 1
}

gitlab_pipeline() {
  gitlab_mr || return 1
  local pid st names held
  pid=$(q 'if .head_pipeline.sha == $s then .head_pipeline.id else "" end' "$mr") || return 1
  if [ -z "$pid" ]; then at_bound=none stuck_at=""; return 0; fi
  at_bound=bound
  st=$(q '.head_pipeline.status' "$mr") || return 1
  case $st in
    success) finish 0 "GREEN $sha" ;;
    skipped) finish 13 "NONE $sha" ;;
  esac
  get glab api "projects/$enc/pipelines/$pid/jobs?per_page=100" --paginate || return 1
  if [ "$st" = failed ] || [ "$st" = canceled ]; then
    names=$(q '[.[] | select((.status == "failed" or .status == "canceled") and .allow_failure == false) | .name | gsub("[\\r\\n]"; " ")] | join(",")' "$out") || return 1
    finish 10 "RED $sha${names:+ $names}"
  fi
  held=$(q '[.[] | select(.stage != "external")] | length > 0 and all(.status | IN("success", "failed", "canceled", "skipped", "manual"))' "$out") || return 1
  stuck_check "$held"
}

github_pipeline() {
  github_head || return 1
  local checks names count pending held
  if ! get gh pr checks "$num" -R "$path" --json name,bucket; then
    grep -q 'no checks reported' "$errf" || return 1
    out='[]'
  fi
  checks=$out
  count=$(q 'length' "$checks") || return 1
  if [ "$count" = 0 ]; then at_bound=none stuck_at=""; return 0; fi
  at_bound=bound
  names=$(q '[.[] | select(.bucket == "fail" or .bucket == "cancel") | .name | gsub("[\\r\\n]"; " ")] | join(",")' "$checks") || return 1
  [ -z "$names" ] || finish 10 "RED $sha $names"
  pending=$(q 'any(.[]; .bucket == "pending")' "$checks") || return 1
  [ "$pending" = true ] || finish 0 "GREEN $sha"
  get gh run list --commit "$full" -R "$path" --limit 100 --json status,conclusion || return 1
  held=$(q 'length > 0 and all(.[]; .status == "completed")' "$out") || return 1
  stuck_check "$held"
}

# Lands the first listed-bot note from the anchor on that is neither an in-progress note nor a refusal, else keeps the first refusal in unrev; $1 is the notes JSON, and gl_notes keeps those listed-bot notes.
gl_landed() {
  local anchor who
  anchor=$(q 'if .head_pipeline.sha == $s then .head_pipeline.created_at else "" end' "$mr") || return 1
  if [ -z "$anchor" ]; then
    get glab api "projects/$enc/repository/commits/$full" || return 1
    anchor=$(q '.committed_date' "$out") || return 1
  fi
  gl_notes=$(jq -c --arg a "$anchor" --arg s "$full" --arg mark "$MARK" --argjson bots "$bots" "$TS"' ($a | ts) as $t | [.[] | select(.system == false and (.author | isbot) and ((.body // "") | contains($mark) | not) and (.created_at | ts) >= $t and (.position.head_sha // $s) == $s)]' <<<"$1" 2>"$errf") || return 1
  who=$(q 'first(.[] | select(refused | not) | .author.username) // empty' "$gl_notes") || return 1
  [ -z "$who" ] || finish 0 "LANDED $sha $who"
  unrev=$(q 'first(.[] | select(refused) | "\(.author.username) \(refusal)") // empty' "$gl_notes") || return 1
}

# Lands the first bot review on the head that is not a refusal, else keeps the first refusal there in unrev. $1 is the reviews JSON.
gh_landed() {
  local who
  who=$(q 'first(.[] | select(.commit_id == $s and (.user | isbot) and (refused | not)) | .user.login) // empty' "$1") || return 1
  [ -z "$who" ] || finish 0 "LANDED $sha $who"
  unrev=$(q 'first(.[] | select(.commit_id == $s and (.user | isbot) and refused) | "\(.user.login) \(refusal)") // empty' "$1") || return 1
}

gitlab_threads() {
  gitlab_mr || return 1
  local all
  get glab api "projects/$enc/merge_requests/$num/notes?per_page=100" --paginate || return 1
  gl_landed "$out" || return 1
  all=$(q '[.[] | select(refused) | .author.username | nb] as $r | all($bots[]; nb | IN($r[]))' "$gl_notes") || return 1
  [ "$all" = false ] || finish 16 "UNREVIEWED $sha $unrev"
}

github_threads() {
  github_head || return 1
  local all
  get gh api "repos/$path/pulls/$num/reviews" --paginate || return 1
  gh_landed "$out" || return 1
  # A refusal ends the wait at once only when every listed bot refused, because another listed bot may still review.
  all=$(q '[.[] | select(.commit_id == $s and refused) | .user.login | nb] as $r | ($bots | length) > 0 and all($bots[]; nb | IN($r[]))' "$out") || return 1
  [ "$all" = false ] || finish 16 "UNREVIEWED $sha $unrev"
}

quiet_at=""
# A review is over once no comment has carried the marker for the whole --settle window.
quiet_check() {
  if [ "$1" = true ]; then quiet_at=""; return 0; fi
  [ -n "$quiet_at" ] || quiet_at=$SECONDS
  [ $((SECONDS - quiet_at)) -lt "$settle_s" ] && return 0
  [ -z "$unrev" ] || finish 16 "UNREVIEWED $sha $unrev"
  finish 15 "QUIET $sha $(((SECONDS - quiet_at) / 60))"
}

github_review() {
  github_head || return 1
  local busy
  get gh api "repos/$path/issues/$num/comments" --paginate || return 1
  busy=$(q 'any(.[]; (.user | isbot) and ((.body // "") | contains($mark)))' "$out") || return 1
  unrev=""
  if [ "$busy" = false ]; then
    get gh api "repos/$path/pulls/$num/reviews" --paginate || return 1
    gh_landed "$out" || return 1
  fi
  quiet_check "$busy"
}

gitlab_review() {
  gitlab_mr || return 1
  local busy notes
  get glab api "projects/$enc/merge_requests/$num/notes?per_page=100" --paginate || return 1
  notes=$out
  busy=$(q 'any(.[]; .system == false and ((.body // "") | contains($mark)) and ($bots == [] or (.author | isbot)))' "$notes") || return 1
  unrev=""
  if [ "$busy" = false ] && [ "$bots" != '[]' ]; then gl_landed "$notes" || return 1; fi
  quiet_check "$busy"
}

fails=0
while :; do
  if "${host}_${mode}"; then
    fails=0
  else
    fails=$((fails + 1))
    if [ "$fails" -ge 5 ]; then
      { echo "watch-mr: five rounds in a row failed, last error:"; cat "$errf"; } >&2
      exit 3
    fi
  fi
  [ -n "$none_s" ] && [ "$at_bound" = none ] && [ "$SECONDS" -ge "$none_s" ] && finish 13 "NONE $sha"
  if [ "$SECONDS" -ge "$bound_s" ]; then
    [ "$at_bound" = none ] && finish 13 "NONE $sha"
    [ -z "$unrev" ] || finish 16 "UNREVIEWED $sha $unrev"
    finish 12 "BOUND $sha $((SECONDS / 60))"
  fi
  left=$((bound_s - SECONDS))
  sleep "$((interval < left ? interval : left))"
done
