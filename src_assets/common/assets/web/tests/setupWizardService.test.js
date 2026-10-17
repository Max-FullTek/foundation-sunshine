import test from 'node:test'
import assert from 'node:assert/strict'

import { saveSetupWizardLocale, saveSetupWizardConfig } from '../services/setupWizardService.js'

test('setup wizard language save preserves the current configuration', async () => {
  const originalFetch = globalThis.fetch
  const requests = []

  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })

    if (requests.length === 1) {
      return new Response(JSON.stringify({
        locale: 'en',
        output_name: 'ZakoHDR',
        port: 40989,
        setup_wizard_completed: false,
      }), { status: 200 })
    }

    return new Response(JSON.stringify({ status: true }), { status: 200 })
  }

  try {
    const response = await saveSetupWizardLocale('zh_TW')

    assert.equal(response.ok, true)
    assert.equal(requests.length, 2)
    assert.equal(requests[0].url, '/api/config')
    assert.equal(requests[0].options.method, undefined)
    assert.equal(requests[1].url, '/api/config')
    assert.equal(requests[1].options.method, 'POST')
    assert.equal(requests[1].options.headers.get('Content-Type'), 'application/json')
    assert.deepEqual(JSON.parse(requests[1].options.body), {
      locale: 'zh_TW',
      output_name: 'ZakoHDR',
      port: 40989,
      setup_wizard_completed: false,
    })
  } finally {
    globalThis.fetch = originalFetch
  }
})

for (const status of [false, 'false']) {
  test('wizard rejects HTTP 200 with backend failure ' + JSON.stringify(status), async (t) => {
    const originalFetch = globalThis.fetch
    t.after(() => { globalThis.fetch = originalFetch })
    globalThis.fetch = async () => Response.json({ status, error: 'failed to persist configuration' })
    await assert.rejects(saveSetupWizardConfig({}), /failed to persist configuration/)
    await assert.rejects(saveSetupWizardLocale('zh_TW'), /failed to persist configuration/)
  })
}
for (const status of [true, 'true']) {
  test('wizard accepts backend success ' + JSON.stringify(status), async (t) => {
    const originalFetch = globalThis.fetch
    t.after(() => { globalThis.fetch = originalFetch })
    globalThis.fetch = async () => Response.json({ status })
    assert.equal((await saveSetupWizardConfig({})).ok, true)
  })
}
test('wizard rejects HTTP errors, missing status and invalid JSON', async (t) => {
  const originalFetch = globalThis.fetch
  t.after(() => { globalThis.fetch = originalFetch })
  for (const response of [Response.json({ error: 'denied' }, { status: 403 }), Response.json({}), new Response('<html>login</html>')]) {
    globalThis.fetch = async () => response
    await assert.rejects(saveSetupWizardConfig({}))
  }
})
