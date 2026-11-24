export const meta = {
  name: 'execute-runner',
  description: 'Execute flow: indexes an approved plan note by path through one verifier, so each worker reads its own lines after a sha256 and heading check, then runs it through a baseline check, one implementer per Implementation Step, the Validation Steps with one fix round, the review-mr panel chosen by changed path with one fix round over the confirmed findings, which takes the nits only under nits fix and runs for them alone in round 1 outside a seat run, a cold read told what the panel already reported and, when nothing blocked, the Doc Update Pass and the remember pass, and returns the result for the execute-flow skill to record. With fixBudget, the validation fix round and the panel rounds together start at most that many fix rounds live, and a replayed round costs nothing. The script writes no file itself: its verifiers write the diff captures under scratchDir and the remember worker writes vault notes. No worker runs mutating git in repoRoot. With seatRun, the script runs no Implementation Step, doc pass or remember pass, captures and reviews the diff from diffBase, and blocks on any captured path outside .claude/worktrees/ that no fix or earlier commit wrote.',
  phases: [
    { title: 'Prep', detail: 'a verifier indexes the plan note by path, with repos one implementer per top-level root writes and removes one file as the edit check, then a verifier records the branch, the tree status and the baseline verify result' },
    { title: 'Implement', detail: 'one implementer per Implementation Step, in order' },
    { title: 'Verify', detail: 'verifier runs the Validation Steps, one implementer fix round on a failure' },
    { title: 'Red team', detail: 'verifier captures the diff, the review-mr child runs the panel chosen by changed path and two cold dimensions' },
    { title: 'Fix', detail: 'one round over the confirmed findings, verifier rechecks, bounded by maxFixRounds and fixBudget. Under nits fix the nits ride round 1 and start it alone outside a seat run, and a seat run starts no round for nits alone' },
    { title: 'Cold read', detail: 'verifier recaptures the diff, one cold code-reviewer reads it' },
    { title: 'Doc pass', detail: 'implementer runs the Doc Update Pass, verifier revalidates and captures the post-doc diff' },
    { title: 'Remember', detail: 'implementer routes the durable facts, only when nothing blocked' },
    { title: 'Finish', detail: 'on a blocked run outside a seat run, a verifier captures the tree once as the blocked tree' },
  ],
}

// A continuation's recorded run, which scripts/run-checkpoint.py writes into a copy of the dead run's own script: its args, its plan:index return as index, and each runner and child label's returns in call order.
const REPLAY = null
let a = args
if (typeof a === 'string') {
  try { a = JSON.parse(a) } catch (e) { a = null }
}
// A continuation runs on the recorded args with the launch's own scratchDir, and the launch's fixBudget when it gives one.
if (REPLAY && a) a = { ...REPLAY.args, scratchDir: a.scratchDir, ...(a.fixBudget != null ? { fixBudget: a.fixBudget } : {}) }
const REQUIRED = ['planName', 'repoRoot', 'repoName', 'planPath', 'recallHits', 'scratchDir', 'pluginRoot', 'vaultRoot']
if (!a || REQUIRED.some((k) => typeof a[k] !== 'string' || !a[k])) {
  throw new Error('execute-runner requires args: {planName, repoRoot, repoName, planPath, recallHits, scratchDir, pluginRoot, vaultRoot, knownEvidence?, verifyCommand?, baselineFailing?, priorChangedPaths?, maxFixRounds?, fixBudget?, reviewRules?, reviewMr?, inWorktree?, models, e2e?, nits?, seatRun?, diffBase?, repos?}')
}
if (a.maxFixRounds != null && !(Number.isInteger(a.maxFixRounds) && a.maxFixRounds >= 0)) {
  throw new Error(`execute-runner maxFixRounds must be a non-negative integer, got ${JSON.stringify(a.maxFixRounds)}`)
}
if (a.fixBudget != null && !(Number.isInteger(a.fixBudget) && a.fixBudget >= 0)) {
  throw new Error(`execute-runner fixBudget must be a non-negative integer, got ${JSON.stringify(a.fixBudget)}`)
}
if (a.reviewRules != null && typeof a.reviewRules !== 'string') throw new Error('execute-runner reviewRules must be a string when given')
const isStrList = (v) => Array.isArray(v) && v.every((s) => typeof s === 'string')
if (a.baselineFailing != null && !isStrList(a.baselineFailing)) throw new Error(`execute-runner baselineFailing must be an array of strings when given, got ${JSON.stringify(a.baselineFailing)}`)
if (a.priorChangedPaths != null && !isStrList(a.priorChangedPaths)) throw new Error(`execute-runner priorChangedPaths must be an array of strings when given, got ${JSON.stringify(a.priorChangedPaths)}`)
if (a.inWorktree != null && typeof a.inWorktree !== 'boolean') throw new Error(`execute-runner inWorktree must be a boolean when given, got ${JSON.stringify(a.inWorktree)}`)
const isModelEntry = (v) => !!v && typeof v === 'object' && !Array.isArray(v) && Object.entries(v).every(([k, x]) => (k === 'model' || k === 'effort') && typeof x === 'string')
if (!a.models || typeof a.models !== 'object' || Array.isArray(a.models) || !Object.keys(a.models).length || !Object.values(a.models).every(isModelEntry)) throw new Error(`execute-runner requires models: the agents object scripts/resolve-models.sh prints. execute-runner models must map agent names to {model, effort} objects, got ${JSON.stringify(a.models)}`)
const SHA = /^[0-9a-f]{7,40}$/
if (a.e2e != null && a.e2e !== 'required' && a.e2e !== 'skip') throw new Error(`execute-runner e2e must be required or skip when given, got ${JSON.stringify(a.e2e)}`)
if (a.nits != null && a.nits !== 'fix' && a.nits !== 'skip') throw new Error(`execute-runner nits must be fix or skip when given, got ${JSON.stringify(a.nits)}`)
if (a.seatRun != null && typeof a.seatRun !== 'boolean') throw new Error(`execute-runner seatRun must be a boolean when given, got ${JSON.stringify(a.seatRun)}`)
if (a.seatRun && a.inWorktree) throw new Error('execute-runner seatRun and inWorktree cannot both be true')
if (a.seatRun && !a.baselineFailing) throw new Error('execute-runner seatRun requires baselineFailing, the failing names the worktree run recorded before the slice')
if (a.seatRun && !(typeof a.diffBase === 'string' && SHA.test(a.diffBase))) throw new Error(`execute-runner seatRun requires diffBase, the commit sha the seat run reviews from, got ${JSON.stringify(a.diffBase)}`)
if (a.diffBase != null && !a.seatRun) throw new Error('execute-runner diffBase is only valid with seatRun')
const REPO_NAME = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/
// A root is a normalized absolute path, so its prefix matches the one slice-capture.py derives.
const ROOT = /^(\/(?!\.\.?(\/|$))[^/'\n\r]+)+$/
const FILE = /^\/[^'\n\r]*$/
if (a.repos != null) {
  const rs = a.repos
  const bad = (why) => { throw new Error(`execute-runner repos ${why}, got ${JSON.stringify(rs)}`) }
  if (!Array.isArray(rs) || rs.length < 2) bad('must list at least two {name, root, rules?, hooks?} entries')
  for (const r of rs) {
    if (!r || typeof r !== 'object' || typeof r.name !== 'string' || !REPO_NAME.test(r.name)) bad('entry names must match ^[A-Za-z0-9][A-Za-z0-9._/-]*$')
    if (typeof r.root !== 'string' || !ROOT.test(r.root) || !(r.root === a.repoRoot || r.root.startsWith(`${a.repoRoot}/`))) bad('entry roots must be normalized absolute paths with no single quote or line break, equal to repoRoot or under it')
    if (r.rules != null && !(isStrList(r.rules) && r.rules.length <= 20 && r.rules.every((p) => FILE.test(p)))) bad('entry rules must list at most 20 absolute paths with no single quote or line break')
    if (r.hooks != null && !(typeof r.hooks === 'string' && r.hooks.length <= 300 && !/[\n\r]/.test(r.hooks))) bad('entry hooks must be one line of at most 300 characters')
  }
  if (new Set(rs.map((r) => r.name)).size < rs.length || new Set(rs.map((r) => r.root)).size < rs.length) bad('entry names and roots must be unique')
}
if (a.repos != null && a.seatRun) throw new Error('execute-runner repos and seatRun cannot both be set, because a seat run switches one main checkout')
const MULTI = Array.isArray(a.repos)
const relRoot = (r) => (r.root === a.repoRoot ? '' : `${r.root.slice(a.repoRoot.length + 1)}/`)
const PREFIXES = MULTI ? a.repos.map(relRoot).sort((x, y) => y.length - x.length) : ['']
const rootOf = (p) => PREFIXES.find((x) => p.startsWith(x))
const underNoRoot = (list) => (list || []).filter((p) => rootOf(p) === undefined)
const EDIT_ROOTS = MULTI ? a.repos.filter((r) => !a.repos.some((o) => o !== r && r.root.startsWith(`${o.root}/`))) : []
const SEAT_RUN = a.seatRun === true
const DIFF_BASE = SEAT_RUN ? a.diffBase : 'HEAD'
const VAULT_DIR = `${a.vaultRoot.replace(/\/+$/, '')}/`
// vault-fs.sh takes the vault-relative path inside a single-quoted shell word and refuses any `..`.
const PLAN_REL = a.planPath.startsWith(VAULT_DIR) ? a.planPath.slice(VAULT_DIR.length) : ''
if (!PLAN_REL.endsWith('.md') || /['\n]|\.\./.test(PLAN_REL)) throw new Error(`execute-runner planPath must be a .md note under vaultRoot whose vault-relative path holds no single quote, newline or .., got ${JSON.stringify(a.planPath)}`)
// Claude Code creates linked worktrees here, and git lists each as one untracked directory that git diff --no-index cannot read.
const OWN_WORKTREES = '.claude/worktrees/'
// Keys the resolved map by the agent's short name. A blank field is omitted so the session value applies.
const modelOpts = (who) => {
  const m = (a.models || {})[who] || {}
  return { ...(m.model ? { model: m.model } : {}), ...(m.effort ? { effort: m.effort } : {}) }
}
const refOk = (r) => typeof r === 'string' ? r.length > 0 : !!(r && typeof r === 'object' && typeof r.scriptPath === 'string' && r.scriptPath.length > 0)
if (a.reviewMr != null && !refOk(a.reviewMr)) throw new Error('execute-runner reviewMr must be a workflow name or {scriptPath} when given')
const MAX_FIX_ROUNDS = a.maxFixRounds ?? 1
const NITS = a.nits ?? 'fix'
const REVIEW_RULES = (a.reviewRules || '').trim()
const REVIEW_MR = a.reviewMr ?? 'toolkit:review-mr'
const STANDING = ['toolkit:code-reviewer', 'toolkit:silent-failure-hunter', 'toolkit:pr-test-analyzer']
const FULL = STANDING.concat(['toolkit:security-reviewer', 'toolkit:performance-reviewer', 'toolkit:coupling-reviewer'])
const DOCS_ONLY = ['toolkit:code-reviewer']
const HIGH_RISK = ['plugins/toolkit/hooks/', 'plugins/toolkit/scripts/', 'plugins/toolkit/workflows/', '.github/']
const panelFor = (all, extra) => {
  const paths = all.map((p) => p.slice((rootOf(p) || '').length))
  const hit = (list) => (p) => list.some((h) => p === h || p.startsWith(h))
  if (paths.some(hit(HIGH_RISK.concat(extra.any))) || all.some(hit(extra.scoped))) return { panel: FULL, rule: 'high-risk path' }
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
const sectionsIn = (lines, outside, name) => {
  const out = []
  let inSection = false
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]
    if (outside[i] && /^##\s/.test(line)) {
      inSection = line.slice(2).trim() === name
    } else if (inSection) out.push(line)
  }
  return out.join('\n').trim()
}
const rulesLines = REVIEW_RULES.split('\n')
const bullets = (text) => text.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('- '))
  .map((l) => l.slice(2).trim().split(/\s/)[0].replace(/^[`'"]+/, '').replace(/[`'".,:;]+$/, '')).filter(Boolean)
// A several-repos run joins each repo's REVIEW.md under a line REVIEW.md of <name>:, so its High-risk paths apply under that repo's root only.
const extraHighRisk = { any: [], scoped: [] }
if (REVIEW_RULES) {
  const parts = [{ prefix: null, lines: [] }]
  for (const line of rulesLines) {
    const m = MULTI ? /^REVIEW\.md of (.+):$/.exec(line.trim()) : null
    const r = m && a.repos.find((x) => x.name === m[1])
    if (r) parts.push({ prefix: relRoot(r), lines: [] })
    else parts[parts.length - 1].lines.push(line)
  }
  for (const p of parts) {
    const found = bullets(sectionsIn(p.lines, outsideFence(p.lines), 'High-risk paths'))
    if (p.prefix === null) extraHighRisk.any.push(...found)
    else extraHighRisk.scoped.push(...found.map((b) => p.prefix + b))
  }
}
const firstLine = (s) => String(s || '').split('\n')[0].trim().replace(/\.$/, '')
const str = { type: 'string' }
const num = { type: 'number' }
const bool = { type: 'boolean' }
const strList = { type: 'array', items: str }
const list = (itemSchema) => ({ type: 'array', items: itemSchema })
const obj = (properties) => ({ type: 'object', properties, required: Object.keys(properties) })
const SHA256 = /^[0-9a-f]{64}$/
// plan-index.py's E2E_MARK, so the script checks the relayed e2e flag against the relayed heading.
const E2E_MARK = /^(?:[0-9]+[.)]\s+)?\[e2e\]/
// plan-index.py's SHOTS_MARK, so a relayed shots flag that the heading does not carry fails the index check.
const SHOTS_MARK = /^(?:[0-9]+[.)]\s+)?\[e2e\]\s*\[shots\]/
const PLAN_INDEX = obj({ error: str, sha256: str,
  sections: list(obj({ name: str, line: num })),
  implementationSteps: list(obj({ heading: str, line: num })),
  validationSteps: list(obj({ heading: str, line: num, e2e: bool, shots: bool })) })
let replaying = REPLAY !== null
let lastLabel = null
// Returns the next recorded result for a label until the first label with none left, then calls agent() for that call and every later one.
const call = (prompt, opts) => {
  lastLabel = opts.label
  const q = replaying ? REPLAY.runner[opts.label] || [] : []
  if (q.length) return Promise.resolve(q.shift())
  replaying = false
  return agent(prompt, opts)
}
const childRecorded = REPLAY ? Object.values(REPLAY.child).reduce((n, q) => n + q.length, 0) : 0
let budget = a.fixBudget ?? Infinity
let liveFixes = 0
const willReplay = (label) => replaying && (REPLAY.runner[label] || []).length > 0
// A replayed round spends no budget, so the recorded control flow replays whatever the budget. A journal resume's blocked run already recorded it in Fix rounds used.
// TODO(toolkit): a dead-run continuation replays rounds its dead run never recorded, so they escape the per-plan fix cap; count them once the REPLAY record marks that kind.
const spend = (label) => {
  if (willReplay(label)) return true
  if (budget <= 0) return false
  budget -= 1
  liveFixes += 1
  return true
}
phase('Prep')
lastLabel = 'plan:index'
const planIndex = await agent(`Run exactly this command and nothing else, and change no file:
bash ${a.pluginRoot}/scripts/vault-fs.sh index '${PLAN_REL}'
It prints one JSON object. Return its sha256, sections, implementationSteps and validationSteps as printed, every string character for character and every number unchanged, and error as an empty string. Return shots as false for a Validation Step whose printed entry has no shots key. If the command exits non-zero or prints no JSON object, return error as its output, sha256 as an empty string and every list empty. Return raw structured data only.`,
  { label: 'plan:index', phase: 'Prep', schema: PLAN_INDEX, agentType: 'toolkit:verifier', ...modelOpts('verifier') })
// The index relays start lines only, so a slipped one fails this order check or an anchor a worker checks before it acts.
const indexProblem = ((ix) => {
  if (!ix) return null
  if (ix.error) return `The plan index failed: ${ix.error}`
  const rising = (rs) => rs.every((r, i) => Number.isInteger(r.line) && r.line >= 1 && (!i || r.line > rs[i - 1].line))
  const inside = (steps, name) => {
    const i = ix.sections.findIndex((s) => s.name === name)
    if (i < 0) return !steps.length
    const next = ix.sections[i + 1]
    return steps.every((s) => s.line > ix.sections[i].line && (!next || s.line < next.line))
  }
  const why = !SHA256.test(ix.sha256) ? 'its sha256 is not 64 lowercase hex characters'
    : !rising(ix.sections) ? 'its section heading lines do not rise'
    : !rising(ix.implementationSteps) || !inside(ix.implementationSteps, 'Implementation Steps') ? 'an Implementation Step line falls outside its section or out of order'
    : !rising(ix.validationSteps) || !inside(ix.validationSteps, 'Validation Steps') ? 'a Validation Step line falls outside its section or out of order'
    : ix.validationSteps.some((s) => s.e2e !== E2E_MARK.test(s.heading)) ? 'a Validation Step e2e flag does not match its heading'
    : ix.validationSteps.some((s) => s.shots === true && !SHOTS_MARK.test(s.heading)) ? 'a Validation Step shots flag does not match its heading'
    : ''
  return why ? `The plan index for ${a.planPath} is inconsistent: ${why}` : null
})(planIndex)
const ix = planIndex && !indexProblem ? planIndex : { sha256: '', sections: [], implementationSteps: [], validationSteps: [] }
const headingsOf = (x) => JSON.stringify([x.implementationSteps, x.validationSteps].map((l) => l.map((s) => s.heading)))
// plan:index runs live because the launch write changed the note's sha256, so only the step headings must match the recorded run.
const replayHeads = !REPLAY || headingsOf(ix) === headingsOf(REPLAY.index)
// A section runs from its heading line to the line before the next heading, or to the end of the note.
const rangeOf = (name) => {
  const i = ix.sections.findIndex((s) => s.name === name)
  if (i < 0) return null
  const next = ix.sections[i + 1]
  return { from: ix.sections[i].line, to: next ? next.line - 1 : null, first: name, after: next ? next.name : null }
}
// Step 1 starts at its section's heading, so text before the first marker stays with it, and each step ends where the next starts.
const stepRanges = (steps, name) => {
  const sec = rangeOf(name)
  return steps.map((s, k) => {
    const next = steps[k + 1]
    return { ...s, from: k ? s.line : sec.from, to: next ? next.line - 1 : sec.to, first: k ? s.heading : sec.first, after: next ? next.heading : sec.after }
  })
}
const pointer = (r) => `read ${r.to == null ? `from line ${r.from} to the end` : `lines ${r.from}-${r.to}`} of the plan note: line ${r.from} begins "${r.first}"${r.to == null ? '' : ` and line ${r.to + 1} begins "${r.after}"`}`
const planBlock = (title, name) => {
  const r = rangeOf(name)
  return block(title, r ? pointer(r) : '')
}
const implItems = ix.implementationSteps.length ? stepRanges(ix.implementationSteps, 'Implementation Steps') : []
const validationParsed = ix.validationSteps.length ? stepRanges(ix.validationSteps, 'Validation Steps') : []
const hasValidation = validationParsed.length > 0
const e2eSteps = validationParsed.map((s, i) => (s.e2e ? i + 1 : 0)).filter(Boolean)
const shotSteps = validationParsed.map((s, i) => (s.shots === true ? i + 1 : 0)).filter(Boolean)
const MAX_SHOTS = 5
const SHOTS_LIST = shotSteps.length ? `Screenshot STEPs: ${shotSteps.join(', ')}. ` : ''
// Paths only: an image a worker opens stays in its context as image tokens.
const SCREENSHOT_RULE = `${SHOTS_LIST}For each Screenshot STEP that you run, screenshots lists each PNG or JPEG file that this run of the STEP wrote into the output directory its command names, such as the --output directory of npx playwright test, as a path relative to ${a.repoRoot}, at most ${MAX_SHOTS}. screenshots is an empty list for every other STEP. Never open, Read or describe an image file.`
const shotsOf = (r, n) => (shotSteps.includes(n) && r.status !== 'manual' && r.status !== 'deferred' && Array.isArray(r.screenshots)
  ? r.screenshots.filter((p) => typeof p === 'string' && p.trim() && !/['\n\r]/.test(p)).slice(0, MAX_SHOTS) : [])
const E2E_OUTCOME = a.e2e === 'skip' ? { status: 'manual', evidence: 'e2e: skip' } : a.inWorktree ? { status: 'deferred', evidence: 'needs the seat' } : null
const E2E_RULE = E2E_OUTCOME && e2eSteps.length ? `End-to-end STEPs: ${e2eSteps.join(', ')}. Do not run them. Report each as ${E2E_OUTCOME.status} with ${E2E_OUTCOME.evidence} as evidence. ` : ''
const SEAT_RUN_RULE = SEAT_RUN ? `The running local stack serves ${a.repoRoot}. Run every STEP against it${E2E_RULE ? ' apart from the end-to-end STEPs named above' : ', the end-to-end STEPs included'}, and report manual only for a step that needs a human. An end-to-end STEP is never pre-existing. ` : ''
const settleE2E = (v) => (v ? { ...v, results: v.results.map((r, i) => {
  const s = { ...r, screenshots: isStop(r) ? [] : shotsOf(r, i + 1) }
  if (!e2eSteps.includes(i + 1) || isStop(r)) return s
  if (E2E_OUTCOME) return { ...s, ...E2E_OUTCOME, screenshots: [] }
  return SEAT_RUN && s.status === 'pre-existing' ? { ...s, status: 'fail' } : s
}) } : v)
const validationCount = validationParsed.length
// An e2e step that runs for real gets its own verifier, because one verifier over many e2e steps can run out its context.
const SPLIT = !E2E_OUTCOME && e2eSteps.length > 0
const blockOf = (ns) => ns.map((n) => `STEP ${n}:\n${pointer(validationParsed[n - 1])}`).join('\n\n')
const groupsOf = (label) => {
  const all = validationParsed.map((_, i) => i + 1)
  if (!SPLIT) return [[label, all]]
  const out = []
  for (const n of all) {
    const last = out[out.length - 1]
    if (e2eSteps.includes(n)) out.push([`${label}:e2e:${n}`, [n]])
    else if (last && !last[0].includes(':e2e:')) last[1].push(n)
    else out.push([out.length ? `${label}:${n}` : label, [n]])
  }
  return out
}
const priorOf = (results) => results.length
  ? `EARLIER STEP RESULTS, from the verifiers that ran the earlier STEPs of this run. Reuse the paths, temp dirs, HOME dirs, logins and URLs they name. A process an earlier verifier started may have ended with that verifier, so start it again if a STEP below needs it. When a STEP below cleans up, remove what these results name as well as what you made:\n${results.map((r) => `${firstLine(r.step)}: ${r.status}: ${r.evidence}`).join('\n')}\n\n`
  : ''
const NAME_RULE = SPLIT ? 'The verifiers of later STEPs run in other agents, so name in each evidence every path, temp dir and process that its STEP creates. ' : ''
const NOTE_CHANGED = 'The plan note changed mid-run'
const INDEX_MISMATCH = 'The plan index does not match the plan note'
const SHA_FAILED = 'The sha check on the plan note failed'
const SHA_CHECK = `bash ${a.pluginRoot}/scripts/vault-fs.sh sha256 '${PLAN_REL}'`
const CHANGED_LINE = `${NOTE_CHANGED}: sha256 <the printed value>, expected ${ix.sha256}.`
const MISMATCH_LINE = `${INDEX_MISMATCH} at line <its number>, which begins <its first words>.`
const planRead = (stop) => `PLAN NOTE: ${a.planPath}
A block that says read lines A-B of the plan note stands for those lines of this file, and names the text that line A begins with and, unless the range runs to the end, the text that line B+1 begins with, each read after any leading # marks and the whitespace after them. Before your first read of the file, run exactly ${SHA_CHECK}. If it is denied or exits non-zero, read nothing from the file and ${stop(`${SHA_FAILED}: <its output>.`)}. If it prints anything other than ${ix.sha256}, read nothing from the file and ${stop(CHANGED_LINE)}. Otherwise read each such block's lines and the line after them with the Read tool, offset at the first line and limit at the line count plus one, with no limit for a range that runs to the end. If a named line does not begin with the text the block gives, or a line after line A inside the range starts with ## and a space or tab outside a fenced block, act on nothing from that block and ${stop(MISMATCH_LINE)}. Otherwise act on the block's lines.`
const STOP = (line) => `record "${line}" as your only blockers entry and stop`
const FAIL = (line) => `return every STEP as fail with "${line}" as its evidence`
const NONE = (line) => (line === CHANGED_LINE ? 'treat every such block as none' : 'treat that block as none')
// A stop counts only on a fail result whose evidence opens with a stop sentence, because a step's evidence can quote one, as a grep for it does.
const isStop = (r) => r.status === 'fail' && [NOTE_CHANGED, INDEX_MISMATCH, SHA_FAILED].some((s) => String(r.evidence || '').replace(/^[\s"'`]+/, '').startsWith(s))
const readStop = (v) => String((((v && v.results) || []).find(isStop) || {}).evidence || '')
const stopped = (label, why) => `The verifier ${label} ran no Validation Step: ${why}`

// Duplicated in review-mr.js: workflow scripts share no module.
const unit = { type: 'number', minimum: 0, maximum: 1 }
const TAG = { type: 'string', enum: ['important', 'nit', 'pre-existing'] }
const clamp = (n) => Math.min(1, Math.max(0, Number(n) || 0))
const round2 = (n) => Math.round(clamp(n) * 100) / 100
const scoreOf = (f) => round2(0.5 * clamp(f.impact) + 0.3 * clamp(f.likelihood) + 0.2 * clamp(f.confidence))
const cited = (f) => typeof f.citation === 'string' && f.citation.trim().length > 0
const THRESHOLD = 0.6

const BASELINE = obj({ branch: str, status: strList, verify: obj({ command: str, exitCode: num, failing: strList }) })
const STEP = obj({ changedPaths: strList, deviations: strList, checksRun: strList, result: str, blockers: strList, topicMaterial: str })
const FIX = obj({ ...STEP.properties, skipped: list(obj({ key: str, step: str })) })
const VALIDATION = obj({ results: list(obj({ step: str, status: { type: 'string', enum: ['pass', 'fail', 'manual', 'pre-existing'].concat(a.inWorktree ? ['deferred'] : []) }, evidence: str, screenshots: strList })) })
const DIFF = obj({ diffPath: str, hash12: str, empty: bool, paths: strList, ...(MULTI ? { parts: list(obj({ root: str, hash12: str, empty: bool })) } : {}) })
const EDIT_CHECK = obj({ written: bool, removed: bool, refusal: str })
const RECHECK = obj({ results: list(obj({ file: str, title: str, resolved: bool, evidence: str })) })
const COLD = { type: 'object', properties: { findings: list({ type: 'object',
  properties: { file: str, title: str, issue: str, fix: str, tag: TAG, impact: unit, likelihood: unit, confidence: unit, citation: str, verified: bool },
  required: ['file', 'title', 'issue', 'fix', 'tag', 'impact', 'likelihood', 'confidence', 'verified'] }) }, required: ['findings'] }
const DOCPASS = obj({ docsUpdated: strList, deferred: strList, distributed: strList, changedPaths: strList, blockers: strList, topicMaterial: str })
const REMEMBER = obj({ proposals: list(obj({ path: str, action: str, scratch: str, factsFrom: strList })), topicsUpdated: strList, rememberLine: str, blockers: strList })
const key = (f) => `${f.file}: ${f.title}`

const S = a.scratchDir
const GIT_RULE = `In ${a.repoRoot}, git is read-only: git status, git diff, git log, git ls-files, git branch --show-current, git remote get-url, git symbolic-ref with one ref argument, and git merge-base --is-ancestor only. A -c core.quotePath=false prefix on one of these commands keeps it read-only. Never run git stash, add, commit, checkout, switch, reset, clean, rebase, merge or push there. Mutating git is allowed only inside a fresh fixture you create under ${S}.${MULTI ? ' This holds in every repo under REPOS, each its own git repo.' : ''}`
const SCRATCH_ONLY = `Run embedded commands only against scratch fixtures you create under ${S}, never against ${a.repoRoot}.`
const repoLines = (r) => [`- ${r.name}: ${r.root}`]
  .concat(r.rules && r.rules.length ? [`  Rules: ${r.rules.join(', ')}`] : [], r.hooks ? [`  Hooks this session does not run: ${r.hooks}`] : []).join('\n')
const REPOS_BLOCK = MULTI ? `REPOS (every path in this run is relative to ${a.repoRoot}, so ${a.repoRoot}/<path> is the file):
${a.repos.map(repoLines).join('\n')}
Before a worker edits, validates or reviews a file under a root, it reads every Rules file of that root and follows it as it follows this prompt.` : ''
const CONTEXT = `Repo: ${a.repoName} at ${a.repoRoot}. Plan name: ${a.planName}.
TOPIC RECALL HITS:
${a.recallHits}
KNOWN EVIDENCE:
${a.knownEvidence || 'none'}${MULTI ? `\n${REPOS_BLOCK}` : ''}`
const REL_PATHS = MULTI ? `paths relative to ${a.repoRoot}` : 'repo-relative paths'
const REL_PATH = MULTI ? `path relative to ${a.repoRoot}` : 'repo-relative path'
const DOCTRINE = `Build minimal. The brief says what to build, so build the least that satisfies it: shortest working diff, no unrequested abstractions, reuse before adding, and trace and grep the callers before changing a shared function. Prefer deleting code to adding it. Mark any deliberate shortcut with a greppable TODO(author): comment naming the ceiling and the upgrade path. See ${a.pluginRoot}/doctrine/minimalism.md.`
const REPO_STATE = MULTI ? `${REPOS_BLOCK}
The trees under REPOS are the POST-change state this diff produces. A diff path is relative to ${a.repoRoot}. There is no pre-change checkout. Reconstruct the pre-change state from the diff's context and removed lines. A defect the diff introduces is in scope even though it is present in the tree.`
  : 'The tree at repoRoot is the POST-change state this diff produces. There is no pre-change checkout. Reconstruct the pre-change state from the diff\'s context and removed lines. A defect the diff introduces is in scope even though it is present in the tree.'
const STDIN_RULE = 'Run any verify or test suite, such as bash verify.sh, with stdin from /dev/null (bash verify.sh </dev/null), because a suite that reads stdin hangs when stdin is a pipe.'
const BLOCKER_RULE = 'If any step, command or tool call is denied or cannot be done, do not work around it. Record it in blockers as one sentence and stop. The runner stops on any blockers entry, so blockers holds only work you could not do and is empty when the work is done.'
const HOOK_RULE = `The dangerous-commands hook refuses any command text, including inside a heredoc, that contains a recursive force-delete of a shell variable, a bare dot or double dot, a bare glob, a path with a /../ segment, the root, the home dir, or a system dir such as /usr, /etc or /var. Remove a scratch fixture with its literal absolute path under ${S}.`
const COMMAND_FORM_RULE = "Run a repo command in its plain form, such as <tool> exec <service> scripts/check <paths>, never wrapped in bash -c or sh -c, because the permission checks cannot read a wrapped script. The one exception is the background launch form bash -c 'set -m; <launch> ...' for a long-running local process."
const HOOK_WRITE_RULE = "If a file you create must hold a command the hook refuses, such as a script's recursive delete of a variable, create it with the Write tool, never through a heredoc."
const EXTERNAL_PROMPT = 'You are CodeRabbit, Copilot, or a senior engineer on another team seeing this diff with no context. List what you would flag that a panel briefed by the author would rationalize away: naming that hides intent, a test that proves nothing, a comment that contradicts the code, a config value that belongs elsewhere, a public surface with no doc.'
const REPO_FLAGS = (a.repos || []).map((r) => ` --repo '${r.root}'`).join('')
const CAPTURE_PROMPT = `Run exactly this command and nothing else, and change no file:
python3 ${a.pluginRoot}/scripts/slice-capture.py --scratch '${S}' --base ${DIFF_BASE} --root '${a.repoRoot}'${REPO_FLAGS}
It prints one JSON object. Return its diffPath, hash12, empty and paths${a.repos ? ' and parts' : ''} as printed, every string character for character. If the command exits non-zero or prints no JSON object, return diffPath and hash12 as empty strings, empty as true and paths empty. Return raw structured data only. ${GIT_RULE}`
const SHARED = `${CONTEXT}

${planRead(STOP)}

${DOCTRINE}
${GIT_RULE}
${BLOCKER_RULE}
${HOOK_RULE}
${HOOK_WRITE_RULE}
${COMMAND_FORM_RULE}`
const RETURN_STEP = `Return changedPaths as ${REL_PATHS}, deviations as one sentence per departure from the instructions and one per caveat or follow-up you want recorded, checksRun as the checks you ran, result as one sentence, blockers as one sentence per step you could not do or empty, and topicMaterial as the durable non-obvious facts with file:line refs, or none. Return raw structured data only.`

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
let keptForSteps = []
let open = []
let coldResidual = null
let coldUnverified = null
let fixAttempts = 0
let docPass = null
let remember = null
let diffRed = null
let diffFinal = null
let diffPost = null
let blockedAt = null
let blockedTree = null

const halt = (sentence) => {
  if (!blocked.length) blockedAt = lastLabel
  blocked.push(sentence)
}
const dead = (who, label) => {
  incomplete.push(label)
  halt(`The ${who} ${label} returned nothing.`)
}
const blockersOf = (who, label, r) => {
  if (r && r.blockers && r.blockers.length) halt(`The ${who} ${label} reported blockers: ${r.blockers.join(' ')}`)
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
const SCOPE = [planBlock('OBJECTIVE', 'Objective'), planBlock('ASSUMPTIONS', 'Assumptions')].join('\n\n')
const implementBrief = (i) => [planBlock('OBJECTIVE', 'Objective'), planBlock('CURRENT CONTEXT', 'Current Context'), planBlock('ASSUMPTIONS', 'Assumptions'), planBlock('AFFECTED FILES', 'Affected Files'),
  planBlock('VALIDATION STEPS', 'Validation Steps'), planBlock('RISKS', 'Risks'), planBlock('PLAN CHANGES DURING EXECUTION', 'Plan Changes During Execution'), block('STEPS', stepMap(i)), block('YOUR STEP', pointer(implItems[i])), changedBlock('ALREADY CHANGED')].join('\n\n')
const failingOf = (v) => v.results.filter((r) => r.status === 'fail')
const lineOf = (r) => `${firstLine(r.step)}: ${r.evidence}`
const setValidation = (v, runs) => {
  validation = {
    results: v.results,
    runs,
    allPass: v.results.length > 0 && v.results.every((r) => r.status === 'pass'),
    manualChecks: v.results.filter((r) => r.status === 'manual').map(lineOf),
    preExisting: v.results.filter((r) => r.status === 'pre-existing').map(lineOf),
    deferred: v.results.filter((r) => r.status === 'deferred').map((r) => firstLine(r.step)),
  }
}
const covers = (v) => {
  if (!v.short && v.results.length === validationCount) return true
  halt(v.results.length === validationCount ? 'A validation verifier returned a result count other than its step count.' : `Validation returned ${v.results.length} results for ${validationCount} steps.`)
  return false
}
const HEX12 = /^[0-9a-f]{12}$/
const partsOk = (d) => !MULTI || (Array.isArray(d.parts) && d.parts.length === a.repos.length && d.parts.every((p, i) => p.root === a.repos[i].root && HEX12.test(p.hash12)))
const named = (d) => (d && MULTI ? d.parts.map((p, i) => ({ name: a.repos[i].name, hash12: p.hash12, empty: p.empty })) : null)
const capture = async (label, phaseName) => {
  const d = await call(CAPTURE_PROMPT, { label, phase: phaseName, schema: DIFF, agentType: 'toolkit:verifier', ...modelOpts('verifier') })
  return d && HEX12.test(d.hash12) && partsOk(d) ? d : null
}

const finish = async () => {
  if (blocked.length && !SEAT_RUN) {
    phase('Finish')
    const t = await capture('diff:blocked', 'Finish')
    blockedTree = t ? t.hash12 : null
  }
  const left = REPLAY && replayHeads ? Object.values(REPLAY.runner).reduce((n, q) => n + q.length, 0) + childRecorded - (review && Number.isInteger(review.replayed) ? review.replayed : 0) : 0
  if (left) halt(`The continuation left ${left} of its recorded results unused, so its control flow differs from the recorded run. The likely cause is a review-mr child without replay support.`)
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
      keptForSteps,
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
    remember: remember || { ran: false, material, proposals: [], topicsUpdated: [], rememberLine: '', reason: '' },
    changedPaths: changed,
    planChanges,
    diffHashes: { redTeam: diffRed ? diffRed.hash12 : null, final: diffFinal ? diffFinal.hash12 : null, postDoc: diffPost ? diffPost.hash12 : null },
    diffPaths: { redTeam: diffRed ? diffRed.diffPath : null, final: diffFinal ? diffFinal.diffPath : null, postDoc: diffPost ? diffPost.diffPath : null },
    diffFiles: { redTeam: diffRed ? diffRed.paths : null, final: diffFinal ? diffFinal.paths : null, postDoc: diffPost ? diffPost.paths : null },
    diffParts: { redTeam: named(diffRed), final: named(diffFinal), postDoc: named(diffPost) },
    blocked,
    incomplete,
    blockedAt,
    blockedTree,
    fixRounds: liveFixes,
  }
}

if (!planIndex) {
  dead('verifier', 'plan:index')
  return await finish()
}
if (indexProblem) {
  halt(`${indexProblem}.`)
  return await finish()
}
if (!replayHeads) {
  halt(`The plan's step headings differ from the recorded run's plan:index, so the run cannot continue from its journal.`)
  return await finish()
}
if (!implItems.length) {
  halt('The plan has no Implementation Steps.')
  return await finish()
}
if (a.e2e === 'required' && hasValidation && !e2eSteps.length) {
  halt(`The plan's e2e option is required and no Validation Step carries the [e2e] marker after its number.`)
  return await finish()
}

// The first several-repos stage proves the harness lets a runner worker write under each top-level root; a nested root sits inside one.
for (const r of EDIT_ROOTS) {
  const file = `${r.root}/toolkit-edit-check-${a.planName}.tmp`
  const e = await call(`Use the Write tool to create ${file} holding the one line toolkit edit check. Then run exactly rm -f -- '${file}' as its own Bash call, then exactly test ! -e '${file}' as its own Bash call. Run nothing else and change no other file. Return written as true only when the Write tool created the file, removed as true only when that test exited 0, and refusal as the refusal or error text the Write tool returned, or an empty string when it wrote the file. Return raw structured data only.`,
    { label: 'edit:check', phase: 'Prep', schema: EDIT_CHECK, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
  if (!e) dead('implementer', 'edit:check')
  else if (!e.written) halt(`Claude Code refused a worker's edit in ${r.root} from a session started in the projects root: ${firstLine(e.refusal) || 'no refusal text'}. A permissions.allow rule does not pre-approve a protected-path write, so the plan is built by hand until the harness allows it.`)
  else if (e.removed !== true) halt(`The edit check could not remove ${file}, so remove it by hand before a rerun.`)
  if (!e || !e.written || e.removed !== true) return await finish()
}

const verifyLine = a.verifyCommand
  ? `run the verify command ${a.verifyCommand}${MULTI ? ` from ${a.repoRoot}` : ''}`
  : MULTI ? 'find and run that repo\'s verify or test command from its AGENTS.md, CLAUDE.md, VERIFY.md or package manifest. If you find none in any root, run none, set command to none and exitCode to -1, and set failing to the one sentence No verify command was found'
  : 'find and run the repo\'s verify or test command from AGENTS.md, CLAUDE.md, VERIFY.md or the package manifest. If you find none, run none, set command to none and exitCode to -1, and set failing to the one sentence No verify command was found'
const BASELINE_RUN = MULTI
  ? `In each root under REPOS, run git branch --show-current and git status --porcelain, then ${verifyLine}. ${STDIN_RULE} Return branch as <name>=<branch> pairs in REPOS order joined by a comma and a space, status as every root's git status --porcelain lines with each path prefixed by its root's path relative to ${a.repoRoot}, and verify with command as the cd '<root>' && <command> parts you ran joined by " ; ", exitCode as the first non-zero exit code or 0, and failing as <name>: <check> for each check a command reported as failed.`
  : `In ${a.repoRoot}, run git branch --show-current and git status --porcelain, then ${verifyLine}. ${STDIN_RULE} Return branch, status as the git status --porcelain lines, and verify with the command you ran, its exit code, and failing as the names of the checks it reported as failed.`
baseline = await call(`${CONTEXT}

${BASELINE_RUN} ${COMMAND_FORM_RULE} Change no file. ${GIT_RULE} Return raw structured data only.`,
  { label: 'prep:baseline', phase: 'Prep', schema: BASELINE, agentType: 'toolkit:verifier', ...modelOpts('verifier') })
if (!baseline) dead('verifier', 'prep:baseline')
else if (a.baselineFailing) baseline.verify = { ...baseline.verify, failing: a.baselineFailing }
if (!hasValidation) halt('The plan has no Validation Steps, so nothing proves the slice.')

phase('Implement')
for (let i = 0; i < (SEAT_RUN ? 0 : implItems.length); i += 1) {
  const label = `implement:${i + 1}`
  const r = await call(`${SHARED}

${implementBrief(i)}

Implement YOUR STEP in ${a.repoRoot} and nothing beyond it. STEPS lists every step of the plan by heading so you can see where your step ends, and the other steps are not your work. Earlier steps already ran, and their changes are the paths under ALREADY CHANGED. ${RETURN_STEP}`,
    { label, phase: 'Implement', schema: STEP, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
  if (!r) {
    dead('implementer', label)
    return await finish()
  }
  steps.push(r)
  collect(r.changedPaths, r.topicMaterial)
  for (const d of r.deviations || []) planChanges.push(`Step ${i + 1}: ${d}`)
  if (blockersOf('implementer', label, r)) return await finish()
}

phase('Verify')
const SEAT_RULE = a.inWorktree ? `${MULTI ? "This run sits in git worktrees, and the running local stack serves each repo's main checkout, not the trees under REPOS." : `This run sits in a git worktree, and the running local stack serves the main checkout, not ${a.repoRoot}.`} Do not run a STEP that needs the running local stack: the site's URL, a browser check, a request to the local stack, or anything else that the main checkout's running services serve. Report such a STEP as deferred with needs the seat as evidence, and run every other STEP. Create nothing outside ${a.repoRoot}: no container, no database clone, no media mount, no hostname. ` : ''
const validateGroup = (label, phaseName, ns, prior) => call(`${CONTEXT}

${planRead(FAIL)}

${priorOf(prior)}VALIDATION STEPS:
${blockOf(ns)}

BASELINE VERIFY RESULT:
${baseline ? JSON.stringify(baseline.verify) : 'none, the baseline check did not run'}

Run each STEP above that an agent can run here, against ${a.repoRoot}. Return exactly ${ns.length} results, one per STEP, in order, with step set to the STEP number and the step's first line, as in STEP 1: <first line>. status is pass or fail with the command output as evidence, never a guessed pass. status is manual, with the reason as evidence, for a step that needs a human or another session. status is pre-existing when a step fails only on a check that the baseline failing list already names. If a command is denied, report its step as fail with the denial as evidence. ${NAME_RULE}${SEAT_RULE}${E2E_RULE}${SEAT_RUN_RULE}${SCREENSHOT_RULE} ${STDIN_RULE} ${HOOK_RULE} ${COMMAND_FORM_RULE} Change no file. ${GIT_RULE} Return raw structured data only.`,
  { label, phase: phaseName, schema: VALIDATION, agentType: 'toolkit:verifier', ...modelOpts('verifier') })
// Groups run in written order. A stop or a short count in one group runs no later group, and a null group is recorded dead under its own label.
const runValidation = async (label, phaseName) => {
  const merged = []
  for (const [l, ns] of groupsOf(label)) {
    const v = await validateGroup(l, phaseName, ns, merged)
    if (!v) {
      dead('verifier', l)
      return null
    }
    merged.push(...v.results)
    if (v.results.length !== ns.length || readStop(v)) return settleE2E({ results: merged, short: true })
  }
  return settleE2E({ results: merged, short: false })
}

if (!hasValidation) setValidation({ results: [] }, 0)
else {
  let v = await runValidation('verify:validation', 'Verify')
  if (!v) return await finish()
  setValidation(v, 1)
  if (readStop(v)) { halt(stopped('verify:validation', readStop(v))); return await finish() }
  if (!covers(v)) {
    failingOf(v).forEach((r) => halt(`Validation step failed: ${firstLine(r.step)}.`))
    return await finish()
  }
  const failing = failingOf(v)
  if (failing.length && !spend('fix:validation')) {
    failing.forEach((r) => halt(`Validation step failed with the plan's fix budget spent: ${firstLine(r.step)}.`))
    return await finish()
  }
  if (failing.length) {
    const fix = await call(`${SHARED}

${SCOPE}

${planBlock('PLAN CHANGES DURING EXECUTION', 'Plan Changes During Execution')}

${changedBlock('CHANGED PATHS')}

FAILING VALIDATION STEPS:
${failing.map((r) => `${r.step}\nEVIDENCE: ${r.evidence}`).join('\n\n')}

Fix only what makes these steps pass, in ${a.repoRoot}. ${RETURN_STEP}`,
      { label: 'fix:validation', phase: 'Verify', schema: STEP, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
    if (!fix) {
      dead('implementer', 'fix:validation')
      return await finish()
    }
    collect(fix.changedPaths, fix.topicMaterial)
    planChanges.push(`Validation fix: ${fix.result}`)
    for (const d of fix.deviations || []) planChanges.push(`Validation fix deviation: ${d}`)
    if (blockersOf('implementer', 'fix:validation', fix)) return await finish()
    v = await runValidation('verify:revalidation', 'Verify')
    if (!v) return await finish()
    setValidation(v, 2)
    if (readStop(v)) { halt(stopped('verify:revalidation', readStop(v))); return await finish() }
    covers(v)
    const still = failingOf(v)
    if (still.length) {
      still.forEach((r) => halt(`Validation step failed after one fix: ${firstLine(r.step)}.`))
      return await finish()
    }
  }
}

phase('Red team')
diffRed = await capture('diff:red-team', 'Red team')
if (SEAT_RUN && diffRed) {
  const stray = (diffRed.paths || []).filter((p) => !changed.includes(p) && !p.startsWith(OWN_WORKTREES))
  if (stray.length) {
    halt(`The seat run left paths that no fix wrote: ${stray.join(', ')}.`)
    return await finish()
  }
  if (diffRed.empty) return await finish()
}
if (!diffRed) dead('verifier', 'diff:red-team')
else if (diffRed.empty) halt('The diff after implementation is empty.')

if (diffRed && !diffRed.empty) {
  const reviewPaths = [...new Set((diffRed.paths || []).concat(changed))]
  const picked = panelFor(reviewPaths, extraHighRisk)
  panel = picked.panel
  panelRule = picked.rule
  const contextBlock = `Repo: ${a.repoName} at ${a.repoRoot}. Plan name: ${a.planName}.
${planBlock('OBJECTIVE', 'Objective')}
CHANGED PATHS:
${changed.join('\n') || 'none'}
SETTLED DECISIONS:
The owner accepted the plan's Assumptions and Risks at approval. A finding that only restates one of them, or asks for scope or coverage the Assumptions exclude, is not a finding, unless the tree contradicts the decision, in which case report it as a normal finding. A breach of a written rule in rules/, doctrine/, CLAUDE.md, AGENTS.md or .claude/rules, or a doc line the tree contradicts, is never settled by an Assumption or Risk: report it as a normal finding and never lower its score on plan grounds.
${planBlock('ASSUMPTIONS', 'Assumptions')}
${planBlock('RISKS', 'Risks')}
${planRead(NONE)}

${MULTI ? 'Apply the project rules in the files each Rules line under REPOS names, each to the files under its own root.' : `Apply the project rules in the CLAUDE.md, AGENTS.md and .claude/rules files under ${a.repoRoot} where they exist.`} When the diff ships executable commands embedded in prose, such as a skill, a workflow script's prompts or a doc, execute those exact commands against a scratch fixture covering the awkward cases (clean tree, dirty tree, untracked directories, unusual filenames) rather than judge them by reading. ${SCRATCH_ONLY} ${GIT_RULE}${REVIEW_RULES ? `\n\nREVIEW RULES (REVIEW.md on the default branch):\n${REVIEW_RULES}` : ''}`
  try {
    lastLabel = 'review'
    review = await workflow(REVIEW_MR, { diffPath: diffRed.diffPath, repoRoot: a.repoRoot, contextBlock, repoState: REPO_STATE, dimensions: DIMENSIONS, registryReviewers: panel, models: a.models, ...(replaying ? { replay: REPLAY.child } : {}) })
    if (review == null) {
      review = null
      halt('The review-mr child workflow returned nothing.')
    } else if (!Array.isArray(review.dead)) {
      halt('The review panel did not report which reviewers ran.')
    } else if (review.dead.length) {
      halt(`The review panel lost ${review.dead.length} reviewers: ${review.dead.join(', ')}.`)
    }
    if (review && Array.isArray(review.verifierDead) && review.verifierDead.length) halt(`The review panel lost the verifier for ${review.verifierDead.length} dimensions: ${review.verifierDead.join(', ')}.`)
  } catch (e) {
    review = null
    halt(`The review-mr child workflow failed: ${e && e.message ? e.message : 'no message'}.`)
  }
}

if (review) {
  phase('Fix')
  const confirmedOpen = (review.confirmed || []).map((f) => ({ ...f, bucket: 'confirmed' }))
  const nitsOpen = (review.nits || []).map((f) => ({ ...f, bucket: 'nit' }))
  const withNits = NITS === 'fix' ? confirmedOpen.concat(nitsOpen) : confirmedOpen
  // The worktree run already offered a seat run's nits, so nits alone start no round there.
  open = SEAT_RUN && !confirmedOpen.length ? [] : withNits
  let stageDead = false
  let budgetOut = false
  for (let round = 1; round <= MAX_FIX_ROUNDS && open.some((f) => f.bucket === 'confirmed' || round === 1); round += 1) {
    if (!spend(`fix:${round}`)) {
      budgetOut = true
      break
    }
    const entry = (f) => `${key(f)} [${f.finalTag || f.tag}, final score ${f.finalScore}, ${f.reproduced ? (f.finalScore < THRESHOLD ? 'cited line read' : 'reproduced') : 'not reproduced'}]\nCITATION: ${f.citation || 'none'}\nDETAIL: ${f.detail}\nFAILURE SCENARIO: ${f.failure_scenario || 'none given'}`
    const confirmedBlock = open.filter((f) => f.bucket === 'confirmed').map(entry).join('\n\n') || 'none'
    const nitBlock = open.filter((f) => f.bucket === 'nit').map(entry).join('\n\n') || 'none'
    const fix = await call(`${SHARED}

${SCOPE}

${changedBlock('CHANGED PATHS')}

${planBlock('VALIDATION STEPS', 'Validation Steps')}

CONFIRMED FINDINGS:
${confirmedBlock}

NITS:
${nitBlock}

Fix each confirmed finding above in ${a.repoRoot} with the smallest change that removes the defect, and, when its tag is important and its finalScore is ${THRESHOLD} or above, fix every instance of that class of defect in the slice, not one line. Fix a confirmed finding tagged nit only at its cited line, and fix any confirmed finding below ${THRESHOLD} only at its cited line. For each nit, fix only the cited line, and only when the tree confirms the nit. Leave a nit, or a confirmed finding whose finalScore is below ${THRESHOLD}, unfixed when its fix would make a step under VALIDATION STEPS fail, such as an edit to text that a step checks byte for byte, and return each one in skipped as one {key, step}, with key as its <file>: <title> exactly as listed above and step as the STEP number and first line of the Validation Step its fix would fail. Return skipped empty when you leave none. ${RETURN_STEP}`,
      { label: `fix:${round}`, phase: 'Fix', schema: FIX, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
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
    // A nit or a confirmed finding below THRESHOLD that the fix left for a Validation Step is settled, so it starts no later round.
    const skippedFor = new Map((fix.skipped || []).map((s) => [s.key, s.step]))
    const kept = open.filter((f) => skippedFor.has(key(f)) && (f.bucket === 'nit' || f.finalScore < THRESHOLD))
    for (const f of kept) planChanges.push(`Fix round ${round} kept for a Validation Step: ${key(f)} [${f.finalTag || f.tag}, score ${f.score}, final ${f.finalScore}] (${skippedFor.get(key(f))})`)
    keptForSteps = keptForSteps.concat(kept.map((f) => ({ ...f, round, step: skippedFor.get(key(f)) })))
    open = open.filter((f) => !kept.includes(f))
    if (!open.length) break
    const findings = open.map((f) => `${key(f)}\nDETAIL: ${f.detail}\nFAILURE SCENARIO: ${f.failure_scenario || 'none given'}`).join('\n\n')
    const re = await call(`${CONTEXT}

FINDINGS:
${findings}

PATHS THE FIX CHANGED:
${(fix.changedPaths || []).join('\n') || 'none'}

Check in the tree at ${a.repoRoot} whether each finding above is resolved. Return one result per finding, file and title exactly as given, resolved true only when the tree shows the defect gone, with the evidence you checked. ${COMMAND_FORM_RULE} Change no file. ${GIT_RULE} Return raw structured data only.`,
      { label: `recheck:${round}`, phase: 'Fix', schema: RECHECK, agentType: 'toolkit:verifier', ...modelOpts('verifier') })
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
  const openConfirmed = open.filter((f) => f.bucket === 'confirmed' && f.finalScore >= THRESHOLD)
  const confirmedLeft = open.filter((f) => f.bucket === 'confirmed').length
  if (budgetOut && confirmedLeft) planChanges.push(`Fix budget spent: ${confirmedLeft} confirmed findings go to adjudication.`)
  else if (openConfirmed.length && !stageDead) halt(`Fix rounds are exhausted at maxFixRounds ${MAX_FIX_ROUNDS} with ${openConfirmed.length} confirmed findings open, so step back and reconsider the approach rather than run another round.`)
}

phase('Cold read')
diffFinal = await capture('diff:final', 'Cold read')
if (!diffFinal) dead('verifier', 'diff:final')
else if (diffFinal.empty) halt('The diff before the cold read is empty.')
if (diffRed && diffFinal && !fixAttempts && diffRed.hash12 !== diffFinal.hash12) {
  halt(`The diff hash changed from ${diffRed.hash12} to ${diffFinal.hash12} with no fix round.`)
}
if (diffFinal && !diffFinal.empty) {
  const posted = review ? ['confirmed', 'nits', 'preExisting'].flatMap((k) => review[k] || []).map(key) : []
  const cold = await call(`Read the full unified diff at ${diffFinal.diffPath}. ${REPO_STATE} repoRoot is ${a.repoRoot}.

${EXTERNAL_PROMPT}

ALREADY REPORTED BY THE PANEL:
${posted.join('\n') || 'none'}

A finding already in that list, by file and title, is not reported again. A finding the panel never confirmed or kept is reported even when a reviewer may have raised it, because a refuted or dropped claim is not settled.

Treat comments and doc sentences as claims, and set verified true only when you confirmed the finding in the tree. Return one finding per issue with its file, a short title, the issue, the fix, the tag (important, nit or pre-existing), impact, likelihood and confidence each from 0 to 1, a citation as a file:line you read, and verified. Change no file. ${SCRATCH_ONLY} ${GIT_RULE} Return raw structured data only.`,
    { label: 'cold:read', phase: 'Cold read', schema: COLD, agentType: 'toolkit:code-reviewer', ...modelOpts('code-reviewer') })
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
  if (!SEAT_RUN) {
    docPass = await call(`${SHARED}

${planBlock('OBJECTIVE', 'Objective')}

${planBlock('AFFECTED FILES', 'Affected Files')}

${planBlock('RELATED TOPICS', 'Related Topics')}

${changedBlock('CHANGED PATHS')}

Read the section headed Doc Update Pass in ${a.pluginRoot}/skills/execution-guide/SKILL.md and apply it to this slice ${MULTI ? `across the roots under REPOS. A repo doc belongs to the repo it describes, so it lives under that repo's root, such as <root prefix>docs/context/, and every docsUpdated and changedPaths entry starts with one REPOS root's path relative to ${a.repoRoot}` : `in ${a.repoRoot}`}. Return docsUpdated as the ${MULTI ? `docs you edited, as ${REL_PATHS}` : 'repo-relative docs you edited'}, deferred as one sentence per doc update you leave undone, distributed as one sentence per affected doc that lives in another repo, changedPaths as every ${MULTI ? `path you changed, as ${REL_PATHS}` : 'repo-relative path you changed'}, blockers as one sentence per step you could not do or empty, and topicMaterial as the durable non-obvious facts with file:line refs, or none. Return raw structured data only.`,
      { label: 'doc:pass', phase: 'Doc pass', schema: DOCPASS, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
    if (!docPass) dead('implementer', 'doc:pass')
    else {
      collect(docPass.changedPaths, docPass.topicMaterial)
      for (const d of docPass.deferred || []) planChanges.push(`Doc debt: ${d}`)
      blockersOf('implementer', 'doc:pass', docPass)
      const stray = [...new Set(underNoRoot((docPass.docsUpdated || []).concat(docPass.changedPaths || [])))]
      for (const p of stray) halt(`The doc pass returned ${p}, which sits under no repo root.`)
      if (stray.length) return await finish()
    }
  }
  if (hasValidation && validation && (rounds.length || (docPass && docPass.changedPaths && docPass.changedPaths.length))) {
    const vf = await runValidation('verify:final', 'Doc pass')
    if (vf && readStop(vf)) halt(stopped('verify:final', readStop(vf)))
    else if (vf) {
      setValidation(vf, validation.runs + 1)
      covers(vf)
      failingOf(vf).forEach((r) => halt(`Validation step failed after the doc pass: ${firstLine(r.step)}.`))
    }
  }
  diffPost = await capture('diff:post-doc', 'Doc pass')
  if (!diffPost) dead('verifier', 'diff:post-doc')
  else if (diffPost.empty) {
    halt('The diff after the doc pass is empty.')
    diffPost = null
  }
}

phase('Remember')
if (!blocked.length && !SEAT_RUN) {
  const rem = await call(`Objective: route the durable facts this slice surfaced. Fold the vault-bound facts into vault topic notes, and stage the repo-bound facts as proposed doc content for the conductor's consent gate.

Scope: write only under the vault root folder ${a.vaultRoot} and the scratchpad ${S}. You must not write any repo file.

Known evidence: the cumulative diff at ${diffPost.diffPath}, the touched files ${changed.join(', ') || 'none'}, the Topic note material returns from this slice ${material.join(' ') || 'none'}, and the recall hits ${a.recallHits}.
${MULTI ? `\n${REPOS_BLOCK}\n` : ''}
${planRead(STOP)}

${planBlock('RELATED TOPICS', 'Related Topics')}

Task-specific constraints. The plugin root is ${a.pluginRoot}. Before your first write, read these files under that root: commands/topic.md, doctrine/security.md, doctrine/repo-artifacts.md, and the usage header of scripts/vault-fs.sh.

Routing: before any write, classify each durable fact. Class (a) is shareable engineering knowledge about this repo. Class (b) is cross-repo, not about any repo, or personal workflow. A class (a) fact routes only to a docs/context/ doc that carries the <!-- managed-by: toolkit --> marker: an existing one that covers the subject, else a new docs/context/context-<kebab>.md. Never route a fact into a hand-written repo doc. If a hand-written repo doc covers the subject, name it as the related doc on the proposal. A class (b) fact routes to the vault topic note. If a vault note carries the repo-mode banner, route its new facts to the doc the banner names, never into the note.${MULTI ? ` In this run a class (a) fact is about one repo under REPOS and routes only to a docs/context/ doc under that repo's root, a fact about how two repos work together is class (b), and each proposal path starts with that root's path relative to ${a.repoRoot}.` : ''}

Class (a) content: for each proposed repo doc, write the full proposed content to ${S}/remember-<kebab-path>.md, where <kebab-path> is the ${REL_PATH} in kebab case. Scrub the content per doctrine/security.md first. For a new file, write the whole doc with the frontmatter doctrine/repo-artifacts.md requires and the <!-- managed-by: toolkit --> marker on the line after the frontmatter. For an existing managed file, write only the exact section to add and name the heading it goes under. Do not write class (a) facts into any vault note.

Class (b) writes: for each candidate topic, fold facts under the section they belong to (Flows, Gotchas, Tasks, Related Topics). Never rewrite Overview or any prose that carries no new fact. Bump updated. Spot-check one source_refs entry against the repo, and set verified to today only on a clean check. Create a stub only for a concept that RELATED TOPICS or the collected material names and no existing note covers. Search by basename before creating. Write every vault file atomically: Write to <name>.tmp.md beside the target, then run bash ${a.pluginRoot}/scripts/vault-fs.sh mv.

Required checks: read back every vault file you wrote and confirm it holds the folded facts. Run no git command. ${BLOCKER_RULE}

Expected return format: proposals holds one entry per proposed repo doc, with path as the ${REL_PATH}, action as created or updated, scratch as the scratch file path, and factsFrom as the [[Note]] names whose facts move into that doc. If a hand-written doc covers the subject, add one factsFrom entry that reads related <${REL_PATH}>. proposals is empty when there is no proposal. topicsUpdated lists every vault note you touched. rememberLine is exactly one draft line in one of these forms: Remember: repo docs <paths>; topics updated [[A]], [[B]] or Remember: repo docs <paths> or Remember: topics updated [[A]] or Remember: no change (<reason>). blockers holds one sentence per step you could not do and is empty otherwise. Return raw structured data only.`,
    { label: 'remember:pass', phase: 'Remember', schema: REMEMBER, agentType: 'toolkit:implementer', ...modelOpts('implementer') })
  // A failed remember pass never blocks: it writes vault notes only, so the conductor runs it from the material.
  if (!rem) remember = { ran: false, material, proposals: [], topicsUpdated: [], rememberLine: '', reason: 'The implementer remember:pass returned nothing.' }
  else if (rem.blockers && rem.blockers.length) remember = { ran: false, material, proposals: [], topicsUpdated: rem.topicsUpdated || [], rememberLine: '', reason: `The implementer remember:pass reported blockers: ${rem.blockers.join(' ')}` }
  else {
    const stray = underNoRoot((rem.proposals || []).map((x) => x.path))
    for (const p of stray) halt(`The remember pass proposed ${p}, which sits under no repo root.`)
    remember = { ran: !stray.length, material, proposals: stray.length ? [] : rem.proposals, topicsUpdated: rem.topicsUpdated, rememberLine: stray.length ? '' : rem.rememberLine, reason: '' }
  }
}

return await finish()
