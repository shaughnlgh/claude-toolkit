// The script body uses top-level await and return, so it compiles inside an AsyncFunction.
import { readFileSync } from 'node:fs'

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const source = readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const flow = new AsyncFunction('args', 'agent', 'workflow', 'phase', 'log', source)

const FENCE = '`'.repeat(3)
const FENCE4 = '`'.repeat(4)
const VALIDATION_LINES = ['1. Run the unit tests.', '2. Export one widget by hand.']
const plan = (implLines, validationLines = VALIDATION_LINES) => [
  '---', 'type: plan', 'status: approved', '---', '',
  '## Objective', '', 'Export widgets as CSV.', '',
  '## Implementation Steps', '', ...implLines, '',
  ...(validationLines ? ['## Validation Steps', '', ...validationLines, ''] : []),
  '## Risks', '', 'None.', '',
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

const ARGS = { planName: 'widget-export', repoRoot: '/repo', repoName: 'demo', planContent: PLAN, recallHits: 'none', scratchDir: '/scratch', pluginRoot: '/plugin', vaultRoot: '/vault/AI' }
const GIT_RULE = 'In /repo, git is read-only: git status, git diff, git log, git ls-files, git branch --show-current, git remote get-url, git symbolic-ref with one ref argument, and git merge-base --is-ancestor only. A -c core.quotePath=false prefix on one of these commands keeps it read-only. Never run git stash, add, commit, checkout, switch, reset, clean, rebase, merge or push there. Mutating git is allowed only inside a fresh fixture you create under /scratch.'
const SCRATCH_ONLY = 'Run embedded commands only against scratch fixtures you create under /scratch, never against /repo.'
const STDIN_RULE = 'Run any verify or test suite, such as bash verify.sh, with stdin from /dev/null (bash verify.sh </dev/null), because a suite that reads stdin hangs when stdin is a pipe.'
const REPO_STATE = "The tree at repoRoot is the POST-change state this diff produces. There is no pre-change checkout. Reconstruct the pre-change state from the diff's context and removed lines. A defect the diff introduces is in scope even though it is present in the tree."
const PANEL = ['toolkit:code-reviewer', 'toolkit:silent-failure-hunter', 'toolkit:pr-test-analyzer']

const stepOf = (changedPaths, extra = {}) => ({ changedPaths, deviations: [], checksRun: ['unit tests'], result: 'Done.', blockers: [], topicMaterial: 'none', ...extra })
const resultOf = (status) => ({ step: '1. Run the unit tests.', status, evidence: `unit tests: ${status}` })
const validationOf = (status) => ({ results: [resultOf(status), { step: '2. Export one widget by hand.', status: 'pass', evidence: 'one row exported' }] })
const PASS = validationOf('pass')
const FAIL = validationOf('fail')
const diffOf = (hash12, empty = false, paths = ['src/a.js']) => ({ diffPath: `/scratch/slice-${hash12}.diff`, hash12, empty, paths })
const finding = (file, title) => ({ title, file, dimension: 'code-reviewer', severity: 'high', detail: 'Evidence at the line.', failure_scenario: 'A null widget throws.', verdict: { isReal: true, confidence: 'confirmed', reasoning: 'Reproduced.' } })
const F1 = finding('src/a.js', 'Null widget crashes the export')
const F2 = finding('src/b.js', 'Route skips the auth check')
const F3 = finding('src/c.js', 'Null widget crashes the export')
const reviewOf = (confirmed) => ({ confirmed, refuted: [], unverified: [], openQuestions: [], dead: [], ran: [...PANEL, 'cold-read', 'external-reviewer'] })
const resolvedOf = (...fs) => ({ results: fs.map((f) => ({ file: f.file, title: f.title, resolved: true, evidence: 'Guard added.' })) })
const docPassOf = (extra = {}) => ({ docsUpdated: [], deferred: [], distributed: [], changedPaths: [], blockers: [], topicMaterial: 'none', ...extra })
const coldOf = (...verified) => ({ findings: verified.map((v, i) => ({ file: 'src/a.js', issue: `issue ${i}`, fix: 'Rename it.', verified: v })) })

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
const AGENT_TYPES = { 'cold:read': 'toolkit:code-reviewer', 'diff:final': V, 'diff:post-doc': V, 'diff:red-team': V, 'doc:pass': I, 'fix:1': I, 'fix:validation': I, 'implement:1': I, 'implement:2': I, 'implement:3': I, 'prep:baseline': V, 'recheck:1': V, 'remember:pass': I, 'verify:final': V, 'verify:revalidation': V, 'verify:validation': V }
const PHASES = { 'cold:read': 'Cold read', 'diff:final': 'Cold read', 'diff:post-doc': 'Doc pass', 'diff:red-team': 'Red team', 'doc:pass': 'Doc pass', 'fix:1': 'Fix', 'fix:validation': 'Verify', 'implement:1': 'Implement', 'implement:2': 'Implement', 'implement:3': 'Implement', 'prep:baseline': 'Prep', 'recheck:1': 'Fix', 'remember:pass': 'Remember', 'verify:final': 'Doc pass', 'verify:revalidation': 'Verify', 'verify:validation': 'Verify' }
const RETURN_KEYS = ['baseline', 'steps', 'validation', 'review', 'coldResidual', 'coldUnverified', 'docPass', 'remember', 'changedPaths', 'planChanges', 'diffHashes', 'diffPaths', 'diffFiles', 'blocked', 'incomplete']
const REVIEW_KEYS = ['panel', 'dimensions', 'confirmed', 'fixed', 'open', 'refuted', 'unverified', 'openQuestions', 'dead', 'rounds']

// Runs the flow with per-label overrides. A null override is a dead stage, an Error makes the child workflow throw.
async function run(overrides = {}, args = ARGS) {
  const script = { ...DEFAULTS, ...overrides }
  const prompts = {}
  const agents = {}
  const calls = []
  const agent = async (prompt, opts) => {
    prompts[opts.label] = prompt
    agents[opts.label] = { agentType: opts.agentType, phase: opts.phase, schema: opts.schema }
    return script[opts.label] ?? null
  }
  const workflow = async (ref, wfArgs) => {
    calls.push({ ref, args: wfArgs })
    const v = script['workflow:review-mr']
    if (v instanceof Error) throw v
    return v ?? null
  }
  try {
    const result = await flow(args, agent, workflow, () => {}, () => {})
    return { result, prompts, agents, calls }
  } catch (error) {
    return { error, prompts, agents, calls }
  }
}

const same = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected)
const implementLabels = (prompts) => Object.keys(prompts).filter((k) => k.startsWith('implement:'))
const stepText = (prompts, n) => prompts[`implement:${n}`].split('YOUR STEP:\n')[1].split('\n\nALREADY CHANGED:')[0]
const byLabel = (agents, field) => Object.fromEntries(Object.keys(agents).sort().map((k) => [k, agents[k][field]]))
const labelsWhere = (prompts, test) => Object.keys(prompts).filter((k) => test(prompts[k])).sort()

const cases = [
  ['missing arg key throws', async () => {
    const { error } = await run({}, { ...ARGS, vaultRoot: undefined })
    return String(error && error.message).includes('execute-runner requires args')
  }],
  ['plan with no Implementation Steps throws', async () => {
    const { error } = await run({}, { ...ARGS, planContent: plan([]) })
    return String(error && error.message).includes('the plan has no Implementation Steps')
  }],
  ['maxFixRounds as the string "1" throws', async () => {
    const { error } = await run({}, { ...ARGS, maxFixRounds: '1' })
    return String(error && error.message).includes('maxFixRounds must be a non-negative integer')
  }],
  ['plan with no Validation Steps blocks and still runs implement:1', async () => {
    const { result, prompts } = await run({}, { ...ARGS, planContent: plan(THREE_STEPS, null) })
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
  ['one of two findings resolved at maxFixRounds 1 reports the exhausted sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1, F2]), 'recheck:1': resolvedOf(F1) })
    return same(result.blocked, ['Fix rounds are exhausted at maxFixRounds 1 with 1 confirmed findings open.'])
  }],
  ['maxFixRounds 0 runs no fix:1 and blocks', async () => {
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1]) }, { ...ARGS, maxFixRounds: 0 })
    return same({ fix: 'fix:1' in prompts, blocked: result.blocked }, { fix: false, blocked: ['Fix rounds are exhausted at maxFixRounds 0 with 1 confirmed findings open.'] })
  }],
  ['dead fix:1 blocks without the exhausted sentence', async () => {
    const { result } = await run({ 'workflow:review-mr': reviewOf([F1]), 'fix:1': null })
    return same(result.blocked, ['The implementer fix:1 returned nothing.'])
  }],
  ['dead recheck:1 blocks without the exhausted sentence', async () => {
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
  ['verified cold finding lands in coldResidual and blocks', async () => {
    const { result } = await run({ 'cold:read': coldOf(true, false) })
    return same({ residual: result.coldResidual.length, blocked: result.blocked }, { residual: 1, blocked: ['The cold read left 1 verified findings open.'] })
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
    const { result, prompts } = await run({ 'cold:read': coldOf(true) })
    return same({ called: 'remember:pass' in prompts, remember: result.remember }, { called: false, remember: { ran: false, material: ['The exporter streams rows (src/a.js:4).'], proposals: [], topicsUpdated: [], rememberLine: '' } })
  }],
  ['FENCED_PLAN yields three steps despite a fenced Validation Steps heading', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: FENCED_PLAN })
    return same(implementLabels(prompts), ['implement:1', 'implement:2', 'implement:3'])
  }],
  ['HEADED_PLAN yields three steps despite a numbered sublist in step 2', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: HEADED_PLAN })
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
    return same({ diffPath: c.diffPath, repoRoot: c.repoRoot, rules: c.contextBlock.includes(SCRATCH_ONLY) && c.contextBlock.includes(GIT_RULE), repoState: c.repoState, keys: c.dimensions.map((d) => d.key), reviewers: c.registryReviewers }, { diffPath: '/scratch/slice-aaaaaaaaaaaa.diff', repoRoot: '/repo', rules: true, repoState: REPO_STATE, keys: ['cold-read', 'external-reviewer'], reviewers: PANEL })
  }],
  ['the scratch-only rule reaches cold:read and both cold dimensions, no other agent prompt', async () => {
    const { prompts, calls } = await run(FULL_RUN)
    return same({ labels: labelsWhere(prompts, (p) => p.includes(SCRATCH_ONLY)), dims: calls[0].args.dimensions.every((d) => d.prompt.includes(SCRATCH_ONLY)) }, { labels: ['cold:read'], dims: true })
  }],
  ['every agent prompt but remember:pass carries the git rule', async () => {
    const { prompts } = await run(FULL_RUN)
    return same(labelsWhere(prompts, (p) => !p.includes(GIT_RULE)), ['remember:pass'])
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
    const { prompts } = await run()
    return prompts['remember:pass'].includes('RELATED TOPICS:\n- [[Widgets]]')
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
    const { prompts } = await run({}, { ...ARGS, planContent: TILDE_PLAN })
    return same({ labels: implementLabels(prompts), validation: prompts['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], validation: false })
  }],
  ['four-backtick fence wrapping a three-backtick block keeps its Validation Steps line in step 2', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: NESTED_PLAN })
    return same({ labels: implementLabels(prompts), step2: stepText(prompts, 2).includes('## Validation Steps'), validation: prompts['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], step2: true, validation: false })
  }],
  ['unnumbered ### subheadings stay inside numbered steps', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: REFERENCE_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(prompts, 1).includes('### Directory layout') && stepText(prompts, 1).includes('### Reference') }, { labels: ['implement:1', 'implement:2', 'implement:3'], step1: true })
  }],
  ['prose-only Implementation Steps run as one step holding the whole text', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: PROSE_PLAN })
    return same({ labels: implementLabels(prompts), step: stepText(prompts, 1) }, { labels: ['implement:1'], step: 'Add the exporter in src/a.js and wire the route.\n\nThen document it.' })
  }],
  ['paren markers split the steps', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: PAREN_PLAN })
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
    const { result, prompts } = await run({ 'workflow:review-mr': reviewOf([F1]), 'recheck:1': resolvedOf(F1), 'cold:read': coldOf(true) })
    return same({ ran: ['doc:pass', 'verify:final', 'diff:post-doc'].filter((k) => k in prompts), docPass: result.docPass, blocked: result.blocked }, { ran: [], docPass: null, blocked: ['The cold read left 1 verified findings open.'] })
  }],
  ['clean run still runs doc:pass and diff:post-doc', async () => {
    const { result, prompts } = await run()
    return same({ ran: ['doc:pass', 'diff:post-doc'].filter((k) => k in prompts), docPass: result.docPass !== null }, { ran: ['doc:pass', 'diff:post-doc'], docPass: true })
  }],
  ['count mismatch with a failing result blocks with both sentences and skips fix:validation', async () => {
    const { result, prompts } = await run({ 'verify:validation': FAIL }, { ...ARGS, planContent: plan(THREE_STEPS, [...VALIDATION_LINES, '3. Check the log.']) })
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
    const { prompts } = await run({}, { ...ARGS, planContent: INFO_FENCE_PLAN })
    return same({ labels: implementLabels(prompts), validation: prompts['verify:validation'].includes('Not a step') }, { labels: ['implement:1', 'implement:2', 'implement:3'], validation: false })
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
    const { result, prompts } = await run({ 'verify:validation': { results: [resultOf('pass')] } }, { ...ARGS, planContent: plan(THREE_STEPS, ['- Run the unit tests.', '- Export one widget by hand.', '', 'Tripwires:', '- The export writes no rows.']) })
    const p = prompts['verify:validation']
    return same({ blocked: result.blocked, step1: p.includes('STEP 1:\n- Run the unit tests.'), step2: p.includes('STEP 2:'), count: p.includes('Return exactly 1 results') }, { blocked: [], step1: true, step2: false, count: true })
  }],
  ['a numbered Validation Steps section renders one STEP per item and asks for that many results', async () => {
    const { prompts } = await run()
    const p = prompts['verify:validation']
    return same({ steps: p.includes('STEP 1:\n1. Run the unit tests.\n\nSTEP 2:\n2. Export one widget by hand.'), count: p.includes('Return exactly 2 results, one per STEP, in order') }, { steps: true, count: true })
  }],
  ['a review-mr return without dead blocks', async () => {
    const { result } = await run({ 'workflow:review-mr': { confirmed: [], refuted: [], unverified: [], openQuestions: [] } })
    return same({ blocked: result.blocked, dead: result.review.dead }, { blocked: ['The review panel did not report which reviewers ran.'], dead: [] })
  }],
  ['text before ### 1. joins step 1', async () => {
    const { prompts } = await run({}, { ...ARGS, planContent: PREAMBLE_PLAN })
    return same({ labels: implementLabels(prompts), step1: stepText(prompts, 1) }, { labels: ['implement:1', 'implement:2'], step1: 'Read the exporter notes first.\n\n### 1. Add the exporter\nWrite src/a.js.' })
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
