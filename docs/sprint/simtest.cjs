const fs = require('fs')
const src = fs.readFileSync(process.argv[2], 'utf8').replace('export const meta', 'const meta')
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor
const run = new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', 'budget', src)   // throws SyntaxError here if the body is invalid
async function sim(args) {
  const labels = [], prompts = {}
  const agent = async (prompt, opts) => {
    labels.push(opts.label + (prompt.includes('RESTART NOTICE') ? '*' : ''))
    prompts[opts.label] = prompt
    if (opts.schema) return {defects: [{id: 1, what: 'x', track: 'art'}, {id: 2, what: 'y', track: 'play'}, {id: 3, what: 'z', track: 'systems'}]}
    return 'abcdef1234 summary of ' + opts.label
  }
  const parallel = async (thunks) => Promise.all(thunks.map(t => t()))
  const logs = []
  const out = await run(args, agent, parallel, () => {}, (m) => logs.push(m), {total: null})
  return {labels, logs, prompts, out}
}
;(async () => {
  const tests = [
    ['SWITCH: restart at 114, wave 113 CI watcher only, stop after 115', {startWave: 114, stopAfter: 115, ciWave: 113, ciSha: 'deadbeef1234 W113-INTEGRATOR-SUMMARY'}],
    ['restart at 114 with the default stop (115), no CI-only wave', {startWave: 114}],
    ['restart at 115 with the default stop', {startWave: 115}],
    ['default args: fresh run, default stop', {}],
    ['restart at 116 WITHOUT stopAfter (must start nothing)', {startWave: 116}],
    ['resume at 116 after the owner lifts the stop (116 only)', {startWave: 116, stopAfter: 116}],
    ['resume 116..121 after the owner lifts the stop', {startWave: 116, stopAfter: 121}],
  ]
  for (const [name, a] of tests) {
    const r = await sim(a)
    console.log('==', name, '->', r.labels.length, 'agents')
    console.log('  ', r.labels.join(' '))
    const late = r.labels.filter(l => /^w(11[6-9]|12[01])/.test(l))
    console.log('   agents of waves 116+:', late.length)
    if (a.ciWave) { const p = r.prompts['w' + a.ciWave + '-ci-apk'] || ''; console.log('   w' + a.ciWave + '-ci-apk prompt has the sha text:', p.includes('W113-INTEGRATOR-SUMMARY'), '| w114 builders carry RESTART NOTICE:', r.labels.filter(l => /^w114-/.test(l) && l.endsWith('*')).join(',')) }
    console.log('   result keys:', Object.keys(r.out || {}).join(','))
    if (r.logs.length) console.log('   logs:', r.logs.slice(0, 6).join(' | ').slice(0, 500))
  }
})().catch(e => { console.error('SIM ERROR', e); process.exit(1) })
