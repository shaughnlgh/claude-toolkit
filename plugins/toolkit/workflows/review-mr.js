export const meta = {
  name: 'review-mr',
  description: 'Multi-dimension diff review: fan out global reviewer agents + custom dimensions, adversarially verify every finding',
  whenToUse: 'Invoked by the gitlab-mr-review skill (fetched MR diffs, target-branch checkout) or the red-team skill (local uncommitted slice diffs) with args = {diffPath, repoRoot, contextBlock, dimensions?, registryReviewers?, repoState?}. Reviews a saved unified diff against the local code at repoRoot whose state repoState declares.',
  phases: [
    { title: 'Review', detail: 'registry reviewer agents + custom prompt dimensions over the diff' },
    { title: 'Verify', detail: 'adversarial verification of each finding against repo truth' },
  ],
}

// ---- args contract ----
// diffPath   (required) absolute path to the saved unified diff
// repoRoot   (required) absolute path to the local repo holding target-branch code
// contextBlock (required) env facts + MR summary + verification instructions, built by the conductor
// dimensions (optional) [{key, prompt, cold?}] extra MR-specific dimensions (contract impact,
//   conventions, domain); cold: true omits the conductor's contextBlock from this dimension's
//   prompt so it reads the diff without the author's framing
// registryReviewers (optional) agentType names to fan out; must be fully qualified as the
//   harness registers them (plugin agents are namespaced, e.g. 'toolkit:code-reviewer') —
//   the Workflow agentType lookup is literal, with none of the Agent tool's bare-name
//   fall-through. Default: the toolkit's reviewer agents.
// repoState (optional) sentence describing the state of the tree at repoRoot, substituted into
//   the reviewer and verifier prompts; defaults to the current MR target-branch sentence.

// The harness may deliver args as a JSON string rather than a parsed object.
let a = args
if (typeof a === 'string') {
  try { a = JSON.parse(a) } catch (e) { a = null }
}

if (!a || !a.diffPath || !a.repoRoot || !a.contextBlock) {
  throw new Error('review-mr requires args: {diffPath, repoRoot, contextBlock, dimensions?, registryReviewers?, repoState?}')
}

const REPO_STATE = a.repoState || `The local repo at ${a.repoRoot} holds the
TARGET-branch code (the MR branch is NOT checked out) — use it to verify claims about existing
code, callers, and framework behavior.`

const REVIEWERS = a.registryReviewers || [
  'toolkit:code-reviewer',
  'toolkit:security-reviewer',
  'toolkit:silent-failure-hunter',
  'toolkit:performance-reviewer',
  'toolkit:pr-test-analyzer',
]

const CUSTOM = a.dimensions || []

const OUTPUT_CONTRACT = `
Output contract: report ONLY findings backed by evidence in the diff or the local repo. Verify
every factual claim (class exists, signature matches, config state, caller behavior) directly in
the code before reporting it. Each finding needs: file (repo-relative path as it appears in the
diff), approximate line, severity, why it is a real problem with the evidence you checked, and a
concrete failure scenario (inputs/state -> wrong behavior). No style nitpicks unless your
dimension explicitly covers conventions. If you hit something you cannot answer from the diff or
the local repo (MR intent, business rule, environment/deploy fact), do NOT guess and do NOT report
it as a finding — put it in open_questions; those go back to the conductor, which has the full
session context. Return raw structured data only.`

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'number' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          detail: { type: 'string', description: 'Why this is a problem, with evidence (repo paths/lines checked)' },
          failure_scenario: { type: 'string', description: 'Concrete inputs/state leading to wrong behavior' },
        },
        required: ['title', 'file', 'severity', 'detail', 'failure_scenario'],
      },
    },
    open_questions: {
      type: 'array',
      items: { type: 'string' },
      description: 'Questions this dimension could not answer from the diff/repo — returned to the conductor, never sent to a verifier',
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    isReal: { type: 'boolean' },
    confidence: { type: 'string', enum: ['confirmed', 'plausible', 'refuted'] },
    reasoning: { type: 'string' },
  },
  required: ['isReal', 'confidence', 'reasoning'],
}

const suffix = (n) => n.split(':').pop()

// Key by bare suffix for readable labels/dimension names; keep the full agentType as the
// key when two reviewers share a suffix, so their findings stay distinguishable.
const registryDimensions = REVIEWERS.map((name) => ({
  key: REVIEWERS.some((n) => n !== name && suffix(n) === suffix(name)) ? name : suffix(name),
  agentType: name,
  prompt: `${a.contextBlock}

Read the full unified diff at ${a.diffPath} first. ${REPO_STATE} Apply your review speciality to this MR diff.
${OUTPUT_CONTRACT}`,
}))

const customDimensions = CUSTOM.map((d) => ({
  key: d.key,
  agentType: undefined,
  prompt: `${d.cold ? '' : `${a.contextBlock}

`}Read the full unified diff at ${a.diffPath} first. ${REPO_STATE}

DIMENSION: ${d.prompt}
${OUTPUT_CONTRACT}`,
}))

const DIMENSIONS = registryDimensions.concat(customDimensions)

phase('Review')
log(`Fanning out ${DIMENSIONS.length} review dimensions (${registryDimensions.length} registry agents, ${customDimensions.length} custom)`)

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(d.prompt, {
    label: `review:${d.key}`,
    phase: 'Review',
    schema: FINDINGS_SCHEMA,
    model: 'sonnet',
    ...(d.agentType ? { agentType: d.agentType } : {}),
  }),
  async (review, d) => {
    if (!review) return null
    const questions = (review.open_questions || []).map((q) => ({ dimension: d.key, question: q }))
    if (!review.findings || !review.findings.length) return { verified: [], questions }
    const verified = await parallel(review.findings.map((f) => () =>
      agent(
        `${a.contextBlock}

You are an adversarial verifier. A reviewer (dimension: ${d.key}) claims the following finding in
this MR. Try to REFUTE it by checking the diff at ${a.diffPath} and the local repo at
${a.repoRoot}. ${REPO_STATE} It is only real if the evidence holds up: the code path actually
executes, the failure scenario is concrete and reachable, and it is not already handled elsewhere
in the diff or repo. Conventions findings are real only if they contradict both written project
rules and actual repo practice.

FINDING: ${f.title}
FILE: ${f.file}
SEVERITY CLAIMED: ${f.severity}
DETAIL: ${f.detail}
FAILURE SCENARIO: ${f.failure_scenario}

Verify every factual claim (method exists, signature matches, caller behavior, config state)
directly in the code. Default to refuted if the scenario is unreachable or speculative.`,
        {
          label: `verify:${(f.title || '').slice(0, 40)}`,
          phase: 'Verify',
          schema: VERDICT_SCHEMA,
          model: 'sonnet',
          agentType: 'toolkit:verifier',
        }
      ).then((v) => ({ ...f, dimension: d.key, verdict: v }))
    ))
    return { verified: verified.filter(Boolean), questions }
  }
)

const perDim = results.filter(Boolean)
const all = perDim.flatMap((r) => r.verified)
const openQuestions = perDim.flatMap((r) => r.questions)
const confirmed = all.filter((f) => f.verdict && f.verdict.isReal)
const refuted = all.filter((f) => f.verdict && !f.verdict.isReal)
const unverified = all.filter((f) => !f.verdict)

log(`${all.length} raw findings: ${confirmed.length} confirmed, ${refuted.length} refuted, ${unverified.length} unverified (verifier died — conductor must adjudicate); ${openQuestions.length} open questions for the conductor`)

return {
  confirmed,
  refuted: refuted.map((f) => ({ title: f.title, file: f.file, dimension: f.dimension, reason: f.verdict.reasoning })),
  unverified,
  openQuestions,
}
