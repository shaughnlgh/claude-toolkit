// The script body uses top-level await and return, so it compiles inside an AsyncFunction.
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const source = readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const flow = new AsyncFunction('args', 'agent', 'workflow', 'phase', 'log', source)
import { execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

// The real indexer, so the step-splitting cases test plan-index.py through the runner. PLAN_INDEX points the suite at a mutated copy.
const INDEXER = process.env.PLAN_INDEX || fileURLToPath(new URL('../../../scripts/plan-index.py', import.meta.url))
const FIXTURES = mkdtempSync(join(tmpdir(), 'execute-runner-'))
process.on('exit', () => rmSync(FIXTURES, { recursive: true, force: true }))
const indexes = new Map()
const indexOf = (text) => {
  if (!indexes.has(text)) {
    const file = join(FIXTURES, `plan-${indexes.size}.md`)
    writeFileSync(file, text)
    indexes.set(text, { error: '', ...JSON.parse(execFileSync('python3', [INDEXER, file], { encoding: 'utf8' })) })
  }
  return indexes.get(text)
}
const POINTER = /read (?:lines (\d+)-(\d+)|from line (\d+) to the end) of the plan note: line \d+ begins "([^"\n]*)"(?: and line \d+ begins "([^"\n]*)")?/g
// What a worker acts on: each range pointer replaced by the fixture lines it names, less a leading ## heading line, trimmed as section text is. A named line that does not begin with its anchor throws.
const readOf = (prompt, text) => prompt.replace(POINTER, (_, from, to, open, first, after) => {
  const lines = text.split('\n')
  const start = Number(from || open)
  const anchored = (n, want) => {
    if (!lines[n - 1].replace(/^#+\s*/, '').startsWith(want)) throw new Error(`line ${n} does not begin with "${want}"`)
  }
  anchored(start, first)
  if (!open) anchored(Number(to) + 1, after)
  const body = lines.slice(start - 1, open ? lines.length : Number(to))
  if (/^##\s/.test(body[0])) body.shift()
  return body.join('\n').trim()
})
// The pointer to the fixture lines from the line equal to first up to the line before the line equal to next, or to the end when next is null.
const pointerTo = (text, first, firstText, next = null, nextText = null) => {
  const lines = text.split('\n')
  const from = lines.indexOf(first) + 1
  if (next == null) return `read from line ${from} to the end of the plan note: line ${from} begins "${firstText}"`
  const after = lines.indexOf(next, from) + 1
  return `read lines ${from}-${after - 1} of the plan note: line ${from} begins "${firstText}" and line ${after} begins "${nextText}"`
}
const PLAN_PATH = '/vault/AI/Projects/demo/plan - widget-export.md'
const SHA_CHECK = "bash /plugin/scripts/vault-fs.sh sha256 'Projects/demo/plan - widget-export.md'"
// The pointer to a ## section that ends before the ## next heading, or at the end of the note when next is null.
const sectionAt = (text, name, next = null) => pointerTo(text, `## ${name}`, name, next && `## ${next}`, next)
const noteRefs = (text) => [`PLAN NOTE: ${PLAN_PATH}`, SHA_CHECK, indexOf(text).sha256]

const FENCE = '`'.repeat(3)
const FENCE4 = '`'.repeat(4)
const VALIDATION_LINES = ['1. Run the unit tests.', '2. Export one widget by hand.']
const ASSUMPTION = '- The export covers active widgets only.'
const RISK = '- A large export holds the request open.'
const plan = (implLines, validationLines = VALIDATION_LINES) => [
  '---', 'type: plan', 'status: approved', '---', '',
  '## Objective', '', 'Export widgets as CSV.', '',
  '## Assumptions', '', ASSUMPTION, '',
  '## Implementation Steps', '', ...implLines, '',
  ...(validationLines ? ['## Validation Steps', '', ...validationLines, ''] : []),
  '## Risks', '', RISK, '',
  '## Related Topics', '', '- [[Widgets]]',
].join('\n')
const THREE_STEPS = ['1. Add the exporter in src/a.js.', '2. Wire the route in src/b.js.', '3. Document it in docs/widgets.md.']
const PLAN = plan(THREE_STEPS)
const FENCED_PLAN = plan(['1. Add the exporter.', '2. Add the doc snippet:', '', FENCE + 'md', '## Validation Steps', '1. Not a step.', FENCE, '', '3. Wire the route.'])
const HEADED_PLAN = plan(['### 1. Add the exporter', '', 'Write src/a.js.', '', '### 2. Wire the route', '', '1. Add the handler.', '2. Register it.', '', '### 3. Document it', '', 'Edit docs/widgets.md.'])
const TILDE_PLAN = plan(['1. Add the exporter.', '2. Add the doc snippet:', '', '~~~md', '## Validation Steps', '### 9. Not a step', '1. Not a step.', '~~~', '', '3. Wire the route.'])
const NESTED_PLAN = plan(['1. Add the exporter.', '2. Add the doc snippet:', '', FENCE4 + 'md', FENCE + 'bash', '## Validation Steps', '1. Not a step.', FENCE, FENCE4, '', '3. Wire the route.'])
const REFERENCE_PLAN = plan(['### Directory layout', '', 'src/a.js', '', '1. Add the exporter.', '', '### Reference', '', 'See src/x.js.', '', '2. Wire the route.', '3. Document it.'])
const INFO_FENCE_PLAN = plan(['1. Add the exporter.', '2. Add the doc snippet:', '', FENCE, FENCE + 'js', '## Validation Steps', '1. Not a step.', FENCE, '', '3. Wire the route.'])
const PROSE_PLAN = plan(['Add the exporter in src/a.js and wire the route.', '', 'Then document it.'])
const PAREN_PLAN = plan(['1) Add the exporter.', '2) Wire the route.'])
const PREAMBLE_PLAN = plan(['Read the exporter notes first.', '', '### 1. Add the exporter', 'Write src/a.js.', '### 2. Wire the route', 'Edit src/b.js.'])
const FENCED_PREAMBLE_PLAN = plan([FENCE, '### 1. not a step', FENCE, '', '### 1. Add the exporter', 'Write src/a.js.', '### 2. Wire the route', 'Edit src/b.js.'])
const LISTED_PREAMBLE_PLAN = plan(['1. Read the notes first.', '', '### 1. Add the exporter', 'Write src/a.js.', '### 2. Wire the route', 'Edit src/b.js.'])
const TIGHT_HEADING_PLAN = plan(['### 1. Add the exporter', 'Write src/a.js.', '### 2.Wire the route', '', '1. Add the handler.', '2. Register it.'])
const STEP_HEADED_PLAN = plan(['### Step 1: Skeleton', '', '1. Create src/a.js.', '2. Export the module.', '', '### Step 2: Schema', '', '1. Add the widgets table.', '2. Seed one widget.'])
const PHASE_PLAN = plan(['### Phase A', '', 'Build the exporter.', '', '### Phase B', '', 'Wire the route.'])
const SUBSTEP_PLAN = plan(['### Step 1: Skeleton', '', '1. Create src/a.js.', '2. Export the module.', '', '### Step 2: Route', '', 'Wire the route in src/b.js.'])
const TRIPWIRE_LINES = [...VALIDATION_LINES, '3. Import the export back.', '', '### Tripwires', '', '1. The export writes no rows.', '2. The import rejects the header row.']
const TRIPWIRE_STEP_3 = '3. Import the export back.\n\n### Tripwires\n\n1. The export writes no rows.\n2. The import rejects the header row.'
const BULLET_HEADED_LINES = ['### Automated', '', '- Run the unit tests.', '', '### Manual', '', '- Export one widget by hand.']
const INTRO_HEADING_PLAN = plan(['### Overview', '', 'The exporter streams rows.', '', ...THREE_STEPS])
const MIXED_HEADING_PLAN = plan(['### 1. Add the exporter', '', '### Notes', '', 'Keep rows streamed.', '', '### 2. Wire the route', '', 'Edit src/b.js.'])
const TWO_TRAILERS_PLAN = plan([...THREE_STEPS, '', '### Tripwires', '', '1. The export writes no rows.', '', '### Rollback', '', '1. Revert src/b.js.'])
const SPACED_HEADING_PLAN = PLAN.replace('## Assumptions', '##  Affected Files\n\n- src/a.js: exporter\n\n## Assumptions')
const TAB_HEADING_PLAN = PLAN.replace('## Risks', '##\tRisks')
const SECTIONED_PLAN = PLAN.replace('## Assumptions', '## Current Context\n\nThe exporter lives in src/a.js.\n\n## Affected Files\n\n- src/a.js: exporter\n\n## Plan Changes During Execution\n\n- Step 1: streamed rows instead.\n\n## Assumptions')

const E2E_PLAN = plan(THREE_STEPS, ['1. Run the unit tests.', '2. [e2e] Load the widget page.'])
const INTRO_PLAN = plan(THREE_STEPS, ['Run these against the local site.', '', '1. [e2e] Load the widget page.', '2. Run the unit tests.'])

const ARGS = { planName: 'widget-export', repoRoot: '/repo', repoName: 'demo', planPath: PLAN_PATH, recallHits: 'none', scratchDir: '/scratch', pluginRoot: '/plugin', vaultRoot: '/vault/AI' }
const SEAT_ARGS = { ...ARGS, plan: E2E_PLAN, seatRun: true, baselineFailing: [], diffBase: '0123abcd4567' }
const SEAT_PANEL = { ...SEAT_ARGS, priorChangedPaths: ['src/a.js'] }
const OWN_WT_PATHSPEC = "':(exclude,top).claude/worktrees/'"
const GIT_RULE = 'In /repo, git is read-only: git status, git diff, git log, git ls-files, git branch --show-current, git remote get-url, git symbolic-ref with one ref argument, and git merge-base --is-ancestor only. A -c core.quotePath=false prefix on one of these commands keeps it read-only. Never run git stash, add, commit, checkout, switch, reset, clean, rebase, merge or push there. Mutating git is allowed only inside a fresh fixture you create under /scratch.'
const SCRATCH_ONLY = 'Run embedded commands only against scratch fixtures you create under /scratch, never against /repo.'
const HOOK_SENTENCE = 'Remove a scratch fixture with its literal absolute path under /scratch.'
const HOOK_REFUSAL = 'a bare dot or double dot, a bare glob, a path with a /../ segment, the root, the home dir'
const HOOK_WRITE = "must hold a command the hook refuses, such as a script's recursive delete of a variable, create it with the Write tool"
const BLOCKERS_ONLY = 'The runner stops on any blockers entry, so blockers holds only work you could not do and is empty when the work is done.'
const STDIN_RULE = 'Run any verify or test suite, such as bash verify.sh, with stdin from /dev/null (bash verify.sh </dev/null), because a suite that reads stdin hangs when stdin is a pipe.'
const REPO_STATE = "The tree at repoRoot is the POST-change state this diff produces. There is no pre-change checkout. Reconstruct the pre-change state from the diff's context and removed lines. A defect the diff introduces is in scope even though it is present in the tree."
const STANDING = ['toolkit:code-reviewer', 'toolkit:silent-failure-hunter', 'toolkit:pr-test-analyzer']
const FULL = STANDING.concat(['toolkit:security-reviewer', 'toolkit:performance-reviewer', 'toolkit:coupling-reviewer'])
const DOCS_ONLY = ['toolkit:code-reviewer']
const MODELS = { verifier: { model: 'opus', effort: 'xhigh' }, implementer: { model: 'sonnet', effort: 'high' }, 'code-reviewer': { model: 'fable', effort: 'medium' } }

const stepOf = (changedPaths, extra = {}) => ({ changedPaths, deviations: [], checksRun: ['unit tests'], result: 'Done.', blockers: [], topicMaterial: 'none', ...extra })
const resultOf = (status) => ({ step: '1. Run the unit tests.', status, evidence: `unit tests: ${status}` })
const validationOf = (status) => ({ results: [resultOf(status), { step: '2. Export one widget by hand.', status: 'pass', evidence: 'one row exported' }] })
const PASS = validationOf('pass')
const FAIL = validationOf('fail')
const E2E_STEP = '2. [e2e] Load the widget page.'
const e2eValidationOf = (status) => ({ results: [resultOf('pass'), { step: E2E_STEP, status, evidence: `widget page: ${status}` }] })
const introValidationOf = (status) => ({ results: [{ step: '1. [e2e] Load the widget page.', status, evidence: `widget page: ${status}` }, { ...resultOf('pass'), step: '2. Run the unit tests.' }] })
const SEAT_STRAY = 'The seat run left paths that no fix wrote: test-results/x.png.'
const E2E_REQUIRED = "The plan's e2e option is required and no Validation Step carries the [e2e] marker after its number."
const diffOf = (hash12, empty = false, paths = ['src/a.js']) => ({ diffPath: `/scratch/slice-${hash12}.diff`, hash12, empty, paths })
const finding = (file, title, extra = {}) => ({ title, file, line: 4, dimension: 'code-reviewer', tag: 'important', finalTag: 'important', impact: 0.8, likelihood: 0.6, confidence: 0.5, citation: `${file}:4`, score: 0.68, finalScore: 0.7, reproduction: 'node fixture.js printed TypeError at a.js:4', reproduced: true, verdict: 'real', reasoning: 'Reproduced.', detail: 'Evidence at the line.', failure_scenario: 'A null widget throws.', ...extra })
const nit = (file, title) => finding(file, title, { tag: 'nit', finalTag: 'nit', finalScore: 0.4, reproduction: '', reproduced: false })
const unreproduced = (file, title) => finding(file, title, { finalScore: 0.7, reproduction: '', reproduced: false, reason: 'not reproduced' })
const F1 = finding('src/a.js', 'Null widget crashes the export')
const F2 = finding('src/b.js', 'Route skips the auth check')
const F3 = finding('src/c.js', 'Null widget crashes the export')
const N1 = nit('src/d.js', 'Name hides intent')
const L1 = finding('src/a.js', 'Low but reproduced', { finalTag: 'nit', finalScore: 0.4 })
const W1 = finding('src/a.js', 'Weak logic claim', { finalScore: 0.45 })
const reviewOf = (confirmed, extra = {}) => ({ confirmed, nits: [], preExisting: [], refuted: [], unverified: [], dropped: [], openQuestions: [], dead: [], verifierDead: [], panel: STANDING, dimensions: ['cold-read', 'external-reviewer'], ...extra })
const resolvedOf = (...fs) => ({ results: fs.map((f) => ({ file: f.file, title: f.title, resolved: true, evidence: 'Guard added.' })) })
const docPassOf = (extra = {}) => ({ docsUpdated: [], deferred: [], distributed: [], changedPaths: [], blockers: [], topicMaterial: 'none', ...extra })
const coldOf = (...verified) => ({ findings: verified.map((v, i) => ({ file: 'src/a.js', title: `title ${i}`, issue: `issue ${i}`, fix: 'Rename it.', tag: 'important', impact: 0.8, likelihood: 0.6, confidence: 0.5, citation: 'src/a.js:4', verified: v })) })

const DEFAULTS = {
  'prep:baseline': { branch: 'feat/widget-export', status: [], verify: { command: 'npm test', exitCode: 0, failing: [] } },
  'implement:1': stepOf(['src/a.js'], { topicMaterial: 'The exporter streams rows (src/a.js:4).' }),
  'implement:2': stepOf(['src/b.js']),
  'implement:3': stepOf(['src/c.js']),
  'verify:validation': PASS,
  'fix:validation': stepOf(['src/a.js']),
  'verify:revalidation': PASS,
  'diff:red-team': diffOf('aaaaaaaaaaaa'),
  'workflow:review-mr': reviewOf([]),
  'fix:1': stepOf(['src/a.js']),
  'recheck:1': resolvedOf(),
  'diff:final': diffOf('aaaaaaaaaaaa'),
  'cold:read': coldOf(),
  'doc:pass': docPassOf(),
  'verify:final': PASS,
  'diff:post-doc': diffOf('cccccccccccc'),
  'remember:pass': { proposals: [], topicsUpdated: ['[[Widgets]]'], rememberLine: 'Remember: topics updated [[Widgets]]', blockers: [] },
}
// Reaches every agent label once: a validation fix, one resolved fix round, then verify:final.
const FULL_RUN = { 'verify:validation': FAIL, 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1), 'diff:final': diffOf('bbbbbbbbbbbb') }
const V = 'toolkit:verifier'
const I = 'toolkit:implementer'
const AGENT_TYPES = { 'cold:read': 'toolkit:code-reviewer', 'diff:final': V, 'diff:post-doc': V, 'diff:red-team': V, 'doc:pass': I, 'fix:1': I, 'fix:validation': I, 'implement:1': I, 'implement:2': I, 'implement:3': I, 'plan:index': V, 'prep:baseline': V, 'recheck:1': V, 'remember:pass': I, 'verify:final': V, 'verify:revalidation': V, 'verify:validation': V }
const PHASES = { 'cold:read': 'Cold read', 'diff:final': 'Cold read', 'diff:post-doc': 'Doc pass', 'diff:red-team': 'Red team', 'doc:pass': 'Doc pass', 'fix:1': 'Fix', 'fix:validation': 'Verify', 'implement:1': 'Implement', 'implement:2': 'Implement', 'implement:3': 'Implement', 'plan:index': 'Prep', 'prep:baseline': 'Prep', 'recheck:1': 'Fix', 'remember:pass': 'Remember', 'verify:final': 'Doc pass', 'verify:revalidation': 'Verify', 'verify:validation': 'Verify' }
const RETURN_KEYS = ['baseline', 'steps', 'validation', 'review', 'coldResidual', 'coldUnverified', 'docPass', 'remember', 'changedPaths', 'planChanges', 'diffHashes', 'diffPaths', 'diffFiles', 'blocked', 'incomplete']
const REVIEW_KEYS = ['panel', 'panelRule', 'dimensions', 'confirmed', 'nits', 'preExisting', 'fixed', 'open', 'keptForSteps', 'refuted', 'unverified', 'dropped', 'openQuestions', 'dead', 'verifierDead', 'rounds']
const STEP_BACK = (n, rounds = 1) => `Fix rounds are exhausted at maxFixRounds ${rounds} with ${n} confirmed findings open, so step back and reconsider the approach rather than run another round.`
const INCONSISTENT = `The plan index for ${PLAN_PATH} is inconsistent:`
const changedLine = (text) => `The plan note changed mid-run: sha256 <the printed value>, expected ${indexOf(text).sha256}.`
const MISMATCH_LINE = 'The plan index does not match the plan note at line <its number>, which begins <its first words>.'
// A validation return whose verifier stopped on its plan read, so every step fails with the stop sentence.
const stoppedOf = (why) => ({ results: VALIDATION_LINES.map((step) => ({ step, status: 'fail', evidence: why })) })
const rulesOf = (bullet) => `# Review rules\n## Paths to skip\n- LICENSE\n## High-risk paths\n- ${bullet}\n## Always check\n- docs/x.md`

// Runs the flow with per-label overrides. A null override is a dead stage, an Error makes the child workflow throw.
async function run(overrides = {}, args = ARGS) {
  const { plan: text = PLAN, ...flowArgs } = args
  const script = { ...DEFAULTS, 'plan:index': indexOf(text), ...overrides }
  const prompts = {}
  const agents = {}
  const calls = []
  const agent = async (prompt, opts) => {
    prompts[opts.label] = prompt
    agents[opts.label] = { agentType: opts.agentType, phase: opts.phase, schema: opts.schema, model: opts.model, effort: opts.effort }
    return script[opts.label] ?? null
  }
  const workflow = async (ref, wfArgs) => {
    calls.push({ ref, args: wfArgs })
    const v = script['workflow:review-mr']
    if (v instanceof Error) throw v
    return v ?? null
  }
  try {
    const result = await flow(flowArgs, agent, workflow, () => {}, () => {})
    return { result, prompts, reads: Object.fromEntries(Object.entries(prompts).map(([k, p]) => [k, readOf(p, text)])), agents, calls }
  } catch (error) {
    return { error, prompts, agents, calls }
  }
}

const same = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected)
const implementLabels = (prompts) => Object.keys(prompts).filter((k) => k.startsWith('implement:'))
const stepText = (prompts, n) => prompts[`implement:${n}`].split('YOUR STEP:\n')[1].split('\n\nALREADY CHANGED:')[0]
const byLabel = (agents, field) => Object.fromEntries(Object.keys(agents).sort().map((k) => [k, agents[k][field]]))
const labelsWhere = (prompts, test) => Object.keys(prompts).filter((k) => test(prompts[k])).sort()
const key = (f) => `${f.file}: ${f.title}`
// Runs with the given capture paths and no implementer paths, so the panel rule sees only these.
const onPaths = (paths, args = ARGS) => run({ 'diff:red-team': diffOf('aaaaaaaaaaaa', false, paths), 'implement:1': stepOf([]), 'implement:2': stepOf([]), 'implement:3': stepOf([]) }, args)

const cases = [
  ['missing arg key throws', async () => {
    const { error } = await run({}, { ...ARGS, vaultRoot: undefined })
    return String(error && error.message).includes('execute-runner requires args')
  }],
  ['a plan with no Implementation Steps blocks before prep:baseline', async () => {
    const { result, prompts } = await run({}, { ...ARGS, plan: plan([]) })
    return same({ blocked: result.blocked, baseline: 'prep:baseline' in prompts }, { blocked: ['The plan has no Implementation Steps.'], baseline: false })
  }],
  ['maxFixRounds as the string "1" throws', async () => {
    const { error } = await run({}, { ...ARGS, maxFixRounds: '1' })
    return String(error && error.message).includes('maxFixRounds must be a non-negative integer')
  }],
  ['baselineFailing as a string throws', async () => {
    const { error } = await run({}, { ...ARGS, baselineFailing: 'lint' })
    return String(error && error.message).includes('baselineFailing must be an array of strings')
  }],
  ['baselineFailing replaces the failing list the validation prompt shows', async () => {
    const { result, prompts } = await run({}, { ...ARGS, baselineFailing: ['lint'] })
    return same({ shown: prompts['verify:validation'].includes('"failing":["lint"]'), failing: result.baseline.verify.failing }, { shown: true, failing: ['lint'] })
  }],
  ['priorChangedPaths as a string throws', async () => {
    const { error } = await run({}, { ...ARGS, priorChangedPaths: 'src/z.js' })
    return String(error && error.message).includes('priorChangedPaths must be an array of strings')
  }],
  ['priorChangedPaths seed ALREADY CHANGED, the doc pass and changedPaths', async () => {
    const { result, prompts } = await run({}, { ...ARGS, priorChangedPaths: ['src/z.js'] })
    return same({ implement: prompts['implement:1'].includes('ALREADY CHANGED:\nsrc/z.js\n'), doc: prompts['doc:pass'].includes('CHANGED PATHS:\nsrc/z.js\n'), changedPaths: result.changedPaths },
      { implement: true, doc: true, changedPaths: ['src/z.js', 'src/a.js', 'src/b.js', 'src/c.js'] })
  }],
  ['plan with no Validation Steps blocks and still runs implement:1', async () => {
    const { result, prompts } = await run({}, { ...ARGS, plan: plan(THREE_STEPS, null) })
    return same({ blocked: result.blocked, ran: 'implement:1' in prompts }, { blocked: ['The plan has no Validation Steps, so nothing proves the slice.'], ran: true })
  }],
  ['implement:2 prompt lists the paths implement:1 changed', async () => {
    const { prompts } = await run()
    return prompts['implement:2'].includes('ALREADY CHANGED:\nsrc/a.js\n')
  }],
  ['dead baseline blocks and the run continues to implement:3', async () => {
    const { result, prompts } = await run({ 'prep:baseline': null })
    return same({ blocked: result.blocked, ran: 'implement:3' in prompts }, { blocked: ['The verifier prep:baseline returned nothing.'], ran: true })
  }],
  ['dead implement:2 skips implement:3 and marks incomplete', async () => {
    const { result, prompts } = await run({ 'implement:2': null })
    return same({ ran: 'implement:3' in prompts, incomplete: result.incomplete }, { ran: false, incomplete: ['implement:2'] })
  }],
  ['implement:2 blockers block and skip implement:3', async () => {
    const { result, prompts } = await run({ 'implement:2': stepOf(['src/b.js'], { blockers: ['The test run was denied.'] }) })
    return same({ blocked: result.blocked, ran: 'implement:3' in prompts }, { blocked: ['The implementer implement:2 reported blockers: The test run was denied.'], ran: false })
  }],
  ['every implementer prompt says blockers holds only work the worker could not do', async () => {
    const { prompts } = await run(FULL_RUN)
    const missing = Object.keys(prompts).filter((k) => AGENT_TYPES[k] === I && !prompts[k].includes(BLOCKERS_ONLY))
    return same(missing, [])
  }],
  ['failing validation step runs fix:validation then verify:revalidation, runs 2, child called', async () => {
    const { result, prompts, calls } = await run({ 'verify:validation': FAIL })
    return same({ fix: 'fix:validation' in prompts, reval: 'verify:revalidation' in prompts, runs: result.validation.runs, child: calls.length }, { fix: true, reval: true, runs: 2, child: 1 })
  }],
  ['step still failing after revalidation blocks and skips the child', async () => {
    const { result, calls } = await run({ 'verify:validation': FAIL, 'verify:revalidation': FAIL })
    return same({ blocked: result.blocked, child: calls.length }, { blocked: ['Validation step failed after one fix: 1. Run the unit tests.'], child: 0 })
  }],
  ['pre-existing step runs no fix and does not block', async () => {
    const { result, prompts } = await run({ 'verify:validation': validationOf('pre-existing') })
    return same({ fix: 'fix:validation' in prompts, blocked: result.blocked, preExisting: result.validation.preExisting }, { fix: false, blocked: [], preExisting: ['1. Run the unit tests: unit tests: pre-existing'] })
  }],
  ['manual step lands in manualChecks and does not block', async () => {
    const { result } = await run({ 'verify:validation': validationOf('manual') })
    return same({ manual: result.validation.manualChecks, blocked: result.blocked }, { manual: ['1. Run the unit tests: unit tests: manual'], blocked: [] })
  }],
  ['deferred step in a worktree run lands in deferred and does not block', async () => {
    const { result } = await run({ 'verify:validation': validationOf('deferred') }, { ...ARGS, inWorktree: true })
    return same({ deferred: result.validation.deferred, blocked: result.blocked }, { deferred: ['1. Run the unit tests'], blocked: [] })
  }],
  ['worktree run offers deferred and carries the seat rule', async () => {
    const { prompts, agents } = await run({}, { ...ARGS, inWorktree: true })
    return same({ deferred: agents['verify:validation'].schema.properties.results.items.properties.status.enum.includes('deferred'), rule: prompts['verify:validation'].includes('Report such a STEP as deferred with needs the seat as evidence') }, { deferred: true, rule: true })
  }],
  ['run outside a worktree offers no deferred and no seat rule', async () => {
    const { prompts, agents } = await run({})
    return same({ deferred: agents['verify:validation'].schema.properties.results.items.properties.status.enum.includes('deferred'), rule: prompts['verify:validation'].includes('needs the seat') }, { deferred: false, rule: false })
  }],
  ['inWorktree as a string throws', async () => {
    const { error } = await run({}, { ...ARGS, inWorktree: 'yes' })
    return String(error && error.message).includes('inWorktree must be a boolean')
  }],
  ['the models map lands on every label by its agent type', async () => {
    const { agents } = await run(FULL_RUN, { ...ARGS, models: MODELS })
    const labels = Object.keys(AGENT_TYPES)
    const got = Object.fromEntries(labels.map((k) => [k, agents[k] && { model: agents[k].model, effort: agents[k].effort }]))
    return same(got, Object.fromEntries(labels.map((k) => [k, MODELS[AGENT_TYPES[k].replace('toolkit:', '')]])))
  }],
  ['a models map wrapped in agents throws', async () => {
    const { error } = await run({}, { ...ARGS, models: { agents: MODELS } })
    return String(error && error.message).includes('execute-runner models must map agent names to {model, effort} objects')
  }],
  ['a models map with a bare string entry throws', async () => {
    const { error } = await run({}, { ...ARGS, models: { verifier: 'opus' } })
    return String(error && error.message).includes('execute-runner models must map agent names to {model, effort} objects')
  }],
  ['a missing models map passes neither key to any call', async () => {
    const { agents } = await run(FULL_RUN)
    return Object.values(agents).every((x) => x.model === undefined && x.effort === undefined)
  }],
  ['the models map is forwarded to the review-mr child and omitted when absent', async () => {
    const given = await run({}, { ...ARGS, models: MODELS })
    const absent = await run()
    return same({ given: given.calls[0].args.models, absent: 'models' in absent.calls[0].args }, { given: MODELS, absent: false })
  }],
  ['dead verify:validation blocks and skips the child', async () => {
    const { result, calls } = await run({ 'verify:validation': null })
    return same({ blocked: result.blocked, child: calls.length }, { blocked: ['The verifier verify:validation returned nothing.'], child: 0 })
  }],
  ['empty diff blocks and skips the child', async () => {
    const { result, calls } = await run({ 'diff:red-team': diffOf('e3b0c44298fc', true), 'diff:final': diffOf('e3b0c44298fc', true) })
    return same({ blocked: result.blocked, child: calls.length }, { blocked: ['The diff after implementation is empty.', 'The diff before the cold read is empty.'], child: 0 })
  }],
  ['child is toolkit:review-mr and both cold dimension prompts carry the git rule', async () => {
    const { calls } = await run()
    const dims = calls[0].args.dimensions
    return same({ ref: calls[0].ref, keys: dims.map((d) => d.key), git: dims.every((d) => d.cold && d.prompt.includes(GIT_RULE)) }, { ref: 'toolkit:review-mr', keys: ['cold-read', 'external-reviewer'], git: true })
  }],
  ['child that throws blocks with its message and cold:read still runs', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': new Error('review-mr requires args') })
    return same({ blocked: result.blocked, cold: 'cold:read' in prompts }, { blocked: ['The review-mr child workflow failed: review-mr requires args.'], cold: true })
  }],
  ['child that returns null blocks', async () => {
    const { result } = await run({ 'workflow:review-mr': null })
    return same(result.blocked, ['The review-mr child workflow returned nothing.'])
  }],
  ['finding resolved by file plus title leaves open and blocked empty', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1) })
    return same({ open: result.review.open, blocked: result.blocked }, { open: [], blocked: [] })
  }],
  ['one of two findings resolved at maxFixRounds 1 reports the step-back sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1, F2]), 'recheck:1': resolvedOf(F1) })
    return same(result.blocked, [STEP_BACK(1)])
  }],
  ['maxFixRounds 0 runs no fix:1 and blocks', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1]) }, { ...ARGS, maxFixRounds: 0 })
    return same({ fix: 'fix:1' in prompts, blocked: result.blocked }, { fix: false, blocked: [STEP_BACK(1, 0)] })
  }],
  ['dead fix:1 blocks without the step-back sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': null })
    return same(result.blocked, ['The implementer fix:1 returned nothing.'])
  }],
  ['dead recheck:1 blocks without the step-back sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': null })
    return same(result.blocked, ['The verifier recheck:1 returned nothing.'])
  }],
  ['changed hash with no fix round blocks naming both hashes', async () => {
    const { result } = await run({ 'diff:final': diffOf('bbbbbbbbbbbb') })
    return same(result.blocked, ['The diff hash changed from aaaaaaaaaaaa to bbbbbbbbbbbb with no fix round.'])
  }],
  ['changed hash after a fix round does not block', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1), 'diff:final': diffOf('bbbbbbbbbbbb') })
    return same(result.blocked, [])
  }],
  ['verified cold finding lands in coldResidual, does not block, and doc:pass runs', async () => {
    const { result, prompts } = await run({ 'cold:read': coldOf(true, false) })
    return same({ residual: result.coldResidual.length, unverified: result.coldUnverified.length, blocked: result.blocked, doc: 'doc:pass' in prompts, remember: 'remember:pass' in prompts }, { residual: 1, unverified: 1, blocked: [], doc: true, remember: true })
  }],
  ['SHARED prompts and verify:validation carry the hook rule, the Write-tool sentence goes to SHARED only', async () => {
    const { prompts } = await run(FULL_RUN)
    const keys = ['implement:1', 'fix:1', 'doc:pass', 'verify:validation', 'recheck:1']
    return same({ refusal: keys.filter((k) => prompts[k].includes(HOOK_REFUSAL)), path: keys.filter((k) => prompts[k].includes(HOOK_SENTENCE)), write: keys.filter((k) => prompts[k].includes(HOOK_WRITE)) }, { refusal: ['implement:1', 'fix:1', 'doc:pass', 'verify:validation'], path: ['implement:1', 'fix:1', 'doc:pass', 'verify:validation'], write: ['implement:1', 'fix:1', 'doc:pass'] })
  }],
  ['panel contextBlock carries the settled decisions with Assumptions and Risks', async () => {
    const { calls } = await run()
    const c = readOf(calls[0].args.contextBlock, PLAN)
    return same(['SETTLED DECISIONS:', 'is not a finding', 'unless the tree contradicts the decision', ASSUMPTION, RISK].filter((s) => !c.includes(s)), [])
  }],
  ['panel contextBlock says a rule breach or contradicted doc line is never settled', async () => {
    const { calls } = await run()
    return calls[0].args.contextBlock.includes('is never settled by an Assumption or Risk')
  }],
  ['panel contextBlock falls back to none for a plan with no Assumptions or Risks', async () => {
    const bare = PLAN.replace(`## Assumptions\n\n${ASSUMPTION}\n\n`, '').replace(`## Risks\n\n${RISK}\n\n`, '')
    const { calls } = await run({}, { ...ARGS, plan: bare })
    const c = readOf(calls[0].args.contextBlock, bare)
    return same(['ASSUMPTIONS:\nnone', 'RISKS:\nnone'].filter((s) => !c.includes(s)), [])
  }],
  ['doc:pass changedPaths trigger verify:final, runs 2', async () => {
    const { result, prompts } = await run({ 'doc:pass': docPassOf({ changedPaths: ['docs/widgets.md'] }) })
    return same({ final: 'verify:final' in prompts, runs: result.validation.runs }, { final: true, runs: 2 })
  }],
  ['failing verify:final blocks with the after-doc-pass sentence', async () => {
    const { result } = await run({ 'doc:pass': docPassOf({ changedPaths: ['docs/widgets.md'] }), 'verify:final': FAIL })
    return same(result.blocked, ['Validation step failed after the doc pass: 1. Run the unit tests.'])
  }],
  ['clean run returns blocked empty, remember ran, changedPaths as the union', async () => {
    const { result } = await run({ 'implement:3': stepOf(['src/a.js', 'src/c.js']), 'doc:pass': docPassOf({ changedPaths: ['docs/widgets.md'] }) })
    return same({ blocked: result.blocked, ran: result.remember.ran, changedPaths: result.changedPaths }, { blocked: [], ran: true, changedPaths: ['src/a.js', 'src/b.js', 'src/c.js', 'docs/widgets.md'] })
  }],
  ['blocked run skips remember:pass and returns ran false with the material', async () => {
    const { result, prompts } = await run({ 'prep:baseline': null })
    return same({ called: 'remember:pass' in prompts, remember: result.remember }, { called: false, remember: { ran: false, material: ['The exporter streams rows (src/a.js:4).'], proposals: [], topicsUpdated: [], rememberLine: '' } })
  }],
  ['FENCED_PLAN yields three steps despite a fenced Validation Steps heading', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: FENCED_PLAN })
    return same(implementLabels(prompts), ['implement:1', 'implement:2', 'implement:3'])
  }],
  ['HEADED_PLAN yields three steps despite a numbered sublist in step 2', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: HEADED_PLAN })
    return same(implementLabels(prompts), ['implement:1', 'implement:2', 'implement:3'])
  }],
  ['dead diff:final blocks, skips cold:read and doc:pass, final hash null', async () => {
    const { result, prompts } = await run({ 'diff:final': null })
    return same({ blocked: result.blocked, cold: 'cold:read' in prompts, doc: 'doc:pass' in prompts, final: result.diffHashes.final }, { blocked: ['The verifier diff:final returned nothing.'], cold: false, doc: false, final: null })
  }],
  ['dead cold:read blocks and leaves coldResidual null', async () => {
    const { result } = await run({ 'cold:read': null })
    return same({ blocked: result.blocked, residual: result.coldResidual }, { blocked: ['The code-reviewer cold:read returned nothing.'], residual: null })
  }],
  ['dead doc:pass blocks and leaves docPass null', async () => {
    const { result } = await run({ 'doc:pass': null })
    return same({ blocked: result.blocked, docPass: result.docPass }, { blocked: ['The implementer doc:pass returned nothing.'], docPass: null })
  }],
  ['doc:pass blockers block', async () => {
    const { result } = await run({ 'doc:pass': docPassOf({ blockers: ['The docs tree is read-only.'] }) })
    return same(result.blocked, ['The implementer doc:pass reported blockers: The docs tree is read-only.'])
  }],
  ['fix:1 blockers block', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': stepOf(['src/a.js'], { blockers: ['The edit was denied.'] }), 'recheck:1': resolvedOf(F1) })
    return same(result.blocked, ['The implementer fix:1 reported blockers: The edit was denied.'])
  }],
  ['every label runs as its expected agentType', async () => {
    const { agents } = await run(FULL_RUN)
    return same(byLabel(agents, 'agentType'), AGENT_TYPES)
  }],
  ['every label runs in its expected phase', async () => {
    const { agents } = await run(FULL_RUN)
    return same(byLabel(agents, 'phase'), PHASES)
  }],
  ['capture schema requires paths and remember schema requires blockers', async () => {
    const { agents } = await run(FULL_RUN)
    return same({ diff: agents['diff:red-team'].schema.required, remember: agents['remember:pass'].schema.required.includes('blockers') }, { diff: ['diffPath', 'hash12', 'empty', 'paths'], remember: true })
  }],
  ['child call carries the diff path, repo, context rules, repoState, dimensions and panel', async () => {
    const { calls } = await run()
    const c = calls[0].args
    return same({ diffPath: c.diffPath, repoRoot: c.repoRoot, rules: c.contextBlock.includes(SCRATCH_ONLY) && c.contextBlock.includes(GIT_RULE), repoState: c.repoState, keys: c.dimensions.map((d) => d.key), reviewers: c.registryReviewers }, { diffPath: '/scratch/slice-aaaaaaaaaaaa.diff', repoRoot: '/repo', rules: true, repoState: REPO_STATE, keys: ['cold-read', 'external-reviewer'], reviewers: STANDING })
  }],
  ['the scratch-only rule reaches cold:read and both cold dimensions, no other agent prompt', async () => {
    const { prompts, calls } = await run(FULL_RUN)
    return same({ labels: labelsWhere(prompts, (p) => p.includes(SCRATCH_ONLY)), dims: calls[0].args.dimensions.every((d) => d.prompt.includes(SCRATCH_ONLY)) }, { labels: ['cold:read'], dims: true })
  }],
  ['every agent prompt but plan:index and remember:pass carries the git rule', async () => {
    const { prompts } = await run(FULL_RUN)
    return same(labelsWhere(prompts, (p) => !p.includes(GIT_RULE)), ['plan:index', 'remember:pass'])
  }],
  ['capture prompt guards the untracked filename with --', async () => {
    const { prompts } = await run()
    return prompts['diff:red-team'].includes('git diff --no-index -- /dev/null "$f"')
  }],
  ['capture prompt lists paths with core.quotePath=false so non-ASCII names stay unquoted', async () => {
    const { prompts } = await run()
    return prompts['diff:red-team'].includes('git -c core.quotePath=false diff HEAD --name-only, then git -c core.quotePath=false ls-files --others --exclude-standard')
  }],
  ['remember prompt carries the plan Related Topics under RELATED TOPICS', async () => {
    const { reads } = await run()
    return reads['remember:pass'].includes('RELATED TOPICS:\n- [[Widgets]]')
  }],
  ['clean run returns every top-level key', async () => {
    const { result } = await run()
    return same(Object.keys(result), RETURN_KEYS)
  }],
  ['clean run review returns every review key', async () => {
    const { result } = await run()
    return same(Object.keys(result.review), REVIEW_KEYS)
  }],
  ['capture paths land in diffFiles', async () => {
    const { result } = await run({ 'diff:red-team': diffOf('aaaaaaaaaaaa', false, ['src/a.js', 'notes.txt']), 'diff:final': diffOf('aaaaaaaaaaaa', false, ['notes.txt']), 'diff:post-doc': diffOf('cccccccccccc', false, ['src/a.js', 'docs/widgets.md']) })
    return same(result.diffFiles, { redTeam: ['src/a.js', 'notes.txt'], final: ['notes.txt'], postDoc: ['src/a.js', 'docs/widgets.md'] })
  }],
  ['dead reviewers block with their names and land in review.dead', async () => {
    const { result } = await run({ 'workflow:review-mr': { ...reviewOf([]), dead: ['toolkit:pr-test-analyzer', 'cold-read'] } })
    return same({ blocked: result.blocked, dead: result.review.dead }, { blocked: ['The review panel lost 2 reviewers: toolkit:pr-test-analyzer, cold-read.'], dead: ['toolkit:pr-test-analyzer', 'cold-read'] })
  }],
  ['one result for two steps blocks and skips fix:validation', async () => {
    const { result, prompts } = await run({ 'verify:validation': { results: [resultOf('fail')] } })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: ['Validation returned 1 results for 2 steps.', 'Validation step failed: 1. Run the unit tests.'], fix: false })
  }],
  ['count mismatch at verify:validation stops the run before the child, the cold read and the doc pass', async () => {
    const { result, prompts, calls } = await run({ 'verify:validation': { results: [resultOf('pass')] } })
    return same({ child: calls.length, ran: ['diff:red-team', 'cold:read', 'doc:pass', 'remember:pass'].filter((k) => k in prompts), review: result.review, runs: result.validation.runs }, { child: 0, ran: [], review: null, runs: 1 })
  }],
  ['zero results for two steps blocks', async () => {
    const { result } = await run({ 'verify:validation': { results: [] } })
    return same(result.blocked, ['Validation returned 0 results for 2 steps.'])
  }],
  ['all-manual validation does not block and allPass is false', async () => {
    const { result } = await run({ 'verify:validation': { results: [resultOf('manual'), { ...resultOf('manual'), step: '2. Export one widget by hand.' }] } })
    return same({ blocked: result.blocked, allPass: result.validation.allPass }, { blocked: [], allPass: false })
  }],
  ['empty diff:final after a fix round blocks and skips cold:read', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1), 'diff:final': diffOf('e3b0c44298fc', true) })
    return same({ blocked: result.blocked, cold: 'cold:read' in prompts }, { blocked: ['The diff before the cold read is empty.'], cold: false })
  }],
  ['unverified cold finding lands in coldUnverified and does not block', async () => {
    const { result } = await run({ 'cold:read': coldOf(false) })
    return same({ unverified: result.coldUnverified.map((f) => f.issue), blocked: result.blocked }, { unverified: ['issue 0'], blocked: [] })
  }],
  ['remember:pass blockers block and set ran false', async () => {
    const { result } = await run({ 'remember:pass': { ...DEFAULTS['remember:pass'], blockers: ['The vault-fs.sh mv was denied.'] } })
    return same({ blocked: result.blocked, ran: result.remember.ran }, { blocked: ['The implementer remember:pass reported blockers: The vault-fs.sh mv was denied.'], ran: false })
  }],
  ['planChanges carry the validation fix and each fix round deviation', async () => {
    const { result } = await run({ 'verify:validation': FAIL, 'fix:validation': stepOf(['src/a.js'], { result: 'Guarded the null.', deviations: ['Also touched src/d.js.'] }), 'workflow:review-mr': reviewOf([F1]), 'fix:1': stepOf(['src/a.js'], { deviations: ['Renamed the helper.'] }), 'recheck:1': resolvedOf(F1) })
    return same(result.planChanges, ['Validation fix: Guarded the null.', 'Validation fix deviation: Also touched src/d.js.', 'Fix round 1: Renamed the helper.', 'Fix round 1 resolved: src/a.js: Null widget crashes the export'])
  }],
  ['two fix rounds resolve the second finding on round 2', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1, F2]), 'recheck:1': resolvedOf(F1), 'fix:2': stepOf(['src/b.js']), 'recheck:2': resolvedOf(F2) }, { ...ARGS, maxFixRounds: 2 })
    const fix2 = prompts['fix:2']
    return same({ open: result.review.open, fixed: result.review.fixed.map((f) => f.title), blocked: result.blocked, round2: fix2.includes(F2.title) && !fix2.includes(F1.title) }, { open: [], fixed: [F1.title, F2.title], blocked: [], round2: true })
  }],
  ['a fix round alone triggers verify:final, runs 2', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1) })
    return same({ final: 'verify:final' in prompts, runs: result.validation.runs }, { final: true, runs: 2 })
  }],
  ['dead doc:pass skips remember:pass', async () => {
    const { result, prompts } = await run({ 'doc:pass': null })
    return same({ called: 'remember:pass' in prompts, ran: result.remember.ran }, { called: false, ran: false })
  }],
  ['tilde fence hides a Validation Steps heading and a numbered heading', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: TILDE_PLAN })
    return same({ labels: implementLabels(prompts), validation: reads['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], validation: false })
  }],
  ['four-backtick fence wrapping a three-backtick block keeps its Validation Steps line in step 2', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: NESTED_PLAN })
    return same({ labels: implementLabels(prompts), step2: stepText(reads, 2).includes('## Validation Steps'), validation: reads['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], step2: true, validation: false })
  }],
  ['unnumbered ### subheadings stay inside numbered steps', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: REFERENCE_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(reads, 1).includes('### Directory layout') && stepText(reads, 1).includes('### Reference') }, { labels: ['implement:1', 'implement:2', 'implement:3'], step1: true })
  }],
  ['### Step headings over numbered sub-lists split one step per heading', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: STEP_HEADED_PLAN })
    return same({ labels: implementLabels(prompts), steps: prompts['implement:1'].includes('\n\nSTEPS:\nStep 1: Skeleton (your step)\nStep 2: Schema\n\n'), step2: stepText(reads, 2) }, { labels: ['implement:1', 'implement:2'], steps: true, step2: '### Step 2: Schema\n\n1. Add the widgets table.\n2. Seed one widget.' })
  }],
  ['### Phase headings with no numbered lines split one step per phase', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: PHASE_PLAN })
    return same({ labels: implementLabels(prompts), steps: prompts['implement:1'].includes('\n\nSTEPS:\nPhase A (your step)\nPhase B\n\n') }, { labels: ['implement:1', 'implement:2'], steps: true })
  }],
  ['### headings over a numbered list under the first heading split one step per heading', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: SUBSTEP_PLAN })
    return same({ labels: implementLabels(prompts), steps: prompts['implement:1'].includes('\n\nSTEPS:\nStep 1: Skeleton (your step)\nStep 2: Route\n\n') }, { labels: ['implement:1', 'implement:2'], steps: true })
  }],
  ['numbered Validation Steps with a trailing ### Tripwires list render three STEPs with the tripwires in STEP 3', async () => {
    const { reads } = await run({}, { ...ARGS, plan: plan(THREE_STEPS, TRIPWIRE_LINES) })
    const p = reads['verify:validation']
    return same({ step3: p.includes(`STEP 3:\n${TRIPWIRE_STEP_3}`), count: p.includes('Return exactly 3 results, one per STEP, in order') }, { step3: true, count: true })
  }],
  ['numbered Implementation Steps with a trailing ### Tripwires list run three implementers with the tripwires in step 3', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: plan(TRIPWIRE_LINES) })
    return same({ labels: implementLabels(prompts), step3: stepText(reads, 3) }, { labels: ['implement:1', 'implement:2', 'implement:3'], step3: TRIPWIRE_STEP_3 })
  }],
  ['bullets under two ### headings in Validation Steps render two STEPs', async () => {
    const { reads } = await run({}, { ...ARGS, plan: plan(THREE_STEPS, BULLET_HEADED_LINES) })
    const p = reads['verify:validation']
    return same({ steps: p.includes('STEP 1:\n### Automated\n\n- Run the unit tests.\n\nSTEP 2:\n### Manual\n\n- Export one widget by hand.'), count: p.includes('Return exactly 2 results, one per STEP, in order') }, { steps: true, count: true })
  }],
  ['one intro ### heading over a numbered list splits on the numbered lines', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: INTRO_HEADING_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(reads, 1) }, { labels: ['implement:1', 'implement:2', 'implement:3'], step1: `### Overview\n\nThe exporter streams rows.\n\n${THREE_STEPS[0]}` })
  }],
  ['an unnumbered ### heading between numbered ### headings stays inside its step', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: MIXED_HEADING_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(reads, 1) }, { labels: ['implement:1', 'implement:2'], step1: '### 1. Add the exporter\n\n### Notes\n\nKeep rows streamed.' })
  }],
  ['numbered steps before two ### blocks with their own lists split on the numbered steps', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: TWO_TRAILERS_PLAN })
    return same(implementLabels(prompts), ['implement:1', 'implement:2', 'implement:3'])
  }],
  ['prose-only Implementation Steps run as one step holding the whole text', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: PROSE_PLAN })
    return same({ labels: implementLabels(prompts), step: stepText(reads, 1) }, { labels: ['implement:1'], step: 'Add the exporter in src/a.js and wire the route.\n\nThen document it.' })
  }],
  ['paren markers split the steps', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: PAREN_PLAN })
    return same(implementLabels(prompts), ['implement:1', 'implement:2'])
  }],
  ['the stdin rule reaches the baseline and every validation run', async () => {
    const { prompts } = await run(FULL_RUN)
    return same(labelsWhere(prompts, (p) => p.includes(STDIN_RULE)), ['prep:baseline', 'verify:final', 'verify:revalidation', 'verify:validation'])
  }],
  ['empty diff:post-doc blocks, nulls postDoc and skips remember:pass', async () => {
    const { result, prompts } = await run({ 'diff:post-doc': diffOf('e3b0c44298fc', true) })
    return same({ blocked: result.blocked, hash: result.diffHashes.postDoc, paths: result.diffFiles.postDoc, remember: 'remember:pass' in prompts }, { blocked: ['The diff after the doc pass is empty.'], hash: null, paths: null, remember: false })
  }],
  ['dead diff:post-doc blocks, nulls postDoc and skips remember:pass', async () => {
    const { result, prompts } = await run({ 'diff:post-doc': null })
    return same({ blocked: result.blocked, hash: result.diffHashes.postDoc, paths: result.diffFiles.postDoc, remember: 'remember:pass' in prompts }, { blocked: ['The verifier diff:post-doc returned nothing.'], hash: null, paths: null, remember: false })
  }],
  ['blocked before the doc pass skips doc:pass, verify:final and diff:post-doc and adds no sentence', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': { ...reviewOf([F1]), dead: ['cold-read'] }, 'recheck:1': resolvedOf(F1) })
    return same({ ran: ['doc:pass', 'verify:final', 'diff:post-doc'].filter((k) => k in prompts), docPass: result.docPass, blocked: result.blocked }, { ran: [], docPass: null, blocked: ['The review panel lost 1 reviewers: cold-read.'] })
  }],
  ['clean run still runs doc:pass and diff:post-doc', async () => {
    const { result, prompts } = await run()
    return same({ ran: ['doc:pass', 'diff:post-doc'].filter((k) => k in prompts), docPass: result.docPass !== null }, { ran: ['doc:pass', 'diff:post-doc'], docPass: true })
  }],
  ['count mismatch with a failing result blocks with both sentences and skips fix:validation', async () => {
    const { result, prompts } = await run({ 'verify:validation': FAIL }, { ...ARGS, plan: plan(THREE_STEPS, [...VALIDATION_LINES, '3. Check the log.']) })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: ['Validation returned 2 results for 3 steps.', 'Validation step failed: 1. Run the unit tests.'], fix: false })
  }],
  ['fix:1 blockers at maxFixRounds 2 stop the loop before recheck:1 and fix:2', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': stepOf(['src/a.js'], { blockers: ['The edit was denied.'] }), 'recheck:1': { results: [] }, 'fix:2': stepOf(['src/a.js']) }, { ...ARGS, maxFixRounds: 2 })
    return same(['recheck:1', 'fix:2'].filter((k) => k in prompts), [])
  }],
  ['dead fix:1 with a changed hash yields the dead-fix sentence only', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': null, 'diff:final': diffOf('bbbbbbbbbbbb') })
    return same(result.blocked, ['The implementer fix:1 returned nothing.'])
  }],
  ['same title in another file stays open when only one resolves', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1, F3]), 'recheck:1': resolvedOf(F1) })
    return same(result.review.open.map((f) => f.file), ['src/c.js'])
  }],
  ['count mismatch at verify:revalidation blocks', async () => {
    const { result } = await run({ 'verify:validation': FAIL, 'verify:revalidation': { results: [resultOf('pass')] } })
    return same(result.blocked, ['Validation returned 1 results for 2 steps.'])
  }],
  ['count mismatch at verify:final blocks', async () => {
    const { result } = await run({ 'doc:pass': docPassOf({ changedPaths: ['docs/widgets.md'] }), 'verify:final': { results: [resultOf('pass')] } })
    return same(result.blocked, ['Validation returned 1 results for 2 steps.'])
  }],
  ['a fence line with an info string does not close the open fence', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: INFO_FENCE_PLAN })
    return same({ labels: implementLabels(prompts), validation: reads['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], validation: false })
  }],
  ['remember:pass blockers keep the topicsUpdated the worker reports', async () => {
    const { result } = await run({ 'remember:pass': { ...DEFAULTS['remember:pass'], blockers: ['The vault-fs.sh mv was denied.'] } })
    return same(result.remember.topicsUpdated, ['[[Widgets]]'])
  }],
  ['coldUnverified is null when the cold read did not run', async () => {
    const { result } = await run({ 'diff:final': null })
    return same(result.coldUnverified, null)
  }],
  ['the git rule allows symbolic-ref, merge-base --is-ancestor and the quotePath prefix', async () => {
    const { prompts } = await run()
    const p = prompts['prep:baseline']
    return same(['git symbolic-ref with one ref argument', 'git merge-base --is-ancestor', 'A -c core.quotePath=false prefix on one of these commands keeps it read-only.'].filter((s) => !p.includes(s)), [])
  }],
  ['a bulleted Validation Steps section with a Tripwires block is one STEP and one result does not block', async () => {
    const { result, reads } = await run({ 'verify:validation': { results: [resultOf('pass')] } }, { ...ARGS, plan: plan(THREE_STEPS, ['- Run the unit tests.', '- Export one widget by hand.', '', 'Tripwires:', '- The export writes no rows.']) })
    const p = reads['verify:validation']
    return same({ blocked: result.blocked, step1: p.includes('STEP 1:\n- Run the unit tests.'), step2: p.includes('STEP 2:'), count: p.includes('Return exactly 1 results') }, { blocked: [], step1: true, step2: false, count: true })
  }],
  ['a numbered Validation Steps section renders one STEP per item and asks for that many results', async () => {
    const { reads } = await run()
    const p = reads['verify:validation']
    return same({ steps: p.includes('STEP 1:\n1. Run the unit tests.\n\nSTEP 2:\n2. Export one widget by hand.'), count: p.includes('Return exactly 2 results, one per STEP, in order') }, { steps: true, count: true })
  }],
  ['a review-mr return without dead blocks', async () => {
    const { result } = await run({ 'workflow:review-mr': { confirmed: [], refuted: [], unverified: [], openQuestions: [] } })
    return same({ blocked: result.blocked, dead: result.review.dead }, { blocked: ['The review panel did not report which reviewers ran.'], dead: [] })
  }],
  ['text before ### 1. joins step 1', async () => {
    const { prompts, reads } = await run({}, { ...ARGS, plan: PREAMBLE_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(reads, 1) }, { labels: ['implement:1', 'implement:2'], step1: 'Read the exporter notes first.\n\n### 1. Add the exporter\nWrite src/a.js.' })
  }],
  ['a reviewRules value that is not a string throws', async () => {
    const { error } = await run({}, { ...ARGS, reviewRules: 5 })
    return String(error && error.message).includes('execute-runner reviewRules must be a string when given')
  }],
  ['a reviewMr value that is neither a name nor {scriptPath} throws', async () => {
    const { error } = await run({}, { ...ARGS, reviewMr: { path: '/repo/review-mr.js' } })
    return String(error && error.message).includes('execute-runner reviewMr must be a workflow name or {scriptPath} when given')
  }],
  ['without reviewMr the child ref is toolkit:review-mr', async () => {
    const { calls } = await run()
    return calls[0].ref === 'toolkit:review-mr'
  }],
  ['a reviewMr name is the child ref', async () => {
    const { calls } = await run({}, { ...ARGS, reviewMr: 'x:review-mr' })
    return calls[0].ref === 'x:review-mr'
  }],
  ['a reviewMr {scriptPath} is the child ref', async () => {
    const ref = { scriptPath: '/repo/plugins/toolkit/workflows/review-mr.js' }
    const { calls } = await run({}, { ...ARGS, reviewMr: ref })
    return same(calls[0].ref, ref)
  }],
  ['reviewRules text reaches the contextBlock under its heading', async () => {
    const { calls } = await run({}, { ...ARGS, reviewRules: 'Nit cap five.' })
    return calls[0].args.contextBlock.includes('REVIEW RULES (REVIEW.md on the default branch):\nNit cap five.')
  }],
  ['without reviewRules the contextBlock carries no review rules heading', async () => {
    const { calls } = await run()
    return !calls[0].args.contextBlock.includes('REVIEW RULES')
  }],
  ['docs/a.md and README.md pick the docs-only panel', async () => {
    const { result, calls } = await onPaths(['docs/a.md', 'README.md'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: DOCS_ONLY, rule: 'docs only' })
  }],
  ['a SKILL.md path alone picks the standing panel', async () => {
    const { result, calls } = await onPaths(['plugins/toolkit/skills/x/SKILL.md'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: STANDING, rule: 'standing' })
  }],
  ['a hooks path picks the full panel', async () => {
    const { result, calls } = await onPaths(['plugins/toolkit/hooks/x.sh'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: FULL, rule: 'high-risk path' })
  }],
  ['a scripts path alone picks the full panel', async () => {
    const { result, calls } = await onPaths(['plugins/toolkit/scripts/x.sh'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: FULL, rule: 'high-risk path' })
  }],
  ['a workflows path alone picks the full panel', async () => {
    const { result, calls } = await onPaths(['plugins/toolkit/workflows/x.js'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: FULL, rule: 'high-risk path' })
  }],
  ['a .github markdown path picks the full panel, so high risk beats docs only', async () => {
    const { calls } = await onPaths(['.github/workflows/docs.md'])
    return same(calls[0].args.registryReviewers, FULL)
  }],
  ['a REVIEW.md High-risk paths bullet makes a skill path pick the full panel', async () => {
    const { calls } = await onPaths(['plugins/toolkit/skills/x/SKILL.md'], { ...ARGS, reviewRules: rulesOf('plugins/toolkit/skills/') })
    return same(calls[0].args.registryReviewers, FULL)
  }],
  ['a backticked High-risk paths bullet also picks the full panel', async () => {
    const { calls } = await onPaths(['plugins/toolkit/skills/x/SKILL.md'], { ...ARGS, reviewRules: rulesOf('`plugins/toolkit/skills/`') })
    return same(calls[0].args.registryReviewers, FULL)
  }],
  ['a src path picks the standing panel', async () => {
    const { result, calls } = await onPaths(['src/a.js'])
    return same({ reviewers: calls[0].args.registryReviewers, rule: result.review.panelRule }, { reviewers: STANDING, rule: 'standing' })
  }],
  ['a docs path beside a src path picks the standing panel', async () => {
    const { calls } = await onPaths(['docs/a.md', 'src/a.js'])
    return same(calls[0].args.registryReviewers, STANDING)
  }],
  ['an empty path list picks the standing panel', async () => {
    const { calls } = await onPaths([])
    return same(calls[0].args.registryReviewers, STANDING)
  }],
  ['a Paths to skip bullet in REVIEW.md does not pick the full panel', async () => {
    const { calls } = await onPaths(['LICENSE'], { ...ARGS, reviewRules: rulesOf('plugins/toolkit/skills/') })
    return same(calls[0].args.registryReviewers, STANDING)
  }],
  ['an Always check bullet in REVIEW.md does not pick the full panel', async () => {
    const { calls } = await onPaths(['docs/x.md'], { ...ARGS, reviewRules: rulesOf('plugins/toolkit/skills/') })
    return same(calls[0].args.registryReviewers, DOCS_ONLY)
  }],
  ['result.review reports the chosen panel and rule', async () => {
    const { result } = await onPaths(['plugins/toolkit/hooks/x.sh'])
    return same({ panel: result.review.panel, rule: result.review.panelRule }, { panel: FULL, rule: 'high-risk path' })
  }],
  ['a lost verifier blocks with its dimensions and cold:read still runs', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([], { verifierDead: ['toolkit:code-reviewer'] }) })
    return same({ blocked: result.blocked, cold: 'cold:read' in prompts }, { blocked: ['The review panel lost the verifier for 1 dimensions: toolkit:code-reviewer.'], cold: true })
  }],
  ['a lost reviewer and a lost verifier report both sentences', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { dead: ['cold-read'], verifierDead: ['toolkit:code-reviewer'] }) })
    return same(result.blocked, ['The review panel lost 1 reviewers: cold-read.', 'The review panel lost the verifier for 1 dimensions: toolkit:code-reviewer.'])
  }],
  ['a child without a verifierDead array does not block on it and reports an empty list', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { verifierDead: undefined }) })
    return same({ blocked: result.blocked, verifierDead: result.review.verifierDead }, { blocked: [], verifierDead: [] })
  }],
  ['nits with no confirmed finding start fix:1 under the default nits value', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }) })
    return String(prompts['fix:1']).includes(`NITS:\n${key(N1)} [nit, final score 0.4, not reproduced]`)
  }],
  ['a nits value other than fix or skip throws the nits sentence', async () => {
    const { error } = await run({}, { ...ARGS, nits: 'later' })
    return String(error && error.message).includes('execute-runner nits must be fix or skip when given, got "later"')
  }],
  ['a nits-only round whose recheck resolves N1 puts N1 in review.fixed', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }), 'recheck:1': resolvedOf(N1) })
    return same(result.review.fixed.map(key), [key(N1)])
  }],
  ['nits skip with F1 and N1 renders no nit in fix:1 and keeps N1 out of open and in nits', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1) }, { ...ARGS, nits: 'skip' })
    return same({ none: prompts['fix:1'].includes('NITS:\nnone'), open: result.review.open.map(key), nits: result.review.nits.map(key) }, { none: true, open: [], nits: [key(N1)] })
  }],
  ['nits skip with N1 alone runs no fix:1', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }) }, { ...ARGS, nits: 'skip' })
    return !('fix:1' in prompts)
  }],
  ['a nits-only round at maxFixRounds 2 that leaves N1 open runs no fix:2', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }), 'fix:2': stepOf(['src/d.js']) }, { ...ARGS, maxFixRounds: 2 })
    return 'fix:1' in prompts && !('fix:2' in prompts)
  }],
  ['a seat run with N1 alone and no nits arg runs no fix:1', async () => {
    const { prompts, calls } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }) }, SEAT_PANEL)
    return calls.length === 1 && !('fix:1' in prompts)
  }],
  ['a seat run with F1 and N1 and no nits arg carries N1 into fix:1', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) }, SEAT_PANEL)
    return String(prompts['fix:1']).includes(`NITS:\n${key(N1)} [nit`)
  }],
  ['a seat run with F1 and N1 under nits skip runs fix:1 with no nit', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1) }, { ...SEAT_PANEL, nits: 'skip' })
    return String(prompts['fix:1']).includes('NITS:\nnone')
  }],
  ['a confirmed finding at finalScore 0.4 alone starts fix:1 and resolves', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([L1]), 'recheck:1': resolvedOf(L1) })
    return same({ fix: 'fix:1' in prompts, open: result.review.open, blocked: result.blocked }, { fix: true, open: [], blocked: [] })
  }],
  ['a confirmed nit renders under CONFIRMED FINDINGS with its nit tag and reproduced state', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([L1]), 'recheck:1': resolvedOf(L1) })
    return prompts['fix:1'].includes(`CONFIRMED FINDINGS:\n${key(L1)} [nit, final score 0.4, cited line read]`)
  }],
  ['fix:1 confines a confirmed nit to its cited line', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([L1]), 'recheck:1': resolvedOf(L1) })
    return prompts['fix:1'].includes('Fix a confirmed finding tagged nit only at its cited line')
  }],
  ['fix:1 applies the class rule only to a confirmed finding tagged important at 0.6 or above', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([W1]), 'recheck:1': resolvedOf(W1) })
    return prompts['fix:1'].includes('when its tag is important and its finalScore is 0.6 or above, fix every instance of that class of defect in the slice')
  }],
  ['fix:1 confines an important confirmed finding at 0.45 to its cited line', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([W1]), 'recheck:1': resolvedOf(W1) })
    const p = prompts['fix:1']
    return same([`${key(W1)} [important, final score 0.45, cited line read]`, 'fix any confirmed finding below 0.6 only at its cited line'].filter((s) => !p.includes(s)), [])
  }],
  ['fix:1 lists the confirmed finding and the nit under their own headings with tag, final score and reproduced state', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) })
    const p = prompts['fix:1']
    return same([`CONFIRMED FINDINGS:\n${key(F1)} [important, final score 0.7, reproduced]`, `NITS:\n${key(N1)} [nit, final score 0.4, not reproduced]`].filter((s) => !p.includes(s)), [])
  }],
  ['fix:1 carries the class sentence and the cited-line nit sentence', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) })
    const p = prompts['fix:1']
    return same(['fix every instance of that class of defect in the slice, not one line', 'For each nit, fix only the cited line'].filter((s) => !p.includes(s)), [])
  }],
  ['a nit left open at maxFixRounds 1 does not block and stays open with bucket nit', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1) })
    return same({ blocked: result.blocked, open: result.review.open.map((f) => [key(f), f.bucket]) }, { blocked: [], open: [[key(N1), 'nit']] })
  }],
  ['a confirmed finding at 0.4 left open after fix:1 passes through in open and does not block', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([L1]), 'recheck:1': resolvedOf() })
    return same({ blocked: result.blocked, open: result.review.open.map((f) => [key(f), f.bucket, f.finalScore]) }, { blocked: [], open: [[key(L1), 'confirmed', 0.4]] })
  }],
  ['a nit left open after the confirmed findings resolve at maxFixRounds 2 runs no fix:2', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1), 'fix:2': stepOf(['src/d.js']) }, { ...ARGS, maxFixRounds: 2 })
    return !('fix:2' in prompts)
  }],
  ['recheck:1 asks about the nit as well as the confirmed finding', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) })
    return prompts['recheck:1'].includes(`FINDINGS:\n${key(F1)}\nDETAIL: ${F1.detail}\nFAILURE SCENARIO: ${F1.failure_scenario}\n\n${key(N1)}\nDETAIL:`)
  }],
  ['a confirmed finding and a nit left open count only the confirmed one in the step-back sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }) })
    return same(result.blocked, [STEP_BACK(1)])
  }],
  ['an open confirmed finding at exactly 0.6 blocks with the step-back sentence', async () => {
    const at = finding('src/a.js', 'At the bar', { finalScore: 0.6 })
    const { result } = await run({ 'workflow:review-mr': reviewOf([at]), 'recheck:1': resolvedOf() })
    return same(result.blocked, [STEP_BACK(1)])
  }],
  ['an open confirmed finding at 0.59 does not block', async () => {
    const below = finding('src/a.js', 'Below the bar', { finalScore: 0.59 })
    const { result } = await run({ 'workflow:review-mr': reviewOf([below]), 'recheck:1': resolvedOf() })
    return same(result.blocked, [])
  }],
  ['the step-back count excludes open confirmed findings below 0.6', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1, L1]), 'recheck:1': resolvedOf() })
    return same({ blocked: result.blocked, open: result.review.open.length }, { blocked: [STEP_BACK(1)], open: 2 })
  }],
  ['a not-reproduced unverified entry passes through with its reason and adds no blocked sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { unverified: [unreproduced('src/e.js', 'Race on the export lock')] }) })
    return same({ unverified: result.review.unverified.map((f) => [key(f), f.reason]), blocked: result.blocked }, { unverified: [['src/e.js: Race on the export lock', 'not reproduced']], blocked: [] })
  }],
  ['cold:read lists the confirmed, nit and pre-existing keys and the no-repeat sentence', async () => {
    const pre = finding('src/f.js', 'Old export leaks a handle', { tag: 'pre-existing', finalTag: 'pre-existing' })
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1], preExisting: [pre] }), 'recheck:1': resolvedOf(F1, N1) })
    return prompts['cold:read'].includes(`ALREADY REPORTED BY THE PANEL:\n${key(F1)}\n${key(N1)}\n${key(pre)}\n\nA finding already in that list, by file and title, is not reported again.`)
  }],
  ['a refuted key is absent from the cold:read prompt', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([], { refuted: [{ title: 'Export skips paging', file: 'src/g.js', reason: 'The caller pages.' }] }) })
    return !prompts['cold:read'].includes('src/g.js: Export skips paging')
  }],
  ['nit-cap and no-citation drops and unverified entries are absent from the cold:read prompt', async () => {
    const dropped = [{ title: 'Spacing drifts', file: 'src/h.js', reason: 'nit cap' }, { title: 'Export may leak', file: 'src/i.js', reason: 'no citation' }]
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([], { dropped, unverified: [unreproduced('src/e.js', 'Race on the export lock')] }) })
    return same(['src/h.js: Spacing drifts', 'src/i.js: Export may leak', 'src/e.js: Race on the export lock'].filter((k) => prompts['cold:read'].includes(k)), [])
  }],
  ['cold:read schema requires the scored fields and not citation', async () => {
    const { agents } = await run()
    return same(agents['cold:read'].schema.properties.findings.items.required, ['file', 'title', 'issue', 'fix', 'tag', 'impact', 'likelihood', 'confidence', 'verified'])
  }],
  ['a verified cold finding with a citation lands in coldResidual with score 0.68', async () => {
    const { result } = await run({ 'cold:read': coldOf(true) })
    return same(result.coldResidual.map((f) => [f.title, f.score]), [['title 0', 0.68]])
  }],
  ['a verified cold finding at score 0.39 lands in coldResidual', async () => {
    const { result } = await run({ 'cold:read': { findings: [{ ...coldOf(true).findings[0], impact: 0.4, likelihood: 0.4, confidence: 0.35 }] } })
    return same(result.coldResidual.map((f) => [f.title, f.score]), [['title 0', 0.39]])
  }],
  ['a verified cold finding without a citation lands in coldUnverified', async () => {
    const { result } = await run({ 'cold:read': { findings: [{ ...coldOf(true).findings[0], citation: '' }] } })
    return same({ residual: result.coldResidual, unverified: result.coldUnverified.map((f) => f.title) }, { residual: [], unverified: ['title 0'] })
  }],
  ['nits, preExisting and dropped pass through to result.review', async () => {
    const pre = finding('src/f.js', 'Old export leaks a handle', { finalTag: 'pre-existing' })
    const dropped = [{ title: 'Spacing drifts', file: 'src/h.js', reason: 'nit cap' }]
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1], preExisting: [pre], dropped }) })
    return same({ nits: result.review.nits, preExisting: result.review.preExisting, dropped: result.review.dropped }, { nits: [N1], preExisting: [pre], dropped })
  }],
  ['implement:2 carries its own step and the plan sections as ranges, the other steps as headings, and not the plan', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: HEADED_PLAN })
    const p = prompts['implement:2']
    const present = ['STEPS:\n1. Add the exporter\n2. Wire the route (your step)\n3. Document it\n', `YOUR STEP:\n${pointerTo(HEADED_PLAN, '### 2. Wire the route', '2. Wire the route', '### 3. Document it', '3. Document it')}`, `OBJECTIVE:\n${sectionAt(HEADED_PLAN, 'Objective', 'Assumptions')}`, `ASSUMPTIONS:\n${sectionAt(HEADED_PLAN, 'Assumptions', 'Implementation Steps')}`, `VALIDATION STEPS:\n${sectionAt(HEADED_PLAN, 'Validation Steps', 'Risks')}`, `RISKS:\n${sectionAt(HEADED_PLAN, 'Risks', 'Related Topics')}`, 'CURRENT CONTEXT:\nnone', 'AFFECTED FILES:\nnone', 'PLAN CHANGES DURING EXECUTION:\nnone', ...noteRefs(HEADED_PLAN)]
    const absent = ['PLAN:', 'type: plan', 'Write src/a.js.', 'Edit docs/widgets.md.', '[[Widgets]]', 'Export widgets as CSV.']
    return same({ missing: present.filter((s) => !p.includes(s)), leaked: absent.filter((s) => p.includes(s)) }, { missing: [], leaked: [] })
  }],
  ['implement brief carries Current Context, Affected Files and Plan Changes when the plan has them', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: SECTIONED_PLAN })
    const p = prompts['implement:1']
    return same([`CURRENT CONTEXT:\n${sectionAt(SECTIONED_PLAN, 'Current Context', 'Affected Files')}`, `AFFECTED FILES:\n${sectionAt(SECTIONED_PLAN, 'Affected Files', 'Plan Changes During Execution')}`, `PLAN CHANGES DURING EXECUTION:\n${sectionAt(SECTIONED_PLAN, 'Plan Changes During Execution', 'Assumptions')}`, ...noteRefs(SECTIONED_PLAN)].filter((s) => !p.includes(s)), [])
  }],
  ['a section heading with two spaces after ## still reads its section', async () => {
    const { reads } = await run({}, { ...ARGS, plan: SPACED_HEADING_PLAN })
    return reads['implement:1'].includes('AFFECTED FILES:\n- src/a.js: exporter')
  }],
  ['a section heading with a tab after ## ends the section before it and reads its own', async () => {
    const { reads } = await run({}, { ...ARGS, plan: TAB_HEADING_PLAN })
    const p = reads['implement:1']
    return same({ risks: p.includes(`RISKS:\n${RISK}`), validation: p.split('VALIDATION STEPS:\n')[1].split('\n\nRISKS:')[0] }, { risks: true, validation: VALIDATION_LINES.join('\n') })
  }],
  ['a section heading with a no-break space after ## ends the section before it and reads its own', async () => {
    const { reads } = await run({}, { ...ARGS, plan: PLAN.replace('## Risks', '##\u00a0Risks') })
    const p = reads['implement:1']
    return same({ risks: p.includes(`RISKS:\n${RISK}`), validation: p.split('VALIDATION STEPS:\n')[1].split('\n\nRISKS:')[0] }, { risks: true, validation: VALIDATION_LINES.join('\n') })
  }],
  ['PREAMBLE_PLAN maps step 1 by its marker line, not the preamble', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: PREAMBLE_PLAN })
    return prompts['implement:1'].includes('STEPS:\n1. Add the exporter (your step)\n2. Wire the route\n')
  }],
  ['a numbered line in a fenced preamble does not take step 1\'s heading', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: FENCED_PREAMBLE_PLAN })
    return prompts['implement:1'].includes('STEPS:\n1. Add the exporter (your step)\n')
  }],
  ['a plain numbered preamble line does not take step 1\'s heading in a headed plan', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: LISTED_PREAMBLE_PLAN })
    return prompts['implement:1'].includes('STEPS:\n1. Add the exporter (your step)\n')
  }],
  ['a headed marker with no space after the number is the step heading, not a sub-step', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: TIGHT_HEADING_PLAN })
    return prompts['implement:2'].includes('STEPS:\n1. Add the exporter\n2.Wire the route (your step)\n')
  }],
  ['PROSE_PLAN maps its single step by its first line', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: PROSE_PLAN })
    return prompts['implement:1'].includes('STEPS:\nAdd the exporter in src/a.js and wire the route (your step)\n')
  }],
  ['fix:validation carries the objective, assumptions, plan changes, changed paths and failing steps, not the plan', async () => {
    const { prompts } = await run({ 'verify:validation': FAIL }, { ...ARGS, plan: SECTIONED_PLAN })
    const p = prompts['fix:validation']
    const present = [`OBJECTIVE:\n${sectionAt(SECTIONED_PLAN, 'Objective', 'Current Context')}`, `ASSUMPTIONS:\n${sectionAt(SECTIONED_PLAN, 'Assumptions', 'Implementation Steps')}`, `PLAN CHANGES DURING EXECUTION:\n${sectionAt(SECTIONED_PLAN, 'Plan Changes During Execution', 'Assumptions')}`, 'CHANGED PATHS:\nsrc/a.js\nsrc/b.js\nsrc/c.js\n', 'FAILING VALIDATION STEPS:\n1. Run the unit tests.\nEVIDENCE: unit tests: fail', ...noteRefs(SECTIONED_PLAN)]
    const absent = ['PLAN:', 'type: plan', THREE_STEPS[1], RISK, 'Export widgets as CSV.']
    return same({ missing: present.filter((s) => !p.includes(s)), leaked: absent.filter((s) => p.includes(s)) }, { missing: [], leaked: [] })
  }],
  ['fix:1 carries the objective, assumptions and changed paths, not the plan', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1) })
    const p = prompts['fix:1']
    const present = [`OBJECTIVE:\n${sectionAt(PLAN, 'Objective', 'Assumptions')}`, `ASSUMPTIONS:\n${sectionAt(PLAN, 'Assumptions', 'Implementation Steps')}`, 'CHANGED PATHS:\nsrc/a.js\nsrc/b.js\nsrc/c.js\n', `CONFIRMED FINDINGS:\n${key(F1)}`, ...noteRefs(PLAN)]
    const absent = ['PLAN:', 'type: plan', THREE_STEPS[1], RISK, 'Export widgets as CSV.']
    return same({ missing: present.filter((s) => !p.includes(s)), leaked: absent.filter((s) => p.includes(s)) }, { missing: [], leaked: [] })
  }],
  ['doc:pass carries the objective, affected files, related topics and changed paths, not the plan', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: SECTIONED_PLAN })
    const p = prompts['doc:pass']
    const present = [`OBJECTIVE:\n${sectionAt(SECTIONED_PLAN, 'Objective', 'Current Context')}`, `AFFECTED FILES:\n${sectionAt(SECTIONED_PLAN, 'Affected Files', 'Plan Changes During Execution')}`, `RELATED TOPICS:\n${sectionAt(SECTIONED_PLAN, 'Related Topics')}`, 'CHANGED PATHS:\nsrc/a.js\nsrc/b.js\nsrc/c.js\n', ...noteRefs(SECTIONED_PLAN)]
    const absent = ['PLAN:', 'type: plan', THREE_STEPS[1], ASSUMPTION, RISK, 'Export widgets as CSV.']
    return same({ missing: present.filter((s) => !p.includes(s)), leaked: absent.filter((s) => p.includes(s)) }, { missing: [], leaked: [] })
  }],
  ['no agent prompt carries the plan note whole', async () => {
    const { prompts } = await run(FULL_RUN)
    return same(labelsWhere(prompts, (p) => p.includes('type: plan') || p.includes('## Objective') || p.includes('PLAN:\n')), [])
  }],
  ['seatRun as the string yes throws', async () => {
    const { error } = await run({}, { ...ARGS, seatRun: 'yes' })
    return String(error && error.message).includes('seatRun must be a boolean')
  }],
  ['seatRun with inWorktree true throws', async () => {
    const { error } = await run({}, { ...SEAT_ARGS, inWorktree: true })
    return String(error && error.message).includes('cannot both be true')
  }],
  ['seatRun with no baselineFailing throws', async () => {
    const { error } = await run({}, { ...SEAT_ARGS, baselineFailing: undefined })
    return String(error && error.message).includes('seatRun requires baselineFailing')
  }],
  ['seatRun with no diffBase throws', async () => {
    const { error } = await run({}, { ...SEAT_ARGS, diffBase: undefined })
    return String(error && error.message).includes('seatRun requires diffBase')
  }],
  ['seatRun with a diffBase that is not a sha throws', async () => {
    const { error } = await run({}, { ...SEAT_ARGS, diffBase: 'HEAD; touch x' })
    return String(error && error.message).includes('seatRun requires diffBase')
  }],
  ['diffBase with no seatRun throws', async () => {
    const { error } = await run({}, { ...ARGS, diffBase: '0123abcd4567' })
    return String(error && error.message).includes('diffBase is only valid with seatRun')
  }],
  ['e2e as yes throws', async () => {
    const { error } = await run({}, { ...ARGS, e2e: 'yes' })
    return String(error && error.message).includes('e2e must be required or skip')
  }],
  ['a seat run runs no implementer and its validation prompt forbids a pre-existing end-to-end step', async () => {
    const { prompts } = await run({}, SEAT_ARGS)
    const p = prompts['verify:validation']
    return same({ labels: implementLabels(prompts), never: p.includes('An end-to-end STEP is never pre-existing'), seat: p.includes('needs the seat') }, { labels: [], never: true, seat: false })
  }],
  ['a seat run replaces the baseline failing list with the empty baselineFailing', async () => {
    const { result, prompts } = await run({ 'prep:baseline': { ...DEFAULTS['prep:baseline'], verify: { command: 'npm test', exitCode: 1, failing: ['lint'] } } }, SEAT_ARGS)
    return same({ shown: prompts['verify:validation'].includes('"failing":[]'), failing: result.baseline.verify.failing }, { shown: true, failing: [] })
  }],
  ['a seat run sends a pre-existing end-to-end step to fix:validation', async () => {
    const { prompts } = await run({ 'verify:validation': e2eValidationOf('pre-existing') }, SEAT_ARGS)
    return prompts['fix:validation'].includes(`FAILING VALIDATION STEPS:\n${E2E_STEP}\nEVIDENCE: widget page: pre-existing`)
  }],
  ['a seat run captures the diff from diffBase, not HEAD', async () => {
    const { prompts } = await run({}, SEAT_ARGS)
    const p = prompts['diff:red-team']
    return same({ base: p.includes('git diff 0123abcd4567 >'), head: p.includes('git diff HEAD') }, { base: true, head: false })
  }],
  ['a seat run with an empty capture returns no review, no doc pass and no remember pass', async () => {
    const { result } = await run({ 'diff:red-team': diffOf('e3b0c44298fc', true, []) }, SEAT_ARGS)
    return same({ blocked: result.blocked, review: result.review, docPass: result.docPass, remember: result.remember.ran }, { blocked: [], review: null, docPass: null, remember: false })
  }],
  ['a seat run whose capture holds only priorChangedPaths runs the panel', async () => {
    const { result, calls } = await run({}, { ...SEAT_ARGS, priorChangedPaths: ['src/a.js'] })
    return same({ blocked: result.blocked, child: calls.length }, { blocked: [], child: 1 })
  }],
  ['a seat run with a validation fix runs the panel and the cold read but no doc pass or remember pass', async () => {
    const { result, prompts, calls } = await run({ 'verify:validation': FAIL }, SEAT_ARGS)
    return same({ blocked: result.blocked, child: calls.length, ran: ['cold:read', 'doc:pass', 'remember:pass'].filter((k) => k in prompts) }, { blocked: [], child: 1, ran: ['cold:read'] })
  }],
  ['a seat run blocks on a captured path that no fix wrote and skips the panel', async () => {
    const { result, calls } = await run({ 'verify:validation': FAIL, 'diff:red-team': diffOf('aaaaaaaaaaaa', false, ['src/a.js', 'test-results/x.png']) }, SEAT_ARGS)
    return same({ blocked: result.blocked, child: calls.length }, { blocked: [SEAT_STRAY], child: 0 })
  }],
  ['a seat run ignores a captured path under .claude/worktrees/', async () => {
    const { result, calls } = await run({ 'verify:validation': FAIL, 'diff:red-team': diffOf('aaaaaaaaaaaa', false, ['src/a.js', '.claude/worktrees/feat/x/']) }, SEAT_ARGS)
    return same({ blocked: result.blocked, child: calls.length }, { blocked: [], child: 1 })
  }],
  ['a worktree run defers a marked step the verifier passed', async () => {
    const { result } = await run({ 'verify:validation': e2eValidationOf('pass') }, { ...ARGS, plan: E2E_PLAN, inWorktree: true })
    const r = result.validation.results[1]
    return same({ status: r.status, evidence: r.evidence, deferred: result.validation.deferred }, { status: 'deferred', evidence: 'needs the seat', deferred: ['2. [e2e] Load the widget page'] })
  }],
  ['a worktree run reads the marker on step 1 heading under an intro line', async () => {
    const { result } = await run({ 'verify:validation': introValidationOf('pass') }, { ...ARGS, plan: INTRO_PLAN, inWorktree: true })
    return same(result.validation.results.map((r) => [r.status, r.evidence]), [['deferred', 'needs the seat'], ['pass', 'unit tests: pass']])
  }],
  ['e2e skip reports a marked step as manual and names it in the prompt', async () => {
    const { result, prompts } = await run({ 'verify:validation': e2eValidationOf('pass') }, { ...ARGS, plan: E2E_PLAN, e2e: 'skip' })
    return same({ status: result.validation.results[1].status, manual: result.validation.manualChecks, named: prompts['verify:validation'].includes('End-to-end STEPs: 2') }, { status: 'manual', manual: ['2. [e2e] Load the widget page: e2e: skip'], named: true })
  }],
  ['e2e required with no marked step blocks before the baseline', async () => {
    const { result, prompts } = await run({}, { ...ARGS, e2e: 'required' })
    return same({ blocked: result.blocked, ran: Object.keys(prompts).filter((k) => k === 'plan:index' || k === 'prep:baseline' || k.startsWith('implement:')) }, { blocked: [E2E_REQUIRED], ran: ['plan:index'] })
  }],
  ['e2e required with a marked step runs the baseline and does not block', async () => {
    const { result, prompts } = await run({}, { ...ARGS, plan: E2E_PLAN, e2e: 'required' })
    return same({ blocked: result.blocked, ran: 'prep:baseline' in prompts }, { blocked: [], ran: true })
  }],
  ['a seat run keeps an unmarked pre-existing step pre-existing and runs no validation fix', async () => {
    const { result, prompts } = await run({ 'verify:validation': { results: [resultOf('pre-existing'), { step: E2E_STEP, status: 'pass', evidence: 'widget page: pass' }] } }, SEAT_ARGS)
    return same({ fix: 'fix:validation' in prompts, preExisting: result.validation.preExisting }, { fix: false, preExisting: ['1. Run the unit tests: unit tests: pre-existing'] })
  }],
  ['a worktree run keeps the verifier status of a step that names [e2e] mid-heading', async () => {
    const { result } = await run({ 'verify:validation': PASS }, { ...ARGS, plan: plan(THREE_STEPS, ['1. Run the unit tests.', '2. Check that the guide documents the [e2e] marker.']), inWorktree: true })
    return same(result.validation.results.map((r) => r.status), ['pass', 'pass'])
  }],
  ['a seat run under e2e skip does not tell the verifier to run the end-to-end steps', async () => {
    const { prompts } = await run({}, { ...SEAT_ARGS, e2e: 'skip' })
    return same({ included: prompts['verify:validation'].includes('the end-to-end STEPs included'), apart: prompts['verify:validation'].includes('apart from the end-to-end STEPs named above') }, { included: false, apart: true })
  }],
  ['the default capture carries the own-worktree pathspec on both untracked listings', async () => {
    const { prompts } = await run()
    return prompts['diff:red-team'].split(OWN_WT_PATHSPEC).length - 1 === 2
  }],
  ['a run without planPath throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: undefined })
    return String(error && error.message).includes('execute-runner requires args')
  }],
  ['a planPath outside vaultRoot throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: '/elsewhere/plan - widget-export.md' })
    return String(error && error.message).includes('planPath must be a .md note under vaultRoot')
  }],
  ['a planPath with a single quote in its vault-relative part throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: "/vault/AI/Projects/demo/plan - widget's export.md" })
    return String(error && error.message).includes('planPath must be a .md note under vaultRoot')
  }],
  ['a planPath with a .. segment throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: '/vault/AI/Projects/../plan - widget-export.md' })
    return String(error && error.message).includes('planPath must be a .md note under vaultRoot')
  }],
  ['a planPath with a newline throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: '/vault/AI/Projects/demo/plan\n - widget-export.md' })
    return String(error && error.message).includes('planPath must be a .md note under vaultRoot')
  }],
  ['a planPath that is not a .md note throws', async () => {
    const { error } = await run({}, { ...ARGS, planPath: '/vault/AI/Projects/demo/plan - widget-export.txt' })
    return String(error && error.message).includes('planPath must be a .md note under vaultRoot')
  }],
  ['plan:index runs the vault-fs index command on the vault-relative path', async () => {
    const { prompts } = await run()
    return prompts['plan:index'].includes("bash /plugin/scripts/vault-fs.sh index 'Projects/demo/plan - widget-export.md'")
  }],
  ['a vaultRoot with a trailing slash still indexes the vault-relative path', async () => {
    const { prompts } = await run({}, { ...ARGS, vaultRoot: '/vault/AI/' })
    return prompts['plan:index'].includes("bash /plugin/scripts/vault-fs.sh index 'Projects/demo/plan - widget-export.md'")
  }],
  ['a dead plan:index blocks before prep:baseline and lands in incomplete', async () => {
    const { result, prompts } = await run({ 'plan:index': null })
    return same({ blocked: result.blocked, incomplete: result.incomplete, keys: Object.keys(result), baseline: 'prep:baseline' in prompts }, { blocked: ['The verifier plan:index returned nothing.'], incomplete: ['plan:index'], keys: RETURN_KEYS, baseline: false })
  }],
  ['a plan:index error blocks before prep:baseline', async () => {
    const { result, prompts } = await run({ 'plan:index': { error: 'refused: unknown command: index', sha256: '', sections: [], implementationSteps: [], validationSteps: [] } })
    return same({ blocked: result.blocked, baseline: 'prep:baseline' in prompts }, { blocked: ['The plan index failed: refused: unknown command: index.'], baseline: false })
  }],
  ['section heading lines that do not rise block as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, sections: ix.sections.map((x, i) => (i === 1 ? { ...x, line: ix.sections[0].line } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['an Implementation Step line outside its section blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, implementationSteps: ix.implementationSteps.map((x, i) => (i === 0 ? { ...x, line: 1 } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['Validation Step lines out of order block as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, validationSteps: [...ix.validationSteps].reverse() } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['an index sha256 that is not 64 hex characters blocks as inconsistent', async () => {
    const { result } = await run({ 'plan:index': { ...indexOf(PLAN), sha256: 'abc123' } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['an Implementation Step line past the next section heading blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const next = ix.sections.find((x) => x.name === 'Validation Steps').line
    const { result } = await run({ 'plan:index': { ...ix, implementationSteps: ix.implementationSteps.map((x, i) => (i === 2 ? { ...x, line: next + 1 } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['a Validation Step line past the next section heading blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const next = ix.sections.find((x) => x.name === 'Risks').line
    const { result } = await run({ 'plan:index': { ...ix, validationSteps: ix.validationSteps.map((x, i) => (i === 1 ? { ...x, line: next + 1 } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['Implementation Step lines out of order block as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, implementationSteps: [...ix.implementationSteps].reverse() } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['a section line that is not an integer blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, sections: ix.sections.map((x, i) => (i === 0 ? { ...x, line: x.line - 0.5 } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['a section line of 0 blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, sections: ix.sections.map((x, i) => (i === 0 ? { ...x, line: 0 } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['Implementation Steps with no Implementation Steps section block as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const { result } = await run({ 'plan:index': { ...ix, sections: ix.sections.filter((x) => x.name !== 'Implementation Steps') } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['a relayed e2e flag that does not match its step heading blocks as inconsistent', async () => {
    const ix = indexOf(E2E_PLAN)
    const { result } = await run({ 'plan:index': { ...ix, validationSteps: ix.validationSteps.map((x, i) => (i === 0 ? { ...x, e2e: true } : x)) } }, { ...ARGS, plan: E2E_PLAN, inWorktree: true })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['a relayed e2e false on a step whose heading carries [e2e] blocks as inconsistent', async () => {
    const ix = indexOf(E2E_PLAN)
    const { result } = await run({ 'plan:index': { ...ix, validationSteps: ix.validationSteps.map((x, i) => (i === 1 ? { ...x, e2e: false } : x)) } }, { ...ARGS, plan: E2E_PLAN, inWorktree: true })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['an Implementation Step line on the next section heading line blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const next = ix.sections.find((x) => x.name === 'Validation Steps').line
    const { result } = await run({ 'plan:index': { ...ix, implementationSteps: ix.implementationSteps.map((x, i) => (i === 2 ? { ...x, line: next } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['an Implementation Step line on its own section heading line blocks as inconsistent', async () => {
    const ix = indexOf(PLAN)
    const own = ix.sections.find((x) => x.name === 'Implementation Steps').line
    const { result } = await run({ 'plan:index': { ...ix, implementationSteps: ix.implementationSteps.map((x, i) => (i === 0 ? { ...x, line: own } : x)) } })
    return same(result.blocked.map((b) => b.startsWith(INCONSISTENT)), [true])
  }],
  ['every plan block travels as a range, Objective included', async () => {
    const { prompts, calls } = await run(FULL_RUN)
    return same({ objective: prompts['implement:1'].includes(`OBJECTIVE:\n${sectionAt(PLAN, 'Objective', 'Assumptions')}`), leaked: labelsWhere({ ...prompts, contextBlock: calls[0].args.contextBlock }, (p) => p.includes('Export widgets as CSV.')) }, { objective: true, leaked: [] })
  }],
  ['step 1 starts at its section heading, so its preamble stays with it', async () => {
    const { prompts } = await run({}, { ...ARGS, plan: PREAMBLE_PLAN })
    return prompts['implement:1'].includes(`YOUR STEP:\n${pointerTo(PREAMBLE_PLAN, '## Implementation Steps', 'Implementation Steps', '### 2. Wire the route', '2. Wire the route')}`)
  }],
  ['each step ends at the line before the next step', async () => {
    const { prompts } = await run()
    return prompts['implement:2'].includes(`YOUR STEP:\n${pointerTo(PLAN, THREE_STEPS[1], THREE_STEPS[1], THREE_STEPS[2], THREE_STEPS[2])}`)
  }],
  ['a section ends at the next heading the runner does not read', async () => {
    const rollback = PLAN.replace('## Related Topics', '## Rollback Notes\n\n- Revert src/b.js.\n\n## Related Topics')
    const { prompts } = await run({}, { ...ARGS, plan: rollback })
    return prompts['implement:1'].includes(`RISKS:\n${sectionAt(rollback, 'Risks', 'Rollback Notes')}`)
  }],
  ['the last section runs to the end of the note', async () => {
    const { prompts } = await run()
    return prompts['doc:pass'].includes(`RELATED TOPICS:\n${sectionAt(PLAN, 'Related Topics')}`)
  }],
  ['every plan-reading prompt carries the plan note path, the sha check, the index sha and the anchor rule', async () => {
    const { prompts, calls } = await run(FULL_RUN)
    const texts = { ...prompts, contextBlock: calls[0].args.contextBlock }
    const labels = ['implement:1', 'implement:2', 'implement:3', 'fix:validation', 'fix:1', 'doc:pass', 'remember:pass', 'verify:validation', 'verify:revalidation', 'verify:final', 'contextBlock']
    const needed = [...noteRefs(PLAN), 'If a named line does not begin with the text the block gives', 'a line after line A inside the range starts with ## and a space or tab outside a fenced block']
    return same(labels.filter((k) => !needed.every((n) => String(texts[k]).includes(n))), [])
  }],
  ['an implementer, fix, doc or remember worker stops with the mid-run or mismatch blocker', async () => {
    const { prompts } = await run(FULL_RUN)
    const stops = [`record "${changedLine(PLAN)}" as your only blockers entry and stop`, `record "${MISMATCH_LINE}" as your only blockers entry and stop`]
    return same(['implement:1', 'implement:2', 'implement:3', 'fix:validation', 'fix:1', 'doc:pass', 'remember:pass'].filter((k) => !stops.every((x) => prompts[k].includes(x))), [])
  }],
  ['a validation verifier fails every step with the stop sentence', async () => {
    const { prompts } = await run(FULL_RUN)
    const fails = [`return every STEP as fail with "${changedLine(PLAN)}" as its evidence`, `return every STEP as fail with "${MISMATCH_LINE}" as its evidence`]
    return same(['verify:validation', 'verify:revalidation', 'verify:final'].filter((k) => !fails.every((x) => prompts[k].includes(x))), [])
  }],
  ['the panel treats a stopped block as none', async () => {
    const { calls } = await run()
    const c = calls[0].args.contextBlock
    return same(['read nothing from the file and treat every such block as none', 'act on nothing from that block and treat that block as none'].filter((x) => !c.includes(x)), [])
  }],
  ['a validation run that reports the plan note changed blocks before fix:validation', async () => {
    const { result, prompts } = await run({ 'verify:validation': stoppedOf('The plan note changed mid-run: sha256 x, expected y.') })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: ['The verifier verify:validation ran no Validation Step: The plan note changed mid-run: sha256 x, expected y.'], fix: false })
  }],
  ['a validation run that reports an index mismatch blocks before fix:validation', async () => {
    const why = 'The plan index does not match the plan note at line 9, which begins Assumptions.'
    const { result, prompts } = await run({ 'verify:validation': stoppedOf(why) })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: [`The verifier verify:validation ran no Validation Step: ${why}`], fix: false })
  }],
  ['a verify:final that reports a stop blocks with one sentence', async () => {
    const why = 'The plan note changed mid-run: sha256 x, expected y.'
    const { result } = await run({ ...FULL_RUN, 'verify:final': stoppedOf(why) })
    return same(result.blocked, [`The verifier verify:final ran no Validation Step: ${why}`])
  }],
  ['a verify:revalidation that reports a stop blocks with one sentence', async () => {
    const why = 'The plan note changed mid-run: sha256 x, expected y.'
    const { result } = await run({ 'verify:validation': FAIL, 'verify:revalidation': stoppedOf(why) })
    return same(result.blocked, [`The verifier verify:revalidation ran no Validation Step: ${why}`])
  }],
  ['a stop sentence the verifier kept in quotes still blocks before fix:validation', async () => {
    const why = '"The plan note changed mid-run: sha256 x, expected y."'
    const { result, prompts } = await run({ 'verify:validation': stoppedOf(why) })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: [`The verifier verify:validation ran no Validation Step: ${why}`], fix: false })
  }],
  ['a worktree run whose every Validation Step is e2e still blocks on a stop', async () => {
    const why = 'The plan note changed mid-run: sha256 x, expected y.'
    const { result } = await run({ 'verify:validation': stoppedOf(why) }, { ...ARGS, plan: plan(THREE_STEPS, ['1. [e2e] Load the widget page.', '2. [e2e] Export one widget in the browser.']), inWorktree: true })
    return same(result.blocked, [`The verifier verify:validation ran no Validation Step: ${why}`])
  }],
  ['a passing Validation Step whose evidence quotes a stop sentence does not block', async () => {
    const quoted = { results: [{ ...PASS.results[0], evidence: "grep -l 'The plan note changed mid-run' plugins/toolkit/workflows/execute-runner.js printed plugins/toolkit/workflows/execute-runner.js" }, PASS.results[1]] }
    const { result, prompts } = await run({ 'verify:validation': quoted })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts, redTeam: 'diff:red-team' in prompts }, { blocked: [], fix: false, redTeam: true })
  }],
  ['a passing Validation Step whose evidence opens with a stop sentence does not block', async () => {
    const quoted = { results: [{ ...PASS.results[0], evidence: '"The plan note changed mid-run" appears in plugins/toolkit/workflows/execute-runner.js' }, PASS.results[1]] }
    const { result } = await run({ 'verify:validation': quoted })
    return same(result.blocked, [])
  }],
  ['a failing Validation Step whose evidence quotes a stop sentence runs fix:validation', async () => {
    const quoted = { results: [{ ...FAIL.results[0], evidence: "grep -qF 'The plan note changed mid-run' plugins/toolkit/workflows/execute-runner.js exited 1" }, FAIL.results[1]] }
    const { result, prompts } = await run({ 'verify:validation': quoted })
    return same({ blocked: result.blocked, fix: 'fix:validation' in prompts }, { blocked: [], fix: true })
  }],
  ['fix:1 carries the Validation Steps range and the skip rule', async () => {
    const { prompts } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) })
    const p = prompts['fix:1']
    return same([`VALIDATION STEPS:\n${sectionAt(PLAN, 'Validation Steps', 'Risks')}`, 'unfixed when its fix would make a step under VALIDATION STEPS fail', 'return each one in skipped'].filter((x) => !p.includes(x)), [])
  }],
  ['fix:<round> runs with the FIX schema', async () => {
    const { agents } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1) })
    return agents['fix:1'].schema.properties.skipped.type === 'array'
  }],
  ['a nit the fix round skips for a Validation Step leaves open and lands in keptForSteps', async () => {
    const step = 'STEP 1: Run the unit tests'
    const { result } = await run({ 'workflow:review-mr': reviewOf([], { nits: [N1] }), 'fix:1': stepOf(['src/a.js'], { skipped: [{ key: key(N1), step }] }) })
    return same({ open: result.review.open.map(key), kept: result.review.keptForSteps.map((f) => [key(f), f.round, f.step]), line: result.planChanges.includes(`Fix round 1 kept for a Validation Step: src/d.js: Name hides intent [nit, score 0.68, final 0.4] (${step})`) },
      { open: [], kept: [[key(N1), 1, step]], line: true })
  }],
  ['a finding the second fix round skips lands in keptForSteps with round 2', async () => {
    const step = 'STEP 1: Run the unit tests'
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1, L1]), 'recheck:1': resolvedOf(F1), 'fix:2': stepOf(['src/a.js'], { skipped: [{ key: key(L1), step }] }) }, { ...ARGS, maxFixRounds: 2 })
    return same(result.review.keptForSteps.map((f) => [key(f), f.round, f.step]), [[key(L1), 2, step]])
  }],
  ['a skipped confirmed finding below the threshold starts no recheck and no second round', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([L1]), 'fix:1': stepOf(['src/a.js'], { skipped: [{ key: key(L1), step: 'STEP 1: Run the unit tests' }] }) }, { ...ARGS, maxFixRounds: 2 })
    return same({ recheck: 'recheck:1' in prompts, fix2: 'fix:2' in prompts, kept: result.review.keptForSteps.map(key), blocked: result.blocked }, { recheck: false, fix2: false, kept: [key(L1)], blocked: [] })
  }],
  ['a skipped confirmed finding at or above the threshold stays open', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': stepOf(['src/a.js'], { skipped: [{ key: key(F1), step: 'STEP 1: Run the unit tests' }] }) })
    return same({ open: result.review.open.map(key), kept: result.review.keptForSteps, blocked: result.blocked }, { open: [key(F1)], kept: [], blocked: [STEP_BACK(1)] })
  }],
  ['a skipped key that names no open finding changes nothing', async () => {
    const plain = await run({ 'workflow:review-mr': reviewOf([F1]) })
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': stepOf(['src/a.js'], { skipped: [{ key: 'src/z.js: Not a finding', step: 'STEP 1: Run the unit tests' }] }) })
    return same({ open: result.review.open, kept: result.review.keptForSteps }, { open: plain.result.review.open, kept: [] })
  }],
  ['fix:1 reads the plan\'s Validation Steps and no step body', async () => {
    const { reads } = await run({ 'workflow:review-mr': reviewOf([F1], { nits: [N1] }), 'recheck:1': resolvedOf(F1, N1) })
    const r = reads['fix:1']
    return same({ validation: r.includes(`VALIDATION STEPS:\n${VALIDATION_LINES.join('\n')}`), leaked: [THREE_STEPS[1], RISK].filter((x) => r.includes(x)) }, { validation: true, leaked: [] })
  }],
  ['a step heading over 120 characters reaches STEPS cut at 120', async () => {
    const long = '1. ' + 'w'.repeat(200)
    const { prompts } = await run({}, { ...ARGS, plan: plan([long, '2. Wire the route.']) })
    const p = prompts['implement:1']
    return same({ cut: p.includes(`STEPS:\n${long.slice(0, 120)} (your step)\n`), whole: p.includes(long.slice(0, 121)) }, { cut: true, whole: false })
  }],
]

let passed = 0
let failed = 0
for (const [name, test] of cases) {
  let ok = false
  try {
    ok = await test()
  } catch (e) {
    console.log(`  ERROR ${name}: ${e.message}`)
  }
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}`)
  if (ok) passed += 1
  else failed += 1
}
console.log('')
console.log(`RESULT: ${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
