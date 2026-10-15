import test from 'node:test'
import assert from 'node:assert/strict'

import {
  createGameLibraryCuratorAgent,
  createGameLibrarySkill,
  GAME_LIBRARY_AGENT_CAPABILITIES,
  GAME_LIBRARY_SKILL_IDS,
  getDefaultEnabledGameLibrarySkillIds,
  getGameLibraryCapabilities,
  getGameLibraryCapabilityIcon,
  getGameLibraryCapabilityLabel,
  getGameLibrarySelectableCapabilities,
  getGameResourceReviewReasons,
  normalizeGameLibrarySkillIds,
  needsGameResourceReview,
  registerGameLibrarySkillExtension,
} from '../utils/agents/gameLibrary/gameLibraryCuratorAgent.js'
import { getGameResourceKey } from '../utils/agents/gameLibrary/gameLibraryCuratorAgent.js'
import { createScanOverrideMemorySkill } from '../utils/agents/gameLibrary/skills/scanOverrideMemorySkill.js'

test('createGameLibrarySkill normalizes extension skill definitions', async () => {
  const skill = createGameLibrarySkill({
    id: ' game.test.skill ',
    async run(context) {
      return context
    },
  })

  assert.equal(skill.id, 'game.test.skill')
  assert.equal(skill.type, 'extension')
  assert.equal(skill.label, 'game.test.skill')

  await assert.doesNotReject(() => skill.run({ apps: [] }))
})

test('createGameLibrarySkill rejects invalid skill definitions', () => {
  assert.throws(() => createGameLibrarySkill({ run() {} }), /non-empty id/)
  assert.throws(() => createGameLibrarySkill({ id: 'game.test.invalid' }), /run\(context\)/)
})

test('game resource keys stay unique for duplicate launch metadata', () => {
  const first = { source_path: 'C:/Games/Same', cmd: 'same.exe' }
  const second = { source_path: 'C:/Games/Same', cmd: 'same.exe' }

  assert.notEqual(getGameResourceKey(first, 0), getGameResourceKey(second, 1))
  assert.equal(getGameResourceKey({ ...first, '__scan-key': 'scan-1-0' }, 7), 'scan-1-0')
})

test('game library curator supports registering extension skills', async () => {
  const calls = []
  const unregister = registerGameLibrarySkillExtension({
    skill: {
      id: 'game.test.annotate',
      type: 'metadata',
      label: 'Test annotation',
      async run(context) {
        calls.push('extension')
        return {
          ...context,
          apps: context.apps.map((app) => ({ ...app, 'test-extension': true })),
        }
      },
    },
    capability: {
      icon: 'fa-vial',
      defaultEnabled: false,
      labels: { zh: '\u6d4b\u8bd5\u6807\u6ce8' },
    },
  })

  try {
    assert.equal(getGameLibraryCapabilityIcon('game.test.annotate'), 'fa-vial')
    assert.equal(getGameLibraryCapabilityLabel('game.test.annotate', { locale: 'zh-CN' }), '\u6d4b\u8bd5\u6807\u6ce8')
    assert.ok(getGameLibrarySelectableCapabilities().some((capability) => capability.skillId === 'game.test.annotate'))
    assert.ok(!getDefaultEnabledGameLibrarySkillIds().includes('game.test.annotate'))

    const result = await createGameLibraryCuratorAgent().run([{ name: 'Raw Game' }], {
      enabledSkills: ['game.test.annotate'],
    })

    assert.deepEqual(calls, ['extension'])
    assert.equal(result.apps[0]['test-extension'], true)
  } finally {
    unregister()
  }

  assert.ok(!getGameLibraryCapabilities().some((capability) => capability.skillId === 'game.test.annotate'))
})

test('game library curator rejects duplicate extension skills', () => {
  assert.throws(
    () => registerGameLibrarySkillExtension({
      skill: {
        id: GAME_LIBRARY_SKILL_IDS.scanOverrideMemory,
        async run(context) {
          return context
        },
      },
    }),
    /already registered/
  )
})

test('game resource review policy flags low confidence and missing cover', () => {
  const app = {
    name: 'Maybe Game',
    'is-game': true,
    'canonical-name': '',
    'ai-confidence': 0.5,
  }

  assert.equal(needsGameResourceReview(app), true)
  assert.deepEqual(getGameResourceReviewReasons(app, { locale: 'en' }), [
    'Low name confidence 50%',
    'Missing canonical name',
    'Missing cover',
  ])
  assert.deepEqual(getGameResourceReviewReasons(app, { locale: 'zh-CN' }), [
    '\u540d\u79f0\u7f6e\u4fe1\u5ea6 50%',
    '\u7f3a\u5c11\u89c4\u8303\u540d\u79f0',
    '\u7f3a\u5c11\u5c01\u9762',
  ])
})

test('game resource review policy ignores blank numeric confidence fields', () => {
  const app = {
    name: 'Known Game',
    'is-game': true,
    'canonical-name': 'Known Game',
    'image-path': 'known.jpg',
    'ai-confidence': '',
    'ai-cover-confidence': '',
    'cover-match-confidence': '',
  }

  assert.deepEqual(getGameResourceReviewReasons(app, { locale: 'en' }), [])
  assert.equal(needsGameResourceReview(app), false)
})
