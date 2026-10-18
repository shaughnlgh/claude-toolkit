// The script body uses top-level await and return, so it compiles inside an AsyncFunction.
import { readFileSync } from 'node:fs'

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const source = readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const flow = new AsyncFunction('args', 'agent', 'pipeline', 'phase', 'log', source)

const ARGS = { brief: 'Add a widget export.', repoRoot: '/repo', repoName: 'demo', planName: 'widget-export', recallHits: 'none' }
const SECTION_KEYS = ['objective', 'plainLanguageSummary', 'currentContext', 'assumptions', 'affectedFiles', 'implementationSteps', 'validationSteps', 'risks', 'rollbackNotes', 'openQuestions', 'relatedTopics']
const draft = (tag) => ({ plan: Object.fromEntries(SECTION_KEYS.map((k) => [k, `${k} ${tag}`])), branch: 'feat/widget-export', relatedTopics: ['widgets'] })
const objection = (claim, isMaterial) => ({ section: 'Risks', claim, evidence: 'src/widget.js:10', fix: 'Add a guard.', material: isMaterial })
const critiqueOf = (verdict, objections) => ({ verdict, objections, tripwires: ['t'], walkAway: ['w'] })
const PROCEED = critiqueOf('proceed', [])
const REVISE = critiqueOf('revise', [objection('revise claim', true)])

const DEFAULTS = {
  'discover:scope': { areas: [{ name: 'alpha', question: 'Q1?', paths: ['/repo/a'] }, { name: 'beta', question: 'Q2?', paths: ['/repo/b'] }] },
  'discover:alpha': { facts: [{ claim: 'a', ref: 'a.js:1' }], gaps: [], risks: [], reuse: 'none' },
  'discover:beta': { facts: [{ claim: 'b', ref: 'b.js:1' }], gaps: [], risks: [], reuse: 'none' },
  'discover:whole-brief': { facts: [{ claim: 'w', ref: 'w.js:1' }], gaps: [], risks: [], reuse: 'none' },
  draft: draft('v0'),
  'invert:0': PROCEED,
  'invert:1': PROCEED,
  'invert:2': PROCEED,
  'revise:1': draft('v1'),
  'revise:2': draft('v2'),
  'red-team:cold': PROCEED,
  'revise:cold': draft('cold'),
  judge: { meets: true, reasons: ['ok'], unmetGoals: [] },
}

// Runs the flow with per-label overrides. A null override is a dead stage.
async function run(overrides = {}, args = ARGS) {
  const script = { ...DEFAULTS, ...overrides }
  const prompts = {}
  const agent = async (prompt, opts) => {
    prompts[opts.label] = prompt
    return script[opts.label] ?? null
  }
  const pipeline = async (items, ...stages) => {
    const out = []
    for (const item of items) {
      let value = item
      try {
        for (const stage of stages) value = await stage(value)
      } catch (e) {
        value = null
      }
      out.push(value)
    }
    return out
  }
  try {
    const result = await flow(args, agent, pipeline, () => {}, () => {})
    return { result, prompts }
  } catch (error) {
    return { error, prompts }
  }
}

const same = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected)
const STOP = critiqueOf('stop', [objection('fatal claim', true), objection('minor claim', false)])
const COLD = critiqueOf('revise', [objection('cold claim', true)])

const cases = [
  ['scope explorer dead falls back to one whole-brief area and marks incomplete', async () => {
    const { result } = await run({ 'discover:scope': null })
    return same({ areas: result.discovery.areas, incomplete: result.incomplete }, { areas: ['whole-brief'], incomplete: ['discover:scope'] })
  }],
  ['one area explorer dead lands in uncovered', async () => {
    const { result } = await run({ 'discover:beta': null })
    return same(result.discovery.uncovered, ['beta'])
  }],
  ['dead draft throws', async () => {
    const { error } = await run({ draft: null })
    return String(error && error.message).includes('planner returned no draft')
  }],
  ['args as a JSON string parse', async () => {
    const { result } = await run({}, JSON.stringify(ARGS))
    return same(result.plan.objective, 'objective v0')
  }],
  ['missing arg key throws', async () => {
    const { error } = await run({}, { ...ARGS, planName: undefined })
    return String(error && error.message).includes('plan-builder requires args')
  }],
  ['maxRounds as the string "0" throws', async () => {
    const { error } = await run({}, { ...ARGS, maxRounds: '0' })
    return String(error && error.message).includes('maxRounds must be a non-negative integer')
  }],
  ['two areas with the same name get distinct explorer labels', async () => {
    const twin = { areas: [{ name: 'alpha', question: 'Q1?', paths: ['/repo/a'] }, { name: 'alpha', question: 'Q2?', paths: ['/repo/b'] }] }
    const { prompts } = await run({ 'discover:scope': twin })
    return same(Object.keys(prompts).filter((k) => k.startsWith('discover:alpha')), ['discover:alpha:0', 'discover:alpha:1'])
  }],
  ['maxRounds 0 skips revise and reports finalVerdict revise with blocked non-empty', async () => {
    const { result, prompts } = await run({ 'invert:0': REVISE }, { ...ARGS, maxRounds: 0 })
    return same({ revised: 'revise:1' in prompts, finalVerdict: result.finalVerdict, blocked: result.blocked.length > 0 }, { revised: false, finalVerdict: 'revise', blocked: true })
  }],
  ['stop verdict sets finalVerdict stop, openObjections to its material objections, blocked non-empty', async () => {
    const { result } = await run({ 'invert:0': STOP })
    return same({ finalVerdict: result.finalVerdict, openObjections: result.openObjections, blocked: result.blocked.length > 0 }, { finalVerdict: 'stop', openObjections: [objection('fatal claim', true)], blocked: true })
  }],
  ['revise exhausted at maxRounds 2 with a lingering revise verdict reports openObjections and blocked', async () => {
    const lingering = critiqueOf('revise', [objection('lingering claim', true)])
    const { result } = await run({ 'invert:0': REVISE, 'invert:1': REVISE, 'invert:2': lingering })
    return same({ openObjections: result.openObjections, blocked: result.blocked.length > 0 }, { openObjections: [objection('lingering claim', true)], blocked: true })
  }],
  ['invert:0 dead sets blocked', async () => {
    const { result } = await run({ 'invert:0': null })
    return result.blocked.length > 0
  }],
  ['revise:1 dead mid-loop sets blocked', async () => {
    const { result } = await run({ 'invert:0': REVISE, 'revise:1': null })
    return result.blocked.length > 0
  }],
  ['red-team:cold dead sets coldVerdict null and blocked', async () => {
    const { result } = await run({ 'red-team:cold': null })
    return same({ coldVerdict: result.coldVerdict, blocked: result.blocked.length > 0 }, { coldVerdict: null, blocked: true })
  }],
  ['revise:cold dead keeps cold material objections in openObjections', async () => {
    const { result } = await run({ 'red-team:cold': COLD, 'revise:cold': null })
    return same(result.openObjections, [objection('cold claim', true)])
  }],
  ['successful cold revise sets critiqueStale true and blocked', async () => {
    const { result } = await run({ 'red-team:cold': COLD })
    return same({ critiqueStale: result.critiqueStale, blocked: result.blocked.length > 0 }, { critiqueStale: true, blocked: true })
  }],
  ['successful revise then dead critique sets critiqueStale true', async () => {
    const { result } = await run({ 'invert:0': REVISE, 'invert:1': null })
    return result.critiqueStale === true
  }],
  ['successful revise then dead critique leaves the applied objections out of openObjections', async () => {
    const { result } = await run({ 'invert:0': REVISE, 'invert:1': null })
    return same(result.openObjections, [])
  }],
  ['cold revise returning the plan unchanged keeps cold material objections open and sets blocked', async () => {
    const { result } = await run({ 'red-team:cold': COLD, 'revise:cold': draft('v0') })
    return same({ openObjections: result.openObjections, blocked: result.blocked.length > 0 }, { openObjections: [objection('cold claim', true)], blocked: true })
  }],
  ['cold stop verdict with no objections sets blocked', async () => {
    const { result } = await run({ 'red-team:cold': critiqueOf('stop', []) })
    return result.blocked.length > 0
  }],
  ['proceed verdict with a material objection reports it in openObjections and sets blocked', async () => {
    const { result } = await run({ 'invert:0': critiqueOf('proceed', [objection('ignored claim', true)]) })
    return same({ openObjections: result.openObjections, blocked: result.blocked.length > 0 }, { openObjections: [objection('ignored claim', true)], blocked: true })
  }],
  ['revise exhausted plus revise:cold dead reports both the exhausted and the dead cold revise', async () => {
    const { result } = await run({ 'invert:0': REVISE, 'invert:1': REVISE, 'invert:2': REVISE, 'red-team:cold': COLD, 'revise:cold': null })
    return same({ exhausted: result.blocked.some((b) => b.includes('exhausted')), coldDead: result.blocked.some((b) => b.includes('revise:cold')) }, { exhausted: true, coldDead: true })
  }],
  ['clean proceed run returns blocked empty, openObjections empty, critiqueStale false', async () => {
    const { result } = await run()
    return same({ blocked: result.blocked, openObjections: result.openObjections, critiqueStale: result.critiqueStale }, { blocked: [], openObjections: [], critiqueStale: false })
  }],
  ['approveIf absent returns approveIf null', async () => {
    const { result } = await run()
    return result.approveIf === null
  }],
  ['judge dead returns meets false and incomplete judge', async () => {
    const { result } = await run({ judge: null }, { ...ARGS, approveIf: 'Exports widgets as CSV.' })
    return same({ meets: result.approveIf.meets, incomplete: result.incomplete }, { meets: false, incomplete: ['judge'] })
  }],
  ['judge prompt contains the FINAL CRITIQUE VERDICT line', async () => {
    const { prompts } = await run({}, { ...ARGS, approveIf: 'Exports widgets as CSV.' })
    return prompts.judge.includes('\nFINAL CRITIQUE VERDICT: proceed\n')
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
