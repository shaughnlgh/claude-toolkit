export const meta = {
  name: 'execute-runner',
  description: 'Execute flow: runs an approved plan note through a baseline check, one implementer per Implementation Step, the Validation Steps with one fix round, the review-mr panel chosen by changed path with one fix round over the confirmed findings and the nits carried along, a cold read told what the panel already reported and, when nothing blocked, the Doc Update Pass and the remember pass, and returns the result for the execute-flow skill to record. The script writes no file itself: its verifiers write the diff captures under scratchDir and the remember worker writes vault notes. No worker runs mutating git in repoRoot.',
  phases: [
    { title: 'Prep', detail: 'verifier records the branch, the tree status and the baseline verify result' },
    { title: 'Implement', detail: 'one implementer per Implementation Step, in order' },
    { title: 'Verify', detail: 'verifier runs the Validation Steps, one implementer fix round on a failure' },
    { title: 'Red team', detail: 'verifier captures the diff, the review-mr child runs the panel chosen by changed path and two cold dimensions' },
    { title: 'Fix', detail: 'one round over the confirmed findings with the nits carried along, verifier rechecks, bounded by maxFixRounds' },
    { title: 'Cold read', detail: 'verifier recaptures the diff, one cold code-reviewer reads it' },
    { title: 'Doc pass', detail: 'implementer runs the Doc Update Pass, verifier revalidates and captures the post-doc diff' },
    { title: 'Remember', detail: 'implementer routes the durable facts, only when nothing blocked' },
  ],
}

let a = args
if (typeof a === 'string') {
  try { a = JSON.parse(a) } catch (e) { a = null }
}
const REQUIRED = ['planName', 'repoRoot', 'repoName', 'planContent', 'recallHits', 'scratchDir', 'pluginRoot', 'vaultRoot']
if (!a || REQUIRED.some((k) => typeof a[k] !== 'string' || !a[k])) {
  throw new Error('execute-runner requires args: {planName, repoRoot, repoName, planContent, recallHits, scratchDir, pluginRoot, vaultRoot, knownEvidence?, verifyCommand?, baselineFailing?, priorChangedPaths?, maxFixRounds?, reviewRules?, reviewMr?}')
}
if (a.maxFixRounds != null && !(Number.isInteger(a.maxFixRounds) && a.maxFixRounds >= 0)) {
  throw new Error(`execute-runner maxFixRounds must be a non-negative integer, got ${JSON.stringify(a.maxFixRounds)}`)
}
if (a.reviewRules != null && typeof a.reviewRules !== 'string') throw new Error('execute-runner reviewRules must be a string when given')
const isStrList = (v) => Array.isArray(v) && v.every((s) => typeof s === 'string')
if (a.baselineFailing != null && !isStrList(a.baselineFailing)) throw new Error(`execute-runner baselineFailing must be an array of strings when given, got ${JSON.stringify(a.baselineFailing)}`)
if (a.priorChangedPaths != null && !isStrList(a.priorChangedPaths)) throw new Error(`execute-runner priorChangedPaths must be an array of strings when given, got ${JSON.stringify(a.priorChangedPaths)}`)
const refOk = (r) => typeof r === 'string' ? r.length > 0 : !!(r && typeof r === 'object' && typeof r.scriptPath === 'string' && r.scriptPath.length > 0)
if (a.reviewMr != null && !refOk(a.reviewMr)) throw new Error('execute-runner reviewMr must be a workflow name or {scriptPath} when given')
const MAX_FIX_ROUNDS = a.maxFixRounds ?? 1
const REVIEW_RULES = (a.reviewRules || '').trim()
const REVIEW_MR = a.reviewMr ?? 'toolkit:review-mr'
const STANDING = ['toolkit:code-reviewer', 'toolkit:silent-failure-hunter', 'toolkit:pr-test-analyzer']
const FULL = STANDING.concat(['toolkit:security-reviewer', 'toolkit:performance-reviewer', 'toolkit:coupling-reviewer'])
const DOCS_ONLY = ['toolkit:code-reviewer']
const HIGH_RISK = ['plugins/toolkit/hooks/', 'plugins/toolkit/scripts/', 'plugins/toolkit/workflows/', '.github/']
const panelFor = (paths, extra) => {
  const risky = HIGH_RISK.concat(extra)
  if (paths.some((p) => risky.some((h) => p === h || p.startsWith(h)))) return { panel: FULL, rule: 'high-risk path' }
  if (paths.length && paths.every((p) => p.startsWith('docs/') || (p.endsWith('.md') && !p.includes('/')))) return { panel: DOCS_ONLY, rule: 'docs only' }
  return { panel: STANDING, rule: 'standing' }
}

// Same fence rule as scripts/validate-plan.py strip_fences: 3+ backticks or tildes, closed only by the same char at least as long with no info string.
const FENCE = /^[ \t]*(`{3,}|~{3,})[ \t]*(\S*)[ \t]*$/
const outsideFence = (lines) => {
  let open = null
  return lines.map((line) => {
    const m = FENCE.exec(line)
    if (!m) return !open
    if (!open) open = m[1]
    else if (m[1][0] === open[0] && m[1].length >= open.length && !m[2]) open = null
    return false
  })
}
const planLines = a.planContent.split('\n')
const planOutside = outsideFence(planLines)
const sectionIn = (lines, outside, name) => {
  const out = []
  let inSection = false
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]
    if (outside[i] && /^##\s/.test(line)) {
      if (inSection) break
      inSection = line.slice(2).trim() === name
    } else if (inSection) out.push(line)
  }
  return out.join('\n').trim()
}
const section = (name) => sectionIn(planLines, planOutside, name)
const rulesLines = REVIEW_RULES.split('\n')
const bullets = (text) => text.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('- '))
  .map((l) => l.slice(2).trim().split(/\s/)[0].replace(/^[`'"]+/, '').replace(/[`'".,:;]+$/, '')).filter(Boolean)
const extraHighRisk = REVIEW_RULES ? bullets(sectionIn(rulesLines, outsideFence(rulesLines), 'High-risk paths')) : []
const firstLine = (s) => String(s || '').split('\n')[0].trim().replace(/\.$/, '')
const STEP_HEADING = /^###\s+\d+[.)]/
const SUBHEADING = /^###\s/
const NUMBERED = /^\d+[.)]\s/
const items = (text) => {
  if (!text) return []
  const lines = text.split('\n')
  const outside = outsideFence(lines)
  const at = (re) => [...lines.keys()].filter((i) => outside[i] && re.test(lines[i]))
  const heads = at(SUBHEADING)
  const nums = at(NUMBERED)
  const numberOf = (i) => parseInt(lines[i], 10)
  const headingsBefore = (i) => heads.filter((h) => h < i).length
  const oneList = nums.length > 0 && nums.every((i, k) => numberOf(i) === k + 1)
  const listCrossesHeading = oneList && headingsBefore(nums[0]) !== headingsBefore(nums[nums.length - 1])
  const byHeading = heads.length > 1 && nums.every((i) => i > heads[0]) && !listCrossesHeading
  // A numbered line that does not top every number before it, such as a restarted sub-list, stays inside the step.
  const rising = nums.filter((i, k) => nums.slice(0, k).every((j) => numberOf(j) < numberOf(i)))
  const stepHeads = at(STEP_HEADING)
  const starts = new Set(stepHeads.length ? stepHeads : byHeading ? heads : rising)
  const groups = []
  const preamble = []
  lines.forEach((line, i) => {
    if (starts.has(i)) groups.push([line])
    else if (groups.length) groups[groups.length - 1].push(line)
    else preamble.push(line)
  })
  if (!groups.length) return [{ heading: firstLine(text), text }]
  return groups.map((g, i) => ({ heading: g[0].trim().replace(/^###\s+/, ''), text: (i ? g : preamble.concat(g)).join('\n').trim() }))
}

const objective = section('Objective')
const assumptions = section('Assumptions')
const risks = section('Risks')
const implItems = items(section('Implementation Steps'))
const implSteps = implItems.map((s) => s.text)
const validationSteps = section('Validation Steps')
const validationItems = items(validationSteps).map((s) => s.text)
const validationCount = validationItems.length
const validationBlock = validationItems.map((s, i) => `STEP ${i + 1}:\n${s}`).join('\n\n')
const relatedTopics = section('Related Topics')
const currentContext = section('Current Context')
const affectedFiles = section('Affected Files')
const planChangesSection = section('Plan Changes During Execution')
if (!implSteps.length) throw new Error('execute-runner: the plan has no Implementation Steps')

const str = { type: 'string' }
const num = { type: 'number' }
const bool = { type: 'boolean' }
const strList = { type: 'array', items: str }
const list = (itemSchema) => ({ type: 'array', items: itemSchema })
const obj = (properties) => ({ type: 'object', properties, required: Object.keys(properties) })
// Duplicated in review-mr.js: workflow scripts share no module.
const unit = { type: 'number', minimum: 0, maximum: 1 }
const TAG = { type: 'string', enum: ['important', 'nit', 'pre-existing'] }
const clamp = (n) => Math.min(1, Math.max(0, Number(n) || 0))
const round2 = (n) => Math.round(clamp(n) * 100) / 100
const scoreOf = (f) => round2(0.5 * clamp(f.impact) + 0.3 * clamp(f.likelihood) + 0.2 * clamp(f.confidence))
const cited = (f) => typeof f.citation === 'string' && f.citation.trim().length > 0

const BASELINE = obj({ branch: str, status: strList, verify: obj({ command: str, exitCode: num, failing: strList }) })
const STEP = obj({ changedPaths: strList, deviations: strList, checksRun: strList, result: str, blockers: strList, topicMaterial: str })
const VALIDATION = obj({ results: list(obj({ step: str, status: { type: 'string', enum: ['pass', 'fail', 'manual', 'pre-existing'] }, evidence: str })) })
const DIFF = obj({ diffPath: str, hash12: str, empty: bool, paths: strList })
const RECHECK = obj({ results: list(obj({ file: str, title: str, resolved: bool, evidence: str })) })
const COLD = { type: 'object', properties: { findings: list({ type: 'object',
  properties: { file: str, title: str, issue: str, fix: str, tag: TAG, impact: unit, likelihood: unit, confidence: unit, citation: str, verified: bool },
  required: ['file', 'title', 'issue', 'fix', 'tag', 'impact', 'likelihood', 'confidence', 'verified'] }) }, required: ['findings'] }
const DOCPASS = obj({ docsUpdated: strList, deferred: strList, distributed: strList, changedPaths: strList, blockers: strList, topicMaterial: str })
const REMEMBER = obj({ proposals: list(obj({ path: str, action: str, scratch: str, factsFrom: strList })), topicsUpdated: strList, rememberLine: str, blockers: strList })
const key = (f) => `${f.file}: ${f.title}`

const S = a.scratchDir
const GIT_RULE = `In ${a.repoRoot}, git is read-only: git status, git diff, git log, git ls-files, git branch --show-current, git remote get-url, git symbolic-ref with one ref argument, and git merge-base --is-ancestor only. A -c core.quotePath=false prefix on one of these commands keeps it read-only. Never run git stash, add, commit, checkout, switch, reset, clean, rebase, merge or push there. Mutating git is allowed only inside a fresh fixture you create under ${S}.`
const SCRATCH_ONLY = `Run embedded commands only against scratch fixtures you create under ${S}, never against ${a.repoRoot}.`
const CONTEXT = `Repo: ${a.repoName} at ${a.repoRoot}. Plan name: ${a.planName}.
TOPIC RECALL HITS:
${a.recallHits}
KNOWN EVIDENCE:
${a.knownEvidence || 'none'}`
const DOCTRINE = `Build minimal. The brief says what to build, so build the least that satisfies it: shortest working diff, no unrequested abstractions, reuse before adding, and trace and grep the callers before changing a shared function. Prefer deleting code to adding it. Mark any deliberate shortcut with a greppable TODO(author): comment naming the ceiling and the upgrade path. See ${a.pluginRoot}/doctrine/minimalism.md.`
const REPO_STATE = 'The tree at repoRoot is the POST-change state this diff produces. There is no pre-change checkout. Reconstruct the pre-change state from the diff\'s context and removed lines. A defect the diff introduces is in scope even though it is present in the tree.'
const STDIN_RULE = 'Run any verify or test suite, such as bash verify.sh, with stdin from /dev/null (bash verify.sh </dev/null), because a suite that reads stdin hangs when stdin is a pipe.'
const BLOCKER_RULE = 'If any step, command or tool call is denied or cannot be done, do not work around it. Record it in blockers as one sentence and stop. The runner stops on any blockers entry, so blockers holds only work you could not do and is empty when the work is done.'
const HOOK_RULE = `The dangerous-commands hook refuses any command text, including inside a heredoc, that contains a recursive force-delete of a shell variable, a bare dot or double dot, a bare glob, a path with a /../ segment, the root, the home dir, or a system dir such as /usr, /etc or /var. Remove a scratch fixture with its literal absolute path under ${S}.`
const HOOK_WRITE_RULE = "If a file you create must hold a command the hook refuses, such as a script's recursive delete of a variable, create it with the Write tool, never through a heredoc."
const EXTERNAL_PROMPT = 'You are CodeRabbit, Copilot, or a senior engineer on another team seeing this diff with no context. List what you would flag that a panel briefed by the author would rationalize away: naming that hides intent, a test that proves nothing, a comment that contradicts the code, a config value that belongs elsewhere, a public surface with no doc.'
const CAPTURE_PROMPT = `Run exactly these commands from ${a.repoRoot} and nothing else:
1. git diff HEAD > ${S}/slice.diff.tmp
2. git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do git diff --no-index -- /dev/null "$f" >> ${S}/slice.diff.tmp; done
3. Hash the temp file (e.g. shasum -a 256) and take the first 12 characters as <hash12>; move it to ${S}/slice-<hash12>.diff.
4. git -c core.quotePath=false diff HEAD --name-only, then git -c core.quotePath=false ls-files --others --exclude-standard
The diff command in 2 exits 1 on any difference. Tolerate that exit code, it is not a failure.
Return diffPath, hash12, empty and paths. diffPath is the absolute path of the moved file. empty is true only when that file has zero bytes. paths holds every line the two commands in 4 printed, as repo-relative paths. Return raw structured data only. ${GIT_RULE}`
const SHARED = `${CONTEXT}

${DOCTRINE}
${GIT_RULE}
${BLOCKER_RULE}
${HOOK_RULE}
${HOOK_WRITE_RULE}`
const RETURN_STEP = 'Return changedPaths as repo-relative paths, deviations as one sentence per departure from the instructions and one per caveat or follow-up you want recorded, checksRun as the checks you ran, result as one sentence, blockers as one sentence per step you could not do or empty, and topicMaterial as the durable non-obvious facts with file:line refs, or none. Return raw structured data only.'

const DIMENSIONS = [
  { key: 'cold-read', cold: true, prompt: `Re-derive what the diff does from the diff alone. Read every instruction and embedded command literally and adversarially, and report each place where the literal reading differs from what the diff appears to intend. ${SCRATCH_ONLY} ${GIT_RULE}` },
  { key: 'external-reviewer', cold: true, prompt: `${EXTERNAL_PROMPT} ${SCRATCH_ONLY} ${GIT_RULE}` },
]

const incomplete = []
const blocked = []
const planChanges = []
const steps = []
const rounds = []
const changed = [...(a.priorChangedPaths || [])]
const material = []
let baseline = null
let validation = null
let review = null
let panel = STANDING
let panelRule = 'standing'
let fixed = []
let open = []
let coldResidual = null
let coldUnverified = null
let fixAttempts = 0
let docPass = null
let remember = null
let diffRed = null
let diffFinal = null
let diffPost = null

const dead = (who, label) => {
  incomplete.push(label)
  blocked.push(`The ${who} ${label} returned nothing.`)
}
const blockersOf = (who, label, r) => {
  if (r && r.blockers && r.blockers.length) blocked.push(`The ${who} ${label} reported blockers: ${r.blockers.join(' ')}`)
  return Boolean(r && r.blockers && r.blockers.length)
}
const collect = (paths, topicMaterial) => {
  for (const p of paths || []) if (!changed.includes(p)) changed.push(p)
  if (topicMaterial && topicMaterial.trim() && topicMaterial.trim().toLowerCase() !== 'none') material.push(topicMaterial.trim())
}
// Each worker carries only the plan sections its job acts on; the other steps travel as headings so a worker sees its boundary without their bodies.
const stepMap = (current) => implItems.map((s, i) => `${s.heading}${i === current ? ' (your step)' : ''}`).join('\n')
const block = (title, body) => `${title}:\n${body || 'none'}`
const changedBlock = (title) => block(title, changed.join('\n'))
const SCOPE = [block('OBJECTIVE', objective), block('ASSUMPTIONS', assumptions)].join('\n\n')
const implementBrief = (i) => [block('OBJECTIVE', objective), block('CURRENT CONTEXT', currentContext), block('ASSUMPTIONS', assumptions), block('AFFECTED FILES', affectedFiles),
  block('VALIDATION STEPS', validationSteps), block('RISKS', risks), block('PLAN CHANGES DURING EXECUTION', planChangesSection), block('STEPS', stepMap(i)), block('YOUR STEP', implSteps[i]), changedBlock('ALREADY CHANGED')].join('\n\n')
const failingOf = (v) => v.results.filter((r) => r.status === 'fail')
const lineOf = (r) => `${firstLine(r.step)}: ${r.evidence}`
const setValidation = (v, runs) => {
  validation = {
    results: v.results,
    runs,
    allPass: v.results.length > 0 && v.results.every((r) => r.status === 'pass'),
    manualChecks: v.results.filter((r) => r.status === 'manual').map(lineOf),
    preExisting: v.results.filter((r) => r.status === 'pre-existing').map(lineOf),
  }
}
const covers = (v) => {
  if (v.results.length === validationCount) return true
  blocked.push(`Validation returned ${v.results.length} results for ${validationCount} steps.`)
  return false
}
const capture = (label, phaseName) => agent(CAPTURE_PROMPT, { label, phase: phaseName, schema: DIFF, agentType: 'toolkit:verifier' })

const finish = () => {
  log(`incomplete: ${incomplete.join(', ') || 'none'}`)
  return {
    baseline,
    steps,
    validation,
    review: review ? {
      panel,
      panelRule,
      dimensions: ['cold-read', 'external-reviewer'],
      confirmed: review.confirmed || [],
      nits: review.nits || [],
      preExisting: review.preExisting || [],
      fixed,
      open,
      refuted: review.refuted || [],
      unverified: review.unverified || [],
      dropped: review.dropped || [],
      openQuestions: review.openQuestions || [],
      dead: Array.isArray(review.dead) ? review.dead : [],
      verifierDead: Array.isArray(review.verifierDead) ? review.verifierDead : [],
      rounds,
    } : null,
    coldResidual,
    coldUnverified,
    docPass,
    remember: remember || { ran: false, material, proposals: [], topicsUpdated: [], rememberLine: '' },
    changedPaths: changed,
    planChanges,
    diffHashes: { redTeam: diffRed ? diffRed.hash12 : null, final: diffFinal ? diffFinal.hash12 : null, postDoc: diffPost ? diffPost.hash12 : null },
    diffPaths: { redTeam: diffRed ? diffRed.diffPath : null, final: diffFinal ? diffFinal.diffPath : null, postDoc: diffPost ? diffPost.diffPath : null },
    diffFiles: { redTeam: diffRed ? diffRed.paths : null, final: diffFinal ? diffFinal.paths : null, postDoc: diffPost ? diffPost.paths : null },
    blocked,
    incomplete,
  }
}

phase('Prep')
const verifyLine = a.verifyCommand
  ? 'run the verify command ' + a.verifyCommand
  : 'find and run the repo\'s verify or test command from AGENTS.md, CLAUDE.md, VERIFY.md or the package manifest. If you find none, run none, set command to none and exitCode to -1, and set failing to the one sentence No verify command was found'
baseline = await agent(`${CONTEXT}

In ${a.repoRoot}, run git branch --show-current and git status --porcelain, then ${verifyLine}. ${STDIN_RULE} Return branch, status as the git status --porcelain lines, and verify with the command you ran, its exit code, and failing as the names of the checks it reported as failed. Change no file. ${GIT_RULE} Return raw structured data only.`,
  { label: 'prep:baseline', phase: 'Prep', schema: BASELINE, agentType: 'toolkit:verifier' })
if (!baseline) dead('verifier', 'prep:baseline')
else if (a.baselineFailing) baseline.verify = { ...baseline.verify, failing: a.baselineFailing }
if (!validationSteps) blocked.push('The plan has no Validation Steps, so nothing proves the slice.')

phase('Implement')
for (let i = 0; i < implSteps.length; i += 1) {
  const label = `implement:${i + 1}`
  const r = await agent(`${SHARED}

${implementBrief(i)}

Implement YOUR STEP in ${a.repoRoot} and nothing beyond it. STEPS lists every step of the plan by heading so you can see where your step ends, and the other steps are not your work. Earlier steps already ran, and their changes are the paths under ALREADY CHANGED. ${RETURN_STEP}`,
    { label, phase: 'Implement', schema: STEP, agentType: 'toolkit:implementer' })
  if (!r) {
    dead('implementer', label)
    return finish()
  }
  steps.push(r)
  collect(r.changedPaths, r.topicMaterial)
  for (const d of r.deviations || []) planChanges.push(`Step ${i + 1}: ${d}`)
  if (blockersOf('implementer', label, r)) return finish()
}

phase('Verify')
const runValidation = (label, phaseName) => agent(`${CONTEXT}

VALIDATION STEPS:
${validationBlock}

BASELINE VERIFY RESULT:
${baseline ? JSON.stringify(baseline.verify) : 'none, the baseline check did not run'}

Run each STEP above that an agent can run here, against ${a.repoRoot}. Return exactly ${validationCount} results, one per STEP, in order, with step set to the STEP number and the step's first line, as in STEP 1: <first line>. status is pass or fail with the command output as evidence, never a guessed pass. status is manual, with the reason as evidence, for a step that needs a human or another session. status is pre-existing when a step fails only on a check that the baseline failing list already names. If a command is denied, report its step as fail with the denial as evidence. ${STDIN_RULE} ${HOOK_RULE} Change no file. ${GIT_RULE} Return raw structured data only.`,
  { label, phase: phaseName, schema: VALIDATION, agentType: 'toolkit:verifier' })

if (!validationSteps) setValidation({ results: [] }, 0)
else {
  let v = await runValidation('verify:validation', 'Verify')
  if (!v) {
    dead('verifier', 'verify:validation')
    return finish()
  }
  setValidation(v, 1)
  if (!covers(v)) {
    failingOf(v).forEach((r) => blocked.push(`Validation step failed: ${firstLine(r.step)}.`))
    return finish()
  }
  const failing = failingOf(v)
  if (failing.length) {
    const fix = await agent(`${SHARED}

${SCOPE}

${block('PLAN CHANGES DURING EXECUTION', planChangesSection)}

${changedBlock('CHANGED PATHS')}

FAILING VALIDATION STEPS:
${failing.map((r) => `${r.step}\nEVIDENCE: ${r.evidence}`).join('\n\n')}

Fix only what makes these steps pass, in ${a.repoRoot}. ${RETURN_STEP}`,
      { label: 'fix:validation', phase: 'Verify', schema: STEP, agentType: 'toolkit:implementer' })
    if (!fix) {
      dead('implementer', 'fix:validation')
      return finish()
    }
    collect(fix.changedPaths, fix.topicMaterial)
    planChanges.push(`Validation fix: ${fix.result}`)
    for (const d of fix.deviations || []) planChanges.push(`Validation fix deviation: ${d}`)
    if (blockersOf('implementer', 'fix:validation', fix)) return finish()
    v = await runValidation('verify:revalidation', 'Verify')
    if (!v) {
      dead('verifier', 'verify:revalidation')
      return finish()
    }
    setValidation(v, 2)
    covers(v)
    const still = failingOf(v)
    if (still.length) {
      still.forEach((r) => blocked.push(`Validation step failed after one fix: ${firstLine(r.step)}.`))
      return finish()
    }
  }
}

phase('Red team')
diffRed = await capture('diff:red-team', 'Red team')
if (!diffRed) dead('verifier', 'diff:red-team')
else if (diffRed.empty) blocked.push('The diff after implementation is empty.')

if (diffRed && !diffRed.empty) {
  const reviewPaths = [...new Set((diffRed.paths || []).concat(changed))]
  const picked = panelFor(reviewPaths, extraHighRisk)
  panel = picked.panel
  panelRule = picked.rule
  const contextBlock = `Repo: ${a.repoName} at ${a.repoRoot}. Plan name: ${a.planName}.
OBJECTIVE:
${objective || 'none'}
CHANGED PATHS:
${changed.join('\n') || 'none'}
SETTLED DECISIONS:
The owner accepted the plan's Assumptions and Risks at approval. A finding that only restates one of them, or asks for scope or coverage the Assumptions exclude, is not a finding, unless the tree contradicts the decision, in which case report it as a normal finding.
ASSUMPTIONS:
${assumptions || 'none'}
RISKS:
${risks || 'none'}

Apply the project rules in the CLAUDE.md, AGENTS.md and .claude/rules files under ${a.repoRoot} where they exist. When the diff ships executable commands embedded in prose, such as a skill, a workflow script's prompts or a doc, execute those exact commands against a scratch fixture covering the awkward cases (clean tree, dirty tree, untracked directories, unusual filenames) rather than judge them by reading. ${SCRATCH_ONLY} ${GIT_RULE}${REVIEW_RULES ? `\n\nREVIEW RULES (REVIEW.md on the default branch):\n${REVIEW_RULES}` : ''}`
  try {
    review = await workflow(REVIEW_MR, { diffPath: diffRed.diffPath, repoRoot: a.repoRoot, contextBlock, repoState: REPO_STATE, dimensions: DIMENSIONS, registryReviewers: panel })
    if (review == null) {
      review = null
      blocked.push('The review-mr child workflow returned nothing.')
    } else if (!Array.isArray(review.dead)) {
      blocked.push('The review panel did not report which reviewers ran.')
    } else if (review.dead.length) {
      blocked.push(`The review panel lost ${review.dead.length} reviewers: ${review.dead.join(', ')}.`)
    }
    if (review && Array.isArray(review.verifierDead) && review.verifierDead.length) blocked.push(`The review panel lost the verifier for ${review.verifierDead.length} dimensions: ${review.verifierDead.join(', ')}.`)
  } catch (e) {
    review = null
    blocked.push(`The review-mr child workflow failed: ${e && e.message ? e.message : 'no message'}.`)
  }
}

if (review) {
  phase('Fix')
  const confirmedOpen = (review.confirmed || []).map((f) => ({ ...f, bucket: 'confirmed' }))
  const nitsOpen = (review.nits || []).map((f) => ({ ...f, bucket: 'nit' }))
  open = confirmedOpen.length ? confirmedOpen.concat(nitsOpen) : []
  let stageDead = false
  for (let round = 1; round <= MAX_FIX_ROUNDS && open.some((f) => f.bucket === 'confirmed'); round += 1) {
    const findings = open.map((f) => `${key(f)}\nDETAIL: ${f.detail}\nFAILURE SCENARIO: ${f.failure_scenario || 'none given'}`).join('\n\n')
    const entry = (f) => `${key(f)} [${f.finalTag || f.tag}, final score ${f.finalScore}, ${f.reproduced ? 'reproduced' : 'not reproduced'}]\nCITATION: ${f.citation || 'none'}\nDETAIL: ${f.detail}\nFAILURE SCENARIO: ${f.failure_scenario || 'none given'}`
    const confirmedBlock = open.filter((f) => f.bucket === 'confirmed').map(entry).join('\n\n') || 'none'
    const nitBlock = open.filter((f) => f.bucket === 'nit').map(entry).join('\n\n') || 'none'
    const fix = await agent(`${SHARED}

${SCOPE}

${changedBlock('CHANGED PATHS')}

CONFIRMED FINDINGS:
${confirmedBlock}

NITS:
${nitBlock}

Fix each confirmed finding above in ${a.repoRoot} with the smallest change that removes the defect, and fix every instance of that class of defect in the slice, not one line. For each nit, fix only the cited line, and only when the tree confirms the nit. ${RETURN_STEP}`,
      { label: `fix:${round}`, phase: 'Fix', schema: STEP, agentType: 'toolkit:implementer' })
    fixAttempts += 1
    if (!fix) {
      dead('implementer', `fix:${round}`)
      stageDead = true
      break
    }
    collect(fix.changedPaths, fix.topicMaterial)
    for (const d of fix.deviations || []) planChanges.push(`Fix round ${round}: ${d}`)
    const record = { round, changedPaths: fix.changedPaths, resolved: [] }
    rounds.push(record)
    if (blockersOf('implementer', `fix:${round}`, fix)) {
      stageDead = true
      break
    }
    const re = await agent(`${CONTEXT}

FINDINGS:
${findings}

PATHS THE FIX CHANGED:
${(fix.changedPaths || []).join('\n') || 'none'}

Check in the tree at ${a.repoRoot} whether each finding above is resolved. Return one result per finding, file and title exactly as given, resolved true only when the tree shows the defect gone, with the evidence you checked. Change no file. ${GIT_RULE} Return raw structured data only.`,
      { label: `recheck:${round}`, phase: 'Fix', schema: RECHECK, agentType: 'toolkit:verifier' })
    if (!re) {
      dead('verifier', `recheck:${round}`)
      stageDead = true
      break
    }
    const resolved = new Set(re.results.filter((r) => r.resolved).map(key))
    const now = open.filter((f) => resolved.has(key(f)))
    record.resolved = now.map(key)
    fixed = fixed.concat(now)
    open = open.filter((f) => !resolved.has(key(f)))
    if (now.length) planChanges.push(`Fix round ${round} resolved: ${record.resolved.join('; ')}`)
  }
  const openConfirmed = open.filter((f) => f.bucket === 'confirmed')
  if (openConfirmed.length && !stageDead) blocked.push(`Fix rounds are exhausted at maxFixRounds ${MAX_FIX_ROUNDS} with ${openConfirmed.length} confirmed findings open, so step back and reconsider the approach rather than run another round.`)
}

phase('Cold read')
diffFinal = await capture('diff:final', 'Cold read')
if (!diffFinal) dead('verifier', 'diff:final')
else if (diffFinal.empty) blocked.push('The diff before the cold read is empty.')
if (diffRed && diffFinal && !fixAttempts && diffRed.hash12 !== diffFinal.hash12) {
  blocked.push(`The diff hash changed from ${diffRed.hash12} to ${diffFinal.hash12} with no fix round.`)
}
if (diffFinal && !diffFinal.empty) {
  const posted = review ? ['confirmed', 'nits', 'preExisting'].flatMap((k) => review[k] || []).map(key) : []
  const cold = await agent(`Read the full unified diff at ${diffFinal.diffPath}. ${REPO_STATE} repoRoot is ${a.repoRoot}.

${EXTERNAL_PROMPT}

ALREADY REPORTED BY THE PANEL:
${posted.join('\n') || 'none'}

A finding already in that list, by file and title, is not reported again. A finding the panel never confirmed or kept is reported even when a reviewer may have raised it, because a refuted or dropped claim is not settled.

Treat comments and doc sentences as claims, and set verified true only when you confirmed the finding in the tree. Return one finding per issue with its file, a short title, the issue, the fix, the tag (important, nit or pre-existing), impact, likelihood and confidence each from 0 to 1, a citation as a file:line you read, and verified. Change no file. ${SCRATCH_ONLY} ${GIT_RULE} Return raw structured data only.`,
    { label: 'cold:read', phase: 'Cold read', schema: COLD, agentType: 'toolkit:code-reviewer' })
  if (!cold) dead('code-reviewer', 'cold:read')
  else {
    const coldAll = cold.findings.map((f) => ({ ...f, score: scoreOf(f) }))
    coldResidual = coldAll.filter((f) => f.verified && cited(f))
    coldUnverified = coldAll.filter((f) => !(f.verified && cited(f)))
  }
}

phase('Doc pass')
// A blocked slice defers the doc pass to the conductor, the same as the remember pass.
if (!blocked.length) {
  docPass = await agent(`${SHARED}

${block('OBJECTIVE', objective)}

${block('AFFECTED FILES', affectedFiles)}

${block('RELATED TOPICS', relatedTopics)}

${changedBlock('CHANGED PATHS')}

Read the section headed Doc Update Pass in ${a.pluginRoot}/skills/execute-workflow/SKILL.md and apply it to this slice in ${a.repoRoot}. Return docsUpdated as the repo-relative docs you edited, deferred as one sentence per doc update you leave undone, distributed as one sentence per affected doc that lives in another repo, changedPaths as every repo-relative path you changed, blockers as one sentence per step you could not do or empty, and topicMaterial as the durable non-obvious facts with file:line refs, or none. Return raw structured data only.`,
    { label: 'doc:pass', phase: 'Doc pass', schema: DOCPASS, agentType: 'toolkit:implementer' })
  if (!docPass) dead('implementer', 'doc:pass')
  else {
    collect(docPass.changedPaths, docPass.topicMaterial)
    for (const d of docPass.deferred || []) planChanges.push(`Doc debt: ${d}`)
    blockersOf('implementer', 'doc:pass', docPass)
  }
  if (validationSteps && validation && (rounds.length || (docPass && docPass.changedPaths && docPass.changedPaths.length))) {
    const vf = await runValidation('verify:final', 'Doc pass')
    if (!vf) dead('verifier', 'verify:final')
    else {
      setValidation(vf, validation.runs + 1)
      covers(vf)
      failingOf(vf).forEach((r) => blocked.push(`Validation step failed after the doc pass: ${firstLine(r.step)}.`))
    }
  }
  diffPost = await capture('diff:post-doc', 'Doc pass')
  if (!diffPost) dead('verifier', 'diff:post-doc')
  else if (diffPost.empty) {
    blocked.push('The diff after the doc pass is empty.')
    diffPost = null
  }
}

phase('Remember')
if (!blocked.length) {
  const rem = await agent(`Objective: route the durable facts this slice surfaced. Fold the vault-bound facts into vault topic notes, and stage the repo-bound facts as proposed doc content for the conductor's consent gate.

Scope: write only under the vault root folder ${a.vaultRoot} and the scratchpad ${S}. You must not write any repo file.

Known evidence: the cumulative diff at ${diffPost.diffPath}, the touched files ${changed.join(', ') || 'none'}, the Topic note material returns from this slice ${material.join(' ') || 'none'}, and the recall hits ${a.recallHits}.

RELATED TOPICS:
${relatedTopics || 'none'}

Task-specific constraints. The plugin root is ${a.pluginRoot}. Before your first write, read these files under that root: commands/obsidian-topic.md, doctrine/security.md, doctrine/repo-artifacts.md, and the usage header of scripts/vault-fs.sh.

Routing: before any write, classify each durable fact. Class (a) is shareable engineering knowledge about this repo. Class (b) is cross-repo, not about any repo, or personal workflow. A class (a) fact routes only to a docs/context/ doc that carries the <!-- managed-by: toolkit --> marker: an existing one that covers the subject, else a new docs/context/context-<kebab>.md. Never route a fact into a hand-written repo doc. If a hand-written repo doc covers the subject, name it as the related doc on the proposal. A class (b) fact routes to the vault topic note. If a vault note carries the repo-mode banner, route its new facts to the doc the banner names, never into the note.

Class (a) content: for each proposed repo doc, write the full proposed content to ${S}/remember-<kebab-path>.md, where <kebab-path> is the repo-relative path in kebab case. Scrub the content per doctrine/security.md first. For a new file, write the whole doc with the frontmatter doctrine/repo-artifacts.md requires and the <!-- managed-by: toolkit --> marker on the line after the frontmatter. For an existing managed file, write only the exact section to add and name the heading it goes under. Do not write class (a) facts into any vault note.

Class (b) writes: for each candidate topic, fold facts under the section they belong to (Flows, Gotchas, Tasks, Related Topics). Never rewrite Overview or any prose that carries no new fact. Bump updated. Spot-check one source_refs entry against the repo, and set verified to today only on a clean check. Create a stub only for a concept that RELATED TOPICS or the collected material names and no existing note covers. Search by basename before creating. Write every vault file atomically: Write to <name>.tmp.md beside the target, then run bash ${a.pluginRoot}/scripts/vault-fs.sh mv.

Required checks: read back every vault file you wrote and confirm it holds the folded facts. Run no git command. ${BLOCKER_RULE}

Expected return format: proposals holds one entry per proposed repo doc, with path as the repo-relative path, action as created or updated, scratch as the scratch file path, and factsFrom as the [[Note]] names whose facts move into that doc. If a hand-written doc covers the subject, add one factsFrom entry that reads related <repo-relative path>. proposals is empty when there is no proposal. topicsUpdated lists every vault note you touched. rememberLine is exactly one draft line in one of these forms: Remember: repo docs <paths>; topics updated [[A]], [[B]] or Remember: repo docs <paths> or Remember: topics updated [[A]] or Remember: no change (<reason>). blockers holds one sentence per step you could not do and is empty otherwise. Return raw structured data only.`,
    { label: 'remember:pass', phase: 'Remember', schema: REMEMBER, agentType: 'toolkit:implementer' })
  if (!rem) dead('implementer', 'remember:pass')
  else if (blockersOf('implementer', 'remember:pass', rem)) remember = { ran: false, material, proposals: [], topicsUpdated: rem.topicsUpdated || [], rememberLine: '' }
  else remember = { ran: true, material, proposals: rem.proposals, topicsUpdated: rem.topicsUpdated, rememberLine: rem.rememberLine }
}

return finish()
