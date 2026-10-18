export const meta = {
  name: 'plan-flow',
  description: 'Plan flow: discovery, planner draft, plan-critic pre-mortem with a revise loop, cold red team, optional goal judge. Returns plan sections for the plan-flow skill to write. Writes no files, runs no git.',
  phases: [
    { title: 'Discover', detail: 'explorer scopes 2 to 5 areas, one explorer per area' },
    { title: 'Draft', detail: 'planner returns every plan section' },
    { title: 'Invert', detail: 'plan-critic pre-mortem, planner revises on a revise verdict' },
    { title: 'Red team', detail: 'cold plan-critic sees the plan alone' },
    { title: 'Judge', detail: 'verifier judges the plan against approveIf' },
  ],
}

let a = args
if (typeof a === 'string') {
  try { a = JSON.parse(a) } catch (e) { a = null }
}
const REQUIRED = ['brief', 'repoRoot', 'repoName', 'planName', 'recallHits']
if (!a || REQUIRED.some((k) => typeof a[k] !== 'string' || !a[k])) {
  throw new Error('plan-flow requires args: {brief, repoRoot, repoName, planName, recallHits, knownEvidence?, approveIf?, maxRounds?}')
}
if (a.maxRounds != null && !(Number.isInteger(a.maxRounds) && a.maxRounds >= 0)) {
  throw new Error(`plan-flow maxRounds must be a non-negative integer, got ${JSON.stringify(a.maxRounds)}`)
}
const MAX_ROUNDS = a.maxRounds ?? 2
const incomplete = []

const SECTIONS = [
  ['objective', 'Objective'], ['plainLanguageSummary', 'Plain Language Summary'],
  ['currentContext', 'Current Context'], ['assumptions', 'Assumptions'],
  ['affectedFiles', 'Affected Files'], ['implementationSteps', 'Implementation Steps'],
  ['validationSteps', 'Validation Steps'], ['risks', 'Risks'], ['rollbackNotes', 'Rollback Notes'],
  ['openQuestions', 'Open Questions'], ['relatedTopics', 'Related Topics'],
]
const str = { type: 'string' }
const strList = { type: 'array', items: str }
const obj = (properties) => ({ type: 'object', properties, required: Object.keys(properties) })

const AREAS_SCHEMA = obj({
  areas: { type: 'array', minItems: 2, maxItems: 5, items: obj({ name: str, question: str, paths: strList }) },
})
const FINDINGS_SCHEMA = obj({
  facts: { type: 'array', items: obj({ claim: str, ref: str }) },
  gaps: strList,
  risks: strList,
  reuse: str,
})
const PLAN_SCHEMA = obj({
  plan: obj(Object.fromEntries(SECTIONS.map(([k]) => [k, str]))),
  branch: str,
  relatedTopics: strList,
})
const CRITIQUE_SCHEMA = obj({
  verdict: { type: 'string', enum: ['proceed', 'revise', 'stop'] },
  objections: { type: 'array', items: obj({ section: str, claim: str, evidence: str, fix: str, material: { type: 'boolean' } }) },
  tripwires: strList,
  walkAway: strList,
})
const JUDGE_SCHEMA = obj({ meets: { type: 'boolean' }, reasons: strList, unmetGoals: strList })

const render = (d) => SECTIONS.map(([k, h]) => `## ${h}\n\n${d.plan[k]}`).join('\n\n')
const material = (c) => (c ? c.objections.filter((o) => o.material) : [])

const CONTEXT = `Repo: ${a.repoName} at ${a.repoRoot}. Plan name: ${a.planName}.
BRIEF:
${a.brief}
TOPIC RECALL HITS:
${a.recallHits}
KNOWN EVIDENCE:
${a.knownEvidence || 'none'}`

const RULES = `Return every plan section as its body text without the heading line. Plain Language Summary starts with the exact sentence "This section is for non-technical readers. The technical detail below it can be skipped." Implementation Steps show the code: key functions, a directory tree for new files, schemas, and the exact commands or config keys. Record the reuse ladder result in Current Context. Feasibility gate: every signal, integration, or data source names a real-data check and its result in Current Context, with "external dependency: none" or the named dependency. Open Questions and Assumptions read "None" or name an external unknown with its owner. Spec, not journal. No em dashes, no semicolons splitting prose, no hard-wrapped lines. branch is <type>/<slug>. The plan section relatedTopics is one [[wiki link]] per line, one line per topic. The top-level relatedTopics list holds the same topics as plain names without brackets.`

phase('Discover')
const scope = await agent(`${CONTEXT}

Split this brief into 2 to 5 investigation areas a planner needs answered. Each area has a name, one question the repo can answer, and the paths to start from. Skip what the recall hits and known evidence settle. Return raw structured data only.`,
  { label: 'discover:scope', phase: 'Discover', schema: AREAS_SCHEMA, agentType: 'toolkit:explorer' })
if (!scope) incomplete.push('discover:scope')
const areas = scope ? scope.areas : [{ name: 'whole-brief', question: 'What in the repo does this brief touch?', paths: [a.repoRoot] }]

// Labels key the resume cache, so a repeated area name gets its index.
const areaLabel = (area, i) => (areas.filter((x) => x.name === area.name).length > 1 ? `discover:${area.name}:${i}` : `discover:${area.name}`)
const findings = await pipeline(areas.map((area, i) => ({ ...area, label: areaLabel(area, i) })), (area) => agent(`${CONTEXT}

AREA: ${area.name}
QUESTION: ${area.question}
START AT: ${area.paths.join(', ')}

Answer the question from the repo. Every fact carries the file:line you read. Walk the reuse ladder: does it need to exist, does the codebase, the standard library, the framework, or an installed dependency already do it, can it be a few lines in the right place. List the gaps you could not close and the risks the brief omits. Return raw structured data only.`,
  { label: area.label, phase: 'Discover', schema: FINDINGS_SCHEMA, agentType: 'toolkit:explorer' }))
const uncovered = areas.filter((area, i) => !findings[i]).map((area) => area.name)
const evidence = areas.map((area, i) => ({ area: area.name, ...findings[i] })).filter((f) => f.facts)

phase('Draft')
let draft = await agent(`${CONTEXT}

EXPLORER FINDINGS:
${JSON.stringify(evidence)}
UNCOVERED AREAS: ${uncovered.join(', ') || 'none'}

Draft the plan from the evidence above. Read the repo at ${a.repoRoot} only to close a gap the evidence leaves. ${RULES}`,
  { label: 'draft', phase: 'Draft', schema: PLAN_SCHEMA, agentType: 'toolkit:planner' })
if (!draft) throw new Error('plan-flow: planner returned no draft')

const critique = (plan, label, cold) => agent(`${cold ? 'You are a senior engineer on another team seeing only this plan.' : CONTEXT}

PLAN:
${plan}

Run the pre-mortem your agent instructions define over this plan, with the repo at ${a.repoRoot} as ground truth. An objection is material only when ignoring it causes rework, a wrong outcome, or a missed risk. verdict is proceed when no objection is material, revise when every material objection has a fix inside this plan, stop when a fatal flaw has none. tripwires: one measurable signal per failure mode with its threshold and when to check. walkAway: one pre-launch check per line with the result that means walk away. Return raw structured data only.`,
  { label, phase: cold ? 'Red team' : 'Invert', schema: CRITIQUE_SCHEMA, agentType: 'toolkit:plan-critic' })

const revise = (prev, objections, label, phaseName) => agent(`${CONTEXT}

CURRENT PLAN (JSON):
${JSON.stringify(prev)}
MATERIAL OBJECTIONS:
${JSON.stringify(objections)}

Return the full plan with every objection resolved in place, or recorded under Risks as an accepted risk with its reason. ${RULES}`,
  { label, phase: phaseName, schema: PLAN_SCHEMA, agentType: 'toolkit:planner' })

phase('Invert')
const rounds = []
const reviseDead = []
let last = null
let lastSeen = null
let revisedAfterLast = false
const critiqueDraft = async (label) => {
  const seen = render(draft)
  const v = await critique(seen, label, false)
  rounds.push({ verdict: v ? v.verdict : 'incomplete', materialCount: material(v).length })
  if (v) {
    last = v
    lastSeen = seen
    revisedAfterLast = false
  } else incomplete.push(label)
  return v
}
let verdict = await critiqueDraft('invert:0')
let round = 0
while (verdict && verdict.verdict === 'revise' && round < MAX_ROUNDS) {
  round += 1
  const next = await revise(draft, material(verdict), `revise:${round}`, 'Invert')
  if (!next) {
    incomplete.push(`revise:${round}`)
    reviseDead.push(`revise:${round}`)
    break
  }
  draft = next
  revisedAfterLast = true
  verdict = await critiqueDraft(`invert:${round}`)
}

phase('Red team')
const cold = await critique(render(draft), 'red-team:cold', true)
if (!cold) incomplete.push('red-team:cold')
const coldMaterial = material(cold)
let coldOpen = []
let coldUnchanged = false
if (coldMaterial.length) {
  const next = await revise(draft, coldMaterial, 'revise:cold', 'Red team')
  if (!next) {
    incomplete.push('revise:cold')
    reviseDead.push('revise:cold')
    coldOpen = coldMaterial
  } else if (render(next) === render(draft)) {
    coldUnchanged = true
    coldOpen = coldMaterial
  } else draft = next
}

const finalVerdict = last ? last.verdict : 'incomplete'
const invertOpen = last && !revisedAfterLast ? material(last) : []
const openObjections = [...invertOpen, ...coldOpen]
const critiqueStale = last !== null && render(draft) !== lastSeen
const blocked = []
if (finalVerdict === 'stop') blocked.push(`The final pre-mortem verdict is stop with ${invertOpen.length} material objections open.`)
if (finalVerdict === 'proceed' && invertOpen.length) blocked.push(`The final pre-mortem verdict is proceed with ${invertOpen.length} material objections open.`)
if (finalVerdict === 'revise' && !revisedAfterLast && !reviseDead.some((label) => label !== 'revise:cold')) {
  blocked.push(MAX_ROUNDS === 0
    ? `maxRounds is 0 and the pre-mortem verdict is revise with ${invertOpen.length} material objections open.`
    : `Revise rounds are exhausted at maxRounds ${MAX_ROUNDS} with ${invertOpen.length} material objections open.`)
}
if (rounds[0].verdict === 'incomplete') blocked.push('The first pre-mortem critique invert:0 returned nothing.')
if (!cold) blocked.push('The cold red-team critique red-team:cold returned nothing.')
if (cold && cold.verdict === 'stop') blocked.push('The cold red-team verdict is stop.')
if (coldUnchanged) blocked.push(`The cold revise returned the plan unchanged with ${coldOpen.length} material objections open.`)
reviseDead.forEach((label) => blocked.push(`The planner stage ${label} returned nothing, so its objections stay unapplied.`))
if (critiqueStale) blocked.push('The returned plan differs from the draft the last pre-mortem critique saw.')

phase('Judge')
let judged = null
if (a.approveIf) {
  judged = await agent(`${CONTEXT}

GOAL: ${a.approveIf}
FINAL CRITIQUE VERDICT: ${finalVerdict}
OPEN OBJECTIONS:
${JSON.stringify(openObjections)}
PLAN:
${render(draft)}

Judge whether this plan meets the goal sentence and the brief. meets is true only when every clause of the goal maps to an implementation step and a validation step that proves it. meets is false when any open material objection remains or the final critique verdict is stop. Default to false. Return raw structured data only.`,
    { label: 'judge', phase: 'Judge', schema: JUDGE_SCHEMA, agentType: 'toolkit:verifier' })
  if (!judged) {
    incomplete.push('judge')
    judged = { meets: false, reasons: ['judge returned nothing'], unmetGoals: [] }
  }
}

log(`incomplete: ${incomplete.join(', ') || 'none'}`)

return {
  plan: draft.plan,
  branch: draft.branch,
  relatedTopics: draft.relatedTopics,
  discovery: { areas: areas.map((x) => x.name), uncovered },
  rounds,
  tripwires: last ? last.tripwires : [],
  walkAway: last ? last.walkAway : [],
  coldObjections: cold ? cold.objections : null,
  coldVerdict: cold ? cold.verdict : null,
  finalVerdict,
  openObjections,
  critiqueStale,
  blocked,
  approveIf: judged,
  incomplete,
}
