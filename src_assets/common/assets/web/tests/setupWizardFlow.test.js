import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import { parse, compileScript } from '@vue/compiler-sfc'
import { apiFetch, apiJson } from '../utils/apiFetch.js'
import { saveSetupWizardConfig, saveSetupWizardLocale } from '../services/setupWizardService.js'

// Execute the real SFC Options API script, replacing only its environment imports.
const source = readFileSync(new URL('../components/SetupWizard.vue', import.meta.url), 'utf8')
const { descriptor } = parse(source)
const { scriptAst } = compileScript(descriptor, { id: 'setup-wizard-test' })
let script = descriptor.script.content
for (const node of [...scriptAst].reverse()) {
  if (node.type === 'ImportDeclaration') script = script.slice(0, node.start) + script.slice(node.end)
}
script = script.replace('export default', 'globalThis.component =')

function createWizard(t, config = {}, postStatus = 'true') {
  const requests = []
  const redirects = []
  const events = []
  const intervals = new Map()
  const timeouts = new Map()
  const originalFetch = globalThis.fetch
  t.after(() => { globalThis.fetch = originalFetch })
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    if (url === '/api/restart') {
      return new Promise((resolve, reject) => options.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }))
    }
    return Response.json(options.method === 'POST'
      ? { status: postStatus, error: 'disk unavailable' }
      : config)
  }
  const context = vm.createContext({
    apiFetch, apiJson, saveSetupWizardConfig, saveSetupWizardLocale,
    ConfirmDialog: {}, detectSystemLocale: () => 'zh_TW', getWizardLocale: locale => locale,
    trackEvents: { userAction() {}, pageView() {} }, console: { error() {} },
    writeInterfaceLocale() {}, SETUP_WIZARD_LANGUAGE_SAVED_KEY: 'saved',
    window: { location: { reload: () => redirects.push('reload'), replace: path => redirects.push(path) }, sessionStorage: { setItem() {} } },
    AbortController,
    setInterval: fn => { intervals.set(1, fn); return 1 },
    clearInterval: id => intervals.delete(id),
    setTimeout: fn => { timeouts.set(1, fn); return 1 },
    clearTimeout: id => timeouts.delete(id),
  })
  vm.runInContext(script, context)
  const component = context.component
  const wizard = { hasLocale: false, vddReady: false, vddInstalling: false, vddStatusLoading: true, $t: key => key, $emit: (...args) => events.push(args) }
  Object.assign(wizard, component.data.call(wizard))
  for (const [key, method] of Object.entries(component.methods)) wizard[key] = method.bind(wizard)
  for (const [key, getter] of Object.entries(component.computed)) Object.defineProperty(wizard, key, { get: getter.bind(wizard) })
  return { wizard, requests, redirects, events, intervals, component }
}

test('display skip completes without VDD, preserving display settings and unrelated config', async t => {
  const original = { output_name: 'physical-id', display_device_prep: 'no_operation', locale: 'de', port: 48000, setup_wizard_completed: false }
  const { wizard, requests, events } = createWizard(t, original)
  wizard.selectedLocale = null
  wizard.selectedAdapter = 'GPU'
  wizard.currentStep = 3
  assert.equal(wizard.selectedDisplay, null)
  assert.equal(wizard.canProceed, false)
  await wizard.skipDisplayConfiguration()
  const posted = JSON.parse(requests[1].options.body)
  assert.deepEqual(posted, { ...original, adapter_name: 'GPU', setup_wizard_completed: true })
  assert.equal(wizard.currentStep, 5)
  assert.equal(events.length, 0, 'completion screen stays mounted until leaving')
})

test('display skip does not add missing display fields or ZakoHDR', async t => {
  const { wizard, requests } = createWizard(t, { locale: 'en' })
  await wizard.skipDisplayConfiguration()
  const posted = JSON.parse(requests[1].options.body)
  assert.equal(Object.hasOwn(posted, 'output_name'), false)
  assert.equal(Object.hasOwn(posted, 'display_device_prep'), false)
})

test('physical display can proceed despite a pending VDD probe and saves the explicit selection', async t => {
  const { wizard, requests } = createWizard(t, { output_name: 'old', display_device_prep: 'old' })
  wizard.currentStep = 3
  wizard.selectedDisplay = 'physical-new'
  assert.equal(wizard.canProceed, true)
  await wizard.nextStep()
  assert.equal(wizard.currentStep, 4)
  await wizard.nextStep()
  assert.equal(wizard.currentStep, 5)
  assert.equal(JSON.parse(requests[1].options.body).output_name, 'physical-new')
})

test('unavailable VDD selection cannot advance or save', async t => {
  const { wizard, requests } = createWizard(t)
  wizard.currentStep = 3
  wizard.selectedDisplay = 'ZakoHDR'
  assert.equal(wizard.canProceed, false)
  await wizard.nextStep()
  await wizard.saveConfiguration()
  assert.equal(requests.some(request => request.options.method === 'POST'), false)
  assert.equal(wizard.currentStep, 3)
  assert.ok(wizard.saveError)
})

for (const action of ['saveLanguage', 'skipDisplayConfiguration', 'confirmSkipWizard']) {
  test(action + ' keeps wizard open on backend rejection', async t => {
    const { wizard, redirects, events } = createWizard(t, {}, 'false')
    wizard.currentStep = action === 'saveLanguage' ? 1 : 3
    await wizard[action]()
    assert.match(wizard.saveError, /disk unavailable/)
    assert.equal(wizard.saving, false)
    assert.equal(redirects.length, 0)
    assert.equal(events.length, 0)
    assert.notEqual(wizard.currentStep, 5)
  })
}

test('skip all preserves config and exits to config without forced setup query', async t => {
  const original = { output_name: 'existing', display_device_prep: 'ensure_primary', adapter_name: 'old-gpu', locale: 'de' }
  const { wizard, requests, redirects, events } = createWizard(t, original)
  await wizard.confirmSkipWizard()
  assert.deepEqual(JSON.parse(requests[1].options.body), { ...original, setup_wizard_completed: true })
  assert.deepEqual(redirects, ['/config'])
  assert.equal(events[0][0], 'setup-complete')
})

for (const immediate of [false, true]) {
  test('hung restart can exit via ' + (immediate ? 'go now' : 'countdown'), async t => {
    const { wizard, requests, redirects, intervals, events } = createWizard(t)
    const pending = wizard.triggerRestartAndRedirect()
    assert.equal(wizard.showRestartModal, true)
    await wizard.triggerRestartAndRedirect()
    assert.equal(requests.length, 1)
    if (immediate) wizard.skipRestartCountdown()
    else for (let i = 0; i < 8; i++) intervals.get(1)()
    await pending
    assert.deepEqual(redirects, ['/apps'])
    assert.equal(requests[0].options.signal.aborted, true)
    assert.equal(intervals.size, 0)
    assert.equal(events[0][0], 'setup-complete')
  })
}
