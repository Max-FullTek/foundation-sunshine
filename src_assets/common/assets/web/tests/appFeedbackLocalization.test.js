import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { createI18n } from 'vue-i18n'
import en from '../public/assets/locale/en.json' with { type: 'json' }
import cs from '../public/assets/locale/cs.json' with { type: 'json' }
import zh from '../public/assets/locale/zh.json' with { type: 'json' }
import { useApps } from '../composables/useApps.js'
import { AppService } from '../services/appService.js'
import { translateFallback } from '../utils/localizedMessage.js'
import { useBackground } from '../composables/useBackground.js'

const translator = () => createI18n({ legacy: false, locale: 'en', messages: { en, cs, zh } }).global

test('app action notifications follow locale changes and translate failures', async context => {
  context.mock.timers.enable({ apis: ['setTimeout'] })
  context.mock.method(console, 'error', () => {})
  context.mock.method(AppService, 'getApps', async () => [])
  context.mock.method(AppService, 'saveApps', async () => true)
  const i18n = translator()
  const apps = useApps()
  apps.init(i18n.t)
  await apps.handleSaveApp({ name: 'Test' })
  assert.equal(apps.message.value, en.apps.feedback.save_success)
  i18n.locale.value = 'cs'
  await apps.handleSaveApp({ name: 'Test' })
  assert.equal(apps.message.value, cs.apps.feedback.save_success)
  context.mock.method(AppService, 'saveApps', async () => { throw new Error('保存应用失败') })
  await apps.handleSaveApp({ name: 'Test' })
  assert.equal(apps.message.value, cs.apps.feedback.save_failed)
  assert.doesNotMatch(apps.message.value, /\p{Script=Han}/u)
  apps.handleCopySuccess()
  assert.equal(apps.message.value, cs._common.copied)
})

test('all locale catalogs supply feedback keys with matching interpolation parameters', () => {
  const directory = new URL('../public/assets/locale/', import.meta.url)
  for (const file of readdirSync(directory).filter(file => file.endsWith('.json'))) {
    const locale = JSON.parse(readFileSync(new URL(file, directory), 'utf8'))
    assert.deepEqual(Object.keys(locale.apps.feedback).sort(), Object.keys(en.apps.feedback).sort(), file)
    assert.equal(typeof locale._common.valid, 'string', file)
    for (const key of Object.keys(en.apps.feedback)) {
      const parameters = text => (text.match(/\{\w+\}/g) || []).sort()
      assert.deepEqual(parameters(locale.apps.feedback[key]), parameters(en.apps.feedback[key]), `${file}: ${key}`)
      if (!/^(zh|zh_TW|ja)\.json$/.test(file)) assert.doesNotMatch(locale.apps.feedback[key], /\p{Script=Han}/u)
    }
  }
})

test('utility validation uses English fallback or an injected translator', () => {
  const i18n = translator()
  i18n.locale.value = 'cs'
  assert.equal(AppService.validateApp({}).errors[0], en.apps.validation.required)
  assert.equal(AppService.validateApp({}, i18n.t).errors[0], cs.apps.validation.required)
  assert.equal(translateFallback('apps.feedback.cover_warning', { message: '$& {name}' }),
    '$& {name} The cover could not be saved locally; the original URL was retained.')
})

test('background file and image decode errors use the current translator', async context => {
  const previous = { FileReader: globalThis.FileReader, Image: globalThis.Image }
  context.after(() => {
    for (const key of ['FileReader', 'Image']) {
      if (previous[key] === undefined) delete globalThis[key]
      else globalThis[key] = previous[key]
    }
  })
  const i18n = translator()
  i18n.locale.value = 'cs'
  globalThis.FileReader = class { readAsDataURL() { this.onerror() } }
  const background = useBackground({ translate: i18n.t })
  await assert.rejects(background.compressImage({}), { message: cs.apps.feedback.file_read_failed })
  globalThis.FileReader = class { readAsDataURL() { this.onload({ target: { result: 'data:image/png;base64,invalid' } }) } }
  globalThis.Image = class { set src(_) { this.onerror() } }
  await assert.rejects(background.compressImage({}), { message: cs.apps.image_load_failed })
  i18n.locale.value = 'zh'
  await assert.rejects(background.compressImage({}), { message: zh.apps.image_load_failed })
})
