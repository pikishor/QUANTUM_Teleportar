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
    ['restart at 112: builders and critics finished, reports passed', {startWave: 112, skipTags: ['cars-pass2', 'landscape', 'outskirts-map', 'hero-look'], skipCritic: true,
      reports: {landscape: 'LANDSCAPE-REPORT-TEXT', 'outskirts-map': 'OUTSKIRTS-REPORT-TEXT', 'hero-look': 'HERO-REPORT-TEXT', critics: ['CRITIC-LOOK-TEXT', 'CRITIC-PLAY-TEXT']}}],
    ['restart at 113 (builders restart)', {startWave: 113}],
    ['restart at 116 only', {startWave: 116}],
    ['resume 117..121 after the owner lifts the stop', {startWave: 117, stopAfter: 121}],
  ]
  for (const [name, a] of tests) {
    const r = await sim(a)
    console.log('==', name, '->', r.labels.length, 'agents')
    console.log(r.labels.join(' '))
    if (name.startsWith('restart at 112')) {
      const p = r.prompts['w112-integrator'] || ''
      console.log('   integrator prompt has reports:', ['LANDSCAPE-REPORT-TEXT', 'OUTSKIRTS-REPORT-TEXT', 'HERO-REPORT-TEXT', 'CRITIC-LOOK-TEXT', 'CRITIC-PLAY-TEXT'].map(k => k + '=' + p.includes(k)).join(' '))
      console.log('   wave 112 watcher label:', r.labels.filter(l => l.startsWith('w112-ci')).join(','))
    }
    const late = r.labels.filter(l => /^w(117|118|119|120|121)/.test(l))
    console.log('   agents of waves 117+:', late.length, a.stopAfter ? '' : '(expected 0)')
    console.log('   result keys:', Object.keys(r.out || {}).join(','), '| r121 =', r.out && r.out.r121)
    if (r.logs.length) console.log('   logs:', r.logs.slice(0, 8).join(' | ').slice(0, 600))
  }
})().catch(e => { console.error('SIM ERROR', e); process.exit(1) })
