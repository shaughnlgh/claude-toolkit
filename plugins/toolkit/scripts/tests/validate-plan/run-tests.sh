#!/usr/bin/env bash
# Behavior tests for validate-plan.py. One line per case:
#   <fixture path relative to fixtures/> | <expected exit> | <expected output substring>
# A literal "-" substring means "no specific message asserted".
# Case 13 (nonexistent path) is invoked directly, not via a fixture file.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="$HERE/../../validate-plan.py"
FX="$HERE/fixtures"
PASS=0; FAIL=0

run() { # $1 name, $2 path, $3 expected exit, $4 substring
  local out actual
  out="$(python3 "$V" "$2" 2>&1)"; actual=$?
  if [ "$actual" -eq "$3" ] && { [ "$4" = "-" ] || case "$out" in *"$4"*) true;; *) false;; esac; }; then
    printf '  PASS  %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  FAIL  %s (exit %s, wanted %s)\n        %s\n' "$1" "$actual" "$3" "$(printf '%s' "$out" | head -3)"
    FAIL=$((FAIL+1))
  fi
}

run "01 valid normal plan (blank modules:/repos: present)" "$FX/2026-01-01-example-feature/plan - example-feature.md" 0 "OK:"
run "02a valid parent plan" "$FX/2026-01-02-example-parent/plan - example-parent.md" 0 "OK:"
run "02b valid child plan (slug differs from dir suffix)" "$FX/2026-01-02-example-parent/plan - example-child.md" 0 "OK:"
run "03 valid nested modules/repos/sessions" "$FX/2026-01-03-nested-feature/plan - nested-feature.md" 0 "OK:"
run "04 missing required frontmatter key" "$FX/2026-01-04-missing-key/plan - missing-key.md" 1 "missing required frontmatter key: status"
run "05 invalid slug" "$FX/2026-01-05-badslug/plan - Bad_Slug.md" 1 "must match"
run "06 filename/frontmatter mismatch" "$FX/2026-01-06-mismatch/plan - mismatch.md" 1 "does not match filename slug"
run "07 invalid status" "$FX/2026-01-07-badstatus/plan - badstatus.md" 1 "not a lifecycle value"
run "08 duplicate nonblank session id" "$FX/2026-01-08-dupsession/plan - dupsession.md" 1 "duplicate session id"
run "09 multiple blank session ids accepted" "$FX/2026-01-09-blankids/plan - blankids.md" 0 "OK:"
run "10 missing required heading" "$FX/2026-01-10-noheading/plan - noheading.md" 1 "missing required heading: ## Rollback Notes"
run "11 retired mr-description link" "$FX/2026-01-11-retired/plan - retired.md" 1 "retired mr-description artifact"
run "12 malformed/unsupported frontmatter" "$FX/2026-01-12-malformed/plan - malformed.md" 2 "block scalars are not supported"
run "13 nonexistent path" "$FX/does-not-exist/plan - nope.md" 2 "not an existing regular file"
run "14 unknown extra frontmatter keys accepted" "$FX/2026-01-14-extrakeys/plan - extrakeys.md" 0 "OK:"
run "15 unknown key with block scalar tolerated (MC worklogs)" "$FX/2026-01-15-worklogs/plan - worklogs.md" 0 "OK:"
run "16 missing modules key is a violation" "$FX/2026-01-16-nomodules/plan - nomodules.md" 1 "missing required frontmatter key: modules"
run "17 missing repos key is a violation" "$FX/2026-01-17-norepos/plan - norepos.md" 1 "missing required frontmatter key: repos"
run "18 headings only inside a code fence do not count" "$FX/2026-01-01-codefence/plan - codefence.md" 1 "missing required heading"
run "19 status as a list is rejected" "$FX/2026-01-01-statuslist/plan - statuslist.md" 1 "status: must be a single lifecycle value, not a list"
run "20 retired mr-description link with double space caught" "$FX/2026-01-01-mrdash/plan - mrdash.md" 1 "retired mr-description artifact"
run "21 distinct mr-description-notes artifact is allowed" "$FX/2026-01-01-mrnotes/plan - mrnotes.md" 0 "OK:"
run "22 headings in a fence with a LONGER closing fence do not count" "$FX/2026-01-01-longfence/plan - longfence.md" 1 "missing required heading"
run "23 headings after an UNCLOSED fence do not count" "$FX/2026-01-01-unclosedfence/plan - unclosedfence.md" 1 "missing required heading"
run "24 post-adoption plan with Plain Language Summary present" "$FX/2026-08-27-pls-present/plan - pls-present.md" 0 "OK:"
run "25 post-adoption plan missing only Plain Language Summary" "$FX/2026-08-27-pls-missing/plan - pls-missing.md" 1 "missing required heading: ## Plain Language Summary"
run "26 created == SINCE date is NOT grandfathered (boundary)" "$FX/2026-08-26-pls-boundary/plan - pls-boundary.md" 1 "missing required heading: ## Plain Language Summary"
run "27 created one day before SINCE date is grandfathered" "$FX/2026-08-25-pls-grandfathered/plan - pls-grandfathered.md" 0 "OK:"
run "28 blank created is NOT grandfathered" "$FX/2026-08-27-pls-unparseable-created/plan - pls-unparseable-created.md" 1 "missing required heading: ## Plain Language Summary"
run "29 Plain Language Summary only inside a fence (plus unfenced prose mention) does not count" "$FX/2026-08-27-pls-fenced/plan - pls-fenced.md" 1 "missing required heading: ## Plain Language Summary"
run "30 malformed non-blank created (sorts lexicographically low) is NOT grandfathered" "$FX/2026-08-27-pls-malformed-created/plan - pls-malformed-created.md" 1 "missing required heading: ## Plain Language Summary"
run "31 completed plan with a Remember: line" "$FX/2026-10-18-completed-remembered/plan - completed-remembered.md" 0 "OK:"
run "32 completed plan without a Remember: line" "$FX/2026-10-18-completed-unremembered/plan - completed-unremembered.md" 1 "status completed requires a Remember: line"
run "33 completed plan created before the Remember: line date is grandfathered" "$FX/2026-01-05-completed-grandfathered/plan - completed-grandfathered.md" 0 "OK:"
run "34 completed plan with a bare Remember: line (no bullet)" "$FX/2026-10-18-completed-bare/plan - completed-bare.md" 0 "OK:"
run "35 Remember: line only inside a fence does not count" "$FX/2026-10-18-completed-fenced/plan - completed-fenced.md" 1 "status completed requires a Remember: line"
run "36 Remember: line only under another heading does not count" "$FX/2026-10-18-completed-wrongsection/plan - completed-wrongsection.md" 1 "status completed requires a Remember: line"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
