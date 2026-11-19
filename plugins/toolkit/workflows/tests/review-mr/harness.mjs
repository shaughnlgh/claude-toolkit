// The script body uses top-level await and return, so it compiles inside an AsyncFunction.
import { readFileSync } from 'node:fs'

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const source = readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const flow = new AsyncFunction('args', 'agent', 'pipeline', 'phase', 'log', source)

const ARGS = { diffPath: '/scratch/x.diff', repoRoot: '/repo', contextBlock: 'CTX\nREVIEW RULES: nit cap five' }
const SIX = ['toolkit:code-reviewer', 'toolkit:security-reviewer', 'toolkit:silent-failure-hunter', 'toolkit:performance-reviewer', 'toolkit:pr-test-analyzer', 'toolkit:coupling-reviewer']
const KEYS = SIX.map((n) => n.split(':').pop())
const RETURN_KEYS = ['confirmed', 'nits', 'preExisting', 'refuted', 'unverified', 'dropped', 'openQuestions', 'dead', 'verifierDead', 'panel', 'dimensions']
const VERDICT_REQUIRED = ['index', 'finalTag', 'finalScore', 'verdict', 'reproduction', 'reasoning']
const REPRO = 'node fixture.js printed TypeError at a.js:4'

const finding = (file, title, extra = {}) => ({ title, file, line: 4, tag: 'important', impact: 0.8, likelihood: 0.6, confidence: 0.5, citation: 'src/a.js:4', detail: 'Evidence at the line.', failure_scenario: 'A null widget throws.', ...extra })
const verdict = (index, finalScore, extra = {}) => ({ index, finalTag: 'important', finalScore, verdict: 'real', reproduction: REPRO, reasoning: 'Reproduced.', ...extra })
const verdictsOf = (...verdicts) => ({ verdicts })
const findingsOf = (...findings) => ({ findings })
const titled = (n) => Array.from({ length: n }, (_, i) => finding('src/a.js', `F${i}`))
const DEFAULTS = Object.fromEntries(KEYS.map((k) => [`review:${k}`, findingsOf()]))

// Runs the flow with per-label overrides. A missing or null label is a dead agent, an Error makes the agent throw.
async function run(overrides = {}, args = ARGS) {
  const script = { ...DEFAULTS, ...overrides }
  const prompts = {}
  const agents = {}
  const agent = async (prompt, opts) => {
    prompts[opts.label] = prompt
    agents[opts.label] = { agentType: opts.agentType, phase: opts.phase, schema: opts.schema, model: opts.model, effort: opts.effort }
    const v = script[opts.label]
    if (v instanceof Error) throw v
    return v ?? null
  }
  // Unlike the plan-builder stub, the second stage receives the item, as the runtime passes it.
  const pipeline = async (items, first, second) => {
    const out = []
    for (const item of items) {
      try { out.push(await second(await first(item), item)) } catch (e) { out.push(null) }
    }
    return out
  }
  try {
    const result = await flow(args, agent, pipeline, () => {}, () => {})
    return { result, prompts, agents }
  } catch (error) {
    return { error, prompts, agents }
  }
}

// One code-reviewer dimension with the given findings and verifier return.
const route = (findings, verifier) => run({ 'review:code-reviewer': findingsOf(...findings), 'verify:code-reviewer': verifier })
const same = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected)
const flat = (s) => String(s).replace(/\s+/g, ' ')
const titles = (list) => list.map((f) => f.title)
const pick = (f, fields) => Object.fromEntries(fields.map((k) => [k, f[k]]))
const verifyLabels = (prompts) => Object.keys(prompts).filter((k) => k.startsWith('verify:')).sort()
const listed = (prompt) => prompt.split('FINDINGS:\n')[1].split('\n').filter((l) => /^\d+\. \[/.test(l))
const ONE_EACH = Object.fromEntries(KEYS.flatMap((k) => [[`review:${k}`, findingsOf(finding('src/a.js', `F-${k}`))], [`verify:${k}`, verdictsOf(verdict(0, 0.7))]]))

const cases = [
  ['missing contextBlock throws the args sentence', async () => {
    const { error } = await run({}, { ...ARGS, contextBlock: undefined })
    return String(error && error.message).includes('review-mr requires args: {diffPath, repoRoot, contextBlock')
  }],
  ['default run spawns the six registry review labels', async () => {
    const { prompts } = await run(ONE_EACH)
    return same(Object.keys(prompts).filter((k) => k.startsWith('review:')).sort(), KEYS.map((k) => `review:${k}`).sort())
  }],
  ['default run spawns one verify label per dimension', async () => {
    const { prompts } = await run(ONE_EACH)
    return same(verifyLabels(prompts), KEYS.map((k) => `verify:${k}`).sort())
  }],
  ['every verifier is toolkit:verifier in the Verify phase with the map verifier model and effort', async () => {
    const { agents } = await run(ONE_EACH, { ...ARGS, models: { verifier: { model: 'opus', effort: 'xhigh' } } })
    return verifyLabels(agents).every((k) => same(pick(agents[k], ['agentType', 'model', 'effort', 'phase']), { agentType: 'toolkit:verifier', model: 'opus', effort: 'xhigh', phase: 'Verify' }))
  }],
  ['a reviewer takes its own map entry and a custom dimension takes the code-reviewer entry', async () => {
    const { agents } = await run({}, { ...ARGS, models: { 'code-reviewer': { model: 'sonnet', effort: 'medium' }, 'security-reviewer': { model: 'opus', effort: 'high' } }, dimensions: [{ key: 'conventions', prompt: 'Check conventions.' }] })
    return same({ reviewer: pick(agents['review:security-reviewer'], ['model', 'effort']), custom: pick(agents['review:conventions'], ['model', 'effort']) }, { reviewer: { model: 'opus', effort: 'high' }, custom: { model: 'sonnet', effort: 'medium' } })
  }],
  ['a cold dimension takes the code-reviewer entry', async () => {
    const { agents } = await run({}, { ...ARGS, models: { 'code-reviewer': { model: 'sonnet', effort: 'medium' } }, dimensions: [{ key: 'cold-read', prompt: 'Read cold.', cold: true }] })
    return same(pick(agents['review:cold-read'], ['model', 'effort']), { model: 'sonnet', effort: 'medium' })
  }],
  ['a missing models map passes neither key to any call', async () => {
    const { agents } = await run(ONE_EACH)
    return Object.values(agents).every((x) => x.model === undefined && x.effort === undefined)
  }],
  ['a non-object models arg throws the models sentence', async () => {
    const { error } = await run({}, { ...ARGS, models: 'opus' })
    return String(error && error.message).includes('review-mr models must map agent names to {model, effort} objects')
  }],
  ['a models map wrapped in agents throws', async () => {
    const { error } = await run({}, { ...ARGS, models: { agents: { verifier: { model: 'opus', effort: 'xhigh' } } } })
    return String(error && error.message).includes('review-mr models must map agent names to {model, effort} objects')
  }],
  ['a models map with a bare string entry throws', async () => {
    const { error } = await run({}, { ...ARGS, models: { verifier: 'opus' } })
    return String(error && error.message).includes('review-mr models must map agent names to {model, effort} objects')
  }],
  ['verifier schema requires the reproduction string and carries no reproduced boolean', async () => {
    const { agents } = await run(ONE_EACH)
    const items = agents['verify:code-reviewer'].schema.properties.verdicts.items
    return same({ required: items.required, reproduced: items.properties.reproduced }, { required: VERDICT_REQUIRED, reproduced: undefined })
  }],
  ['finding without citation lands in dropped with reason no citation', async () => {
    const { result } = await route([finding('src/a.js', 'Kept'), finding('src/b.js', 'Uncited', { citation: '' })], verdictsOf(verdict(0, 0.7)))
    return same(result.dropped.map((f) => pick(f, ['title', 'reason'])), [{ title: 'Uncited', reason: 'no citation' }])
  }],
  ['finding without citation never appears in the verifier prompt', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept'), finding('src/b.js', 'Uncited', { citation: '  ' })], verdictsOf(verdict(0, 0.7)))
    return !prompts['verify:code-reviewer'].includes('Uncited')
  }],
  ['dimension whose only finding lacks a citation spawns no verifier', async () => {
    const { prompts } = await route([finding('src/b.js', 'Uncited', { citation: undefined })], verdictsOf())
    return same(verifyLabels(prompts), [])
  }],
  ['score is 0.68 for the default fixture', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.7)))
    return result.confirmed[0].score === 0.68
  }],
  ['score is 1 when impact, likelihood and confidence are 1', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { impact: 1, likelihood: 1, confidence: 1 })], verdictsOf(verdict(0, 0.7)))
    return result.confirmed[0].score === 1
  }],
  ['verifier prompt lists each kept finding by index, tag, score, file:line and title', async () => {
    const { prompts } = await route([finding('src/a.js', 'First'), finding('src/b.js', 'Second', { tag: 'nit', line: 9 })], verdictsOf())
    return same(listed(prompts['verify:code-reviewer']), ['0. [important] score 0.68 src/a.js:4 First', '1. [nit] score 0.68 src/b.js:9 Second'])
  }],
  ['verifier prompt carries the contextBlock', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return prompts['verify:code-reviewer'].startsWith(ARGS.contextBlock)
  }],
  ['verifier prompt carries the 0.6 reproduce sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('For a finding with score 0.6 or above, reproduce it against the code, then confirm or refute it.')
  }],
  ['verifier prompt carries the raise-then-reproduce sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('if the reviewer undersold a real defect raise finalScore, and if you raise it to 0.6 or above reproduce it first.')
  }],
  ['verifier prompt carries the reproduction definition', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('reproduction holds the command or trace you ran and the output you observed, verbatim, and is empty when you ran nothing. A finding with an empty reproduction never counts as reproduced')
  }],
  ['verifier prompt carries the never-modify-repoRoot sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('Never modify any file under /repo.')
  }],
  ['verifier prompt carries the pre-existing retag rule', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes("Confirm pre-existing only when the diff's removed lines or its context lines already carry the defect and the diff does not make it worse, otherwise retag it important.")
  }],
  ['verifier prompt carries the doc-finding sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('A doc finding is one whose file is under a docs/ directory or ends in .md. Its bar is 0: reproduce it at every score')
  }],
  ['verifier prompt says plan grounds are not refutations and a plan line is never the line', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    const p = flat(prompts['verify:code-reviewer'])
    return p.includes('are not refutations') && p.includes('is never that line')
  }],
  ['verifier prompt carries the rules and doctrine sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('A finding that cites a file under rules/, doctrine/, CLAUDE.md, AGENTS.md or .claude/rules is a rule breach: lower its finalScore only when the cited rule does not say what the finding claims, never on plan or design grounds.')
  }],
  ['verifier prompt quotes the plan-ground phrases it rejects as refutations', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('"The plan decided it", "settled at approval", "the owner accepted this", and a subjective preference are not refutations.')
  }],
  ['verifier prompt carries the below-threshold reproduction sentence', async () => {
    const { prompts } = await route([finding('src/a.js', 'Kept')], verdictsOf())
    return flat(prompts['verify:code-reviewer']).includes('reproduction is the cited line as you read it and what it shows')
  }],
  ['registry reviewer prompt carries the contextBlock', async () => {
    const { prompts } = await run()
    return prompts['review:code-reviewer'].includes(ARGS.contextBlock)
  }],
  ['cold custom dimension prompt omits the contextBlock', async () => {
    const { prompts } = await run({}, { ...ARGS, dimensions: [{ key: 'cold-read', prompt: 'Read cold.', cold: true }] })
    return !prompts['review:cold-read'].includes(ARGS.contextBlock)
  }],
  ['non-cold custom dimension prompt carries the contextBlock', async () => {
    const { prompts } = await run({}, { ...ARGS, dimensions: [{ key: 'conventions', prompt: 'Check conventions.' }] })
    return prompts['review:conventions'].includes(ARGS.contextBlock)
  }],
  ['every reviewer prompt, registry and cold custom, carries A scorer follows', async () => {
    const { prompts } = await run({}, { ...ARGS, dimensions: [{ key: 'cold-read', prompt: 'Read cold.', cold: true }] })
    const keys = Object.keys(prompts).filter((k) => k.startsWith('review:'))
    return keys.includes('review:cold-read') && keys.includes('review:code-reviewer') && keys.every((k) => prompts[k].includes('A scorer follows'))
  }],
  ['real important at finalScore 0.6 with a reproduction is confirmed and reproduced', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.6)))
    return same(result.confirmed.map((f) => pick(f, ['title', 'finalScore', 'reproduced', 'reproduction'])), [{ title: 'Kept', finalScore: 0.6, reproduced: true, reproduction: REPRO }])
  }],
  ['real important at finalScore 0.59 with a reproduction is confirmed', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.59)))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: ['Kept'], nits: [] })
  }],
  ['real important at finalScore 0.59 with an empty reproduction routes to nits', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.59, { reproduction: '' })))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: [], nits: ['Kept'] })
  }],
  ['real nit at finalScore 0.4 with a reproduction is confirmed', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { tag: 'nit' })], verdictsOf(verdict(0, 0.4, { finalTag: 'nit' })))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: ['Kept'], nits: [] })
  }],
  ['doc findings at finalScore 0.4 with empty reproductions are unverified as not reproduced', async () => {
    const { result } = await route([finding('docs/guide.md', 'Guide'), finding('plugins/toolkit/skills/x/SKILL.md', 'Skill')], verdictsOf(verdict(0, 0.4, { reproduction: '' }), verdict(1, 0.4, { reproduction: '' })))
    return same({ nits: titles(result.nits), unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])) }, { nits: [], unverified: [{ title: 'Guide', reason: 'not reproduced' }, { title: 'Skill', reason: 'not reproduced' }] })
  }],
  ['code file under docs/ at finalScore 0.4 with an empty reproduction is unverified as not reproduced', async () => {
    const { result } = await route([finding('docs/examples/run.js', 'Example')], verdictsOf(verdict(0, 0.4, { reproduction: '' })))
    return same({ nits: titles(result.nits), unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])) }, { nits: [], unverified: [{ title: 'Example', reason: 'not reproduced' }] })
  }],
  ['doc finding at finalScore 0.4 with a reproduction is confirmed', async () => {
    const { result } = await route([finding('docs/guide.md', 'Guide')], verdictsOf(verdict(0, 0.4)))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: ['Guide'], nits: [] })
  }],
  ['real nit promoted to finalScore 0.7 with a reproduction is confirmed', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { tag: 'nit' })], verdictsOf(verdict(0, 0.7, { finalTag: 'nit' })))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: ['Kept'], nits: [] })
  }],
  ['real nit at finalScore 0.4 routes to nits', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { tag: 'nit' })], verdictsOf(verdict(0, 0.4, { finalTag: 'nit', reproduction: '' })))
    return same({ confirmed: titles(result.confirmed), nits: titles(result.nits) }, { confirmed: [], nits: ['Kept'] })
  }],
  ['real pre-existing routes to preExisting whatever the finalScore', async () => {
    const { result } = await route([finding('src/a.js', 'High'), finding('src/b.js', 'Low')], verdictsOf(verdict(0, 0.9, { finalTag: 'pre-existing' }), verdict(1, 0.2, { finalTag: 'pre-existing' })))
    return same({ preExisting: titles(result.preExisting), confirmed: titles(result.confirmed), nits: titles(result.nits) }, { preExisting: ['High', 'Low'], confirmed: [], nits: [] })
  }],
  ['reviewer pre-existing overturned to important at 0.8 is confirmed', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { tag: 'pre-existing' })], verdictsOf(verdict(0, 0.8)))
    return same({ confirmed: result.confirmed.map((f) => pick(f, ['tag', 'finalTag'])), preExisting: titles(result.preExisting) }, { confirmed: [{ tag: 'pre-existing', finalTag: 'important' }], preExisting: [] })
  }],
  ['real at 0.7 with an empty reproduction is unverified as not reproduced', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.7, { reproduction: '' })))
    return same({ confirmed: titles(result.confirmed), unverified: result.unverified.map((f) => pick(f, ['title', 'reason', 'reproduced'])) }, { confirmed: [], unverified: [{ title: 'Kept', reason: 'not reproduced', reproduced: false }] })
  }],
  ['real at 0.7 with a whitespace-only reproduction is unverified as not reproduced', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.7, { reproduction: ' \n\t ' })))
    return same({ confirmed: titles(result.confirmed), unverified: result.unverified.map((f) => pick(f, ['title', 'reason', 'reproduced'])) }, { confirmed: [], unverified: [{ title: 'Kept', reason: 'not reproduced', reproduced: false }] })
  }],
  ['self-score 0.3 raised to 0.7 with a reproduction is confirmed', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { impact: 0.3, likelihood: 0.3, confidence: 0.3 })], verdictsOf(verdict(0, 0.7)))
    return same(result.confirmed.map((f) => pick(f, ['title', 'score', 'finalScore'])), [{ title: 'Kept', score: 0.3, finalScore: 0.7 }])
  }],
  ['self-score 0.3 raised to 0.7 with an empty reproduction is unverified as not reproduced', async () => {
    const { result } = await route([finding('src/a.js', 'Kept', { impact: 0.3, likelihood: 0.3, confidence: 0.3 })], verdictsOf(verdict(0, 0.7, { reproduction: '' })))
    return same({ confirmed: titles(result.confirmed), unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])) }, { confirmed: [], unverified: [{ title: 'Kept', reason: 'not reproduced' }] })
  }],
  ['refuted verdict routes to refuted with score, finalScore, finalTag and reason', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.2, { verdict: 'refuted', finalTag: 'nit', reasoning: 'Guarded at a.js:2.' })))
    return same(result.refuted.map((f) => pick(f, ['title', 'score', 'finalScore', 'finalTag', 'reason'])), [{ title: 'Kept', score: 0.68, finalScore: 0.2, finalTag: 'nit', reason: 'Guarded at a.js:2.' }])
  }],
  ['doc finding refuted with an empty reproduction is unverified as not reproduced with the verifier reasoning', async () => {
    const { result } = await route([finding('docs/guide.md', 'Guide')], verdictsOf(verdict(0, 0.2, { verdict: 'refuted', reproduction: '', reasoning: 'Settled at approval.' })))
    return same({ refuted: result.refuted, unverified: result.unverified.map((f) => pick(f, ['title', 'reason', 'verdict', 'reasoning'])) }, { refuted: [], unverified: [{ title: 'Guide', reason: 'not reproduced', verdict: 'refuted', reasoning: 'Settled at approval.' }] })
  }],
  ['code finding refuted with an empty reproduction stays in refuted', async () => {
    const { result } = await route([finding('src/a.js', 'Kept')], verdictsOf(verdict(0, 0.2, { verdict: 'refuted', reproduction: '', reasoning: 'Guarded at a.js:2.' })))
    return same({ refuted: titles(result.refuted), unverified: titles(result.unverified) }, { refuted: ['Kept'], unverified: [] })
  }],
  ['doc finding refuted with a quoted line stays in refuted and carries the reproduction', async () => {
    const quoted = 'guide.md:4 reads: the loader parses the file'
    const { result } = await route([finding('docs/guide.md', 'Guide')], verdictsOf(verdict(0, 0.2, { verdict: 'refuted', reproduction: quoted, reasoning: 'The doc matches the tree.' })))
    return same(result.refuted.map((f) => pick(f, ['title', 'reason', 'reproduction'])), [{ title: 'Guide', reason: 'The doc matches the tree.', reproduction: quoted }])
  }],
  ['finding the verifier omits is unverified with reason no verdict', async () => {
    const { result } = await route([finding('src/a.js', 'First'), finding('src/b.js', 'Second')], verdictsOf(verdict(0, 0.7)))
    return same({ confirmed: titles(result.confirmed), unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])) }, { confirmed: ['First'], unverified: [{ title: 'Second', reason: 'no verdict' }] })
  }],
  ['dead verifier sets verifierDead, routes its findings to unverified and leaves dead empty', async () => {
    const { result } = await route([finding('src/a.js', 'First'), finding('src/b.js', 'Second')], null)
    return same({ verifierDead: result.verifierDead, unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])), dead: result.dead }, { verifierDead: ['toolkit:code-reviewer'], unverified: [{ title: 'First', reason: 'verifier died' }, { title: 'Second', reason: 'verifier died' }], dead: [] })
  }],
  ['nine kept findings split into a chunk of eight and a chunk of one', async () => {
    const { prompts } = await route(titled(9), verdictsOf())
    return same({ labels: verifyLabels(prompts), first: listed(prompts['verify:code-reviewer']).length, second: listed(prompts['verify:code-reviewer:2']) }, { labels: ['verify:code-reviewer', 'verify:code-reviewer:2'], first: 8, second: ['0. [important] score 0.68 src/a.js:4 F8'] })
  }],
  ['dead second chunk sets verifierDead once and still routes the first chunk', async () => {
    const first = verdictsOf(...Array.from({ length: 8 }, (_, i) => verdict(i, 0.7)))
    const { result } = await route(titled(9), first)
    return same({ verifierDead: result.verifierDead, confirmed: result.confirmed.length, unverified: result.unverified.map((f) => pick(f, ['title', 'reason'])) }, { verifierDead: ['toolkit:code-reviewer'], confirmed: 8, unverified: [{ title: 'F8', reason: 'verifier died' }] })
  }],
  ['a second-chunk verdict at index 0 routes to the ninth finding', async () => {
    const { result } = await run({ 'review:code-reviewer': findingsOf(...titled(9)), 'verify:code-reviewer': verdictsOf(), 'verify:code-reviewer:2': verdictsOf(verdict(0, 0.7)) })
    return same(titles(result.confirmed), ['F8'])
  }],
  ['seven nits keep the five highest in order and drop the two lowest under nit cap', async () => {
    const scores = [0.3, 0.55, 0.25, 0.45, 0.5, 0.35, 0.4]
    const { result } = await route(titled(7), verdictsOf(...scores.map((s, i) => verdict(i, s, { finalTag: 'nit', reproduction: '' }))))
    return same({ nits: result.nits.map((f) => f.finalScore), dropped: result.dropped.map((f) => pick(f, ['finalScore', 'reason'])) }, { nits: [0.55, 0.5, 0.45, 0.4, 0.35], dropped: [{ finalScore: 0.3, reason: 'nit cap' }, { finalScore: 0.25, reason: 'nit cap' }] })
  }],
  ['seven unreproduced code nits and two unreproduced doc findings keep five nits, drop two and send the docs to unverified', async () => {
    const scores = [0.3, 0.55, 0.25, 0.45, 0.5, 0.35, 0.4]
    const docs = [finding('docs/guide.md', 'D0'), finding('README.md', 'D1')]
    const unreproduced = (i, s) => verdict(i, s, { finalTag: 'nit', reproduction: '' })
    const { result } = await run({ 'review:code-reviewer': findingsOf(...titled(7), ...docs), 'verify:code-reviewer': verdictsOf(...scores.concat([0.4]).map((s, i) => unreproduced(i, s))), 'verify:code-reviewer:2': verdictsOf(unreproduced(0, 0.4)) })
    return same({ nits: result.nits.length, dropped: result.dropped.map((f) => f.reason), unverified: titles(result.unverified) }, { nits: 5, dropped: ['nit cap', 'nit cap'], unverified: ['D0', 'D1'] })
  }],
  ['dead registry reviewer appears in dead by agentType', async () => {
    const { result } = await run({ 'review:security-reviewer': null })
    return same(result.dead, ['toolkit:security-reviewer'])
  }],
  ['dead custom dimension appears in dead by key', async () => {
    const { result } = await run({}, { ...ARGS, dimensions: [{ key: 'cold-read', prompt: 'Read cold.', cold: true }] })
    return same(result.dead, ['cold-read'])
  }],
  ['throwing reviewer appears in dead', async () => {
    const { result } = await run({ 'review:code-reviewer': new Error('boom') })
    return same(result.dead, ['toolkit:code-reviewer'])
  }],
  ['panel equals the registryReviewers passed in', async () => {
    const panel = ['toolkit:code-reviewer', 'toolkit:pr-test-analyzer']
    const { result } = await run({}, { ...ARGS, registryReviewers: panel })
    return same(result.panel, panel)
  }],
  ['panel defaults to the six registry reviewers', async () => {
    const { result } = await run()
    return same(result.panel, SIX)
  }],
  ['dimensions equals the custom dimension keys', async () => {
    const dims = [{ key: 'cold-read', prompt: 'Read cold.', cold: true }, { key: 'external-reviewer', prompt: 'Run it.', cold: true }]
    const { result } = await run({ 'review:cold-read': findingsOf(), 'review:external-reviewer': findingsOf() }, { ...ARGS, dimensions: dims })
    return same(result.dimensions, ['cold-read', 'external-reviewer'])
  }],
  ['open_questions pass through with their dimension', async () => {
    const { result } = await run({ 'review:code-reviewer': { findings: [], open_questions: ['Is the export admin-only?'] } })
    return same(result.openQuestions, [{ dimension: 'code-reviewer', question: 'Is the export admin-only?' }])
  }],
  ['return keys are exactly the eleven result keys', async () => {
    const { result } = await run(ONE_EACH)
    return same(Object.keys(result), RETURN_KEYS)
  }],
  ['JSON string args are parsed', async () => {
    const { result } = await run({}, JSON.stringify(ARGS))
    return same(Object.keys(result), RETURN_KEYS)
  }],
  ['a replayed label makes no agent call', async () => {
    const { prompts } = await run({}, { ...ARGS, replay: { 'review:code-reviewer': [findingsOf()] } })
    return same(Object.keys(prompts).filter((k) => k.startsWith('review:')).sort(), KEYS.filter((k) => k !== 'code-reviewer').map((k) => `review:${k}`).sort())
  }],
  ['a replay returns the count of recorded results it used', async () => {
    const { result } = await run({}, { ...ARGS, replay: { 'review:code-reviewer': [findingsOf()], 'review:not-run': [findingsOf()] } })
    return result.replayed === 1
  }],
  ['a replay of a review and its verify issues neither prompt', async () => {
    const replay = { 'review:code-reviewer': [findingsOf(finding('src/a.js', 'Kept'))], 'verify:code-reviewer': [verdictsOf(verdict(0, 0.7))] }
    const { result, prompts } = await run({}, { ...ARGS, replay })
    return same({ asked: ['review:code-reviewer', 'verify:code-reviewer'].filter((k) => k in prompts), replayed: result.replayed }, { asked: [], replayed: 2 })
  }],
  ['a replay arg that is not a label map throws', async () => {
    const { error } = await run({}, { ...ARGS, replay: ['review:code-reviewer'] })
    return String(error && error.message).includes('review-mr replay must map labels to lists of results when given')
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
