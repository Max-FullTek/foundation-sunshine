import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'
import { computed, ref } from 'vue'
import { APP_CONSTANTS } from '../utils/constants.js'

const source = (await readFile(new URL('../composables/useApps.js', import.meta.url), 'utf8'))
  .replace(/^import .*\n/gm, '')
  .replace('export function useApps()', 'function useApps()')

function harness(initialApps, fail = false) {
  const saves = []
  const context = vm.createContext({
    computed, ref, APP_CONSTANTS, ENV_VARS_CONFIG: {},
    translateFallback: key => key,
    deepClone: value => JSON.parse(JSON.stringify(value)),
    debounce: fn => fn,
    trackEvents: { userAction() {} },
    setTimeout() {},
    console: { error() {} },
    AppService: {
      getApps: async () => structuredClone(initialApps),
      searchApps: apps => apps,
      saveApps: async apps => {
        saves.push(JSON.parse(JSON.stringify(apps)))
        if (fail) throw new Error('Save rejected')
      },
    },
  })
  vm.runInContext(source, context)
  return { state: context.useApps(), saves }
}

test('dropping a single card without changing order stays silent and does not save', async () => {
  const { state, saves } = harness([{ name: 'Desktop', cmd: '' }])
  await state.loadApps()
  state.onDragStart()
  await state.onDragEnd()
  assert.equal(state.isDragging.value, false)
  assert.equal(state.message.value, '')
  assert.equal(saves.length, 0)
})

test('a changed app order saves once, then dropping it again stays silent', async () => {
  const { state, saves } = harness([{ name: 'Desktop' }, { name: 'Game' }])
  await state.loadApps()
  state.apps.value.reverse()
  await state.onDragEnd()
  assert.deepEqual(saves[0].map(app => app.name), ['Game', 'Desktop'])
  assert.equal(state.hasUnsavedChanges.value, false)
  state.message.value = ''
  await state.onDragEnd()
  assert.equal(saves.length, 1)
  assert.equal(state.message.value, '')
})

test('failed reorder saves retain pending changes and show the error', async () => {
  const { state, saves } = harness([{ name: 'Desktop' }, { name: 'Game' }], true)
  await state.loadApps()
  state.apps.value.reverse()
  await state.onDragEnd()
  assert.equal(saves.length, 1)
  assert.equal(state.hasUnsavedChanges.value, true)
  assert.equal(state.isSaving.value, false)
  assert.equal(state.message.value, 'apps.feedback.save_failed')
})
