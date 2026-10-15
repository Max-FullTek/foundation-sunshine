import { createScanOverrideMemorySkill, SCAN_OVERRIDE_MEMORY_SKILL_ID } from './skills/scanOverrideMemorySkill.js'
import {
  createAgent,
  createAgentSkill,
  createSkillRegistry,
  getAgentCapability,
  getAgentCapabilityIcon,
  getAgentCapabilityLabel,
  getDefaultEnabledSkillIds,
  getSelectableAgentCapabilities,
  normalizeEnabledSkillIds,
} from '../core/agentCore.js'

export function getGameResourceKey(app, index) {
  if (app?.['__scan-key']) return app['__scan-key']
  const stablePart = app?.source_path || app?.cmd || app?.name || 'app'
  return `${stablePart}-${index}`
}
export {
  getGameResourceReviewReasons,
  needsGameResourceReview,
  GAME_RESOURCE_REVIEW_THRESHOLDS,
} from './policies/reviewQueuePolicy.js'

export const GAME_LIBRARY_AGENT_ID = 'game-library-curator'

export const GAME_LIBRARY_SKILL_IDS = {
  scanOverrideMemory: SCAN_OVERRIDE_MEMORY_SKILL_ID,
}

export const GAME_LIBRARY_AGENT_CAPABILITIES = [
  {
    skillId: SCAN_OVERRIDE_MEMORY_SKILL_ID,
    stage: 'memory',
    icon: 'fa-clock-rotate-left',
    label: 'Confirmed overrides',
    labels: {
      zh: '\u5df2\u786e\u8ba4\u8986\u76d6',
    },
    required: true,
    defaultEnabled: true,
    userSelectable: false,
  },
]

export function createGameLibrarySkill(definition = {}) {
  return createAgentSkill(definition, {
    skillSubject: 'Game library skills',
    runSubject: 'Game library skill',
  })
}

const gameLibraryRegistry = createSkillRegistry({
  baseCapabilities: GAME_LIBRARY_AGENT_CAPABILITIES,
  createSkill: createGameLibrarySkill,
  duplicateMessage: 'Game library skill already registered',
})

export function registerGameLibrarySkillExtension(extension = {}) {
  return gameLibraryRegistry.registerExtension(extension)
}

export function getGameLibraryCapabilities() {
  return gameLibraryRegistry.getCapabilities()
}

export function getGameLibraryCapability(skillId, capabilities = getGameLibraryCapabilities()) {
  return getAgentCapability(skillId, capabilities)
}

export function getGameLibrarySelectableCapabilities(capabilities = getGameLibraryCapabilities()) {
  return getSelectableAgentCapabilities(capabilities)
}

export function getDefaultEnabledGameLibrarySkillIds(capabilities = getGameLibraryCapabilities()) {
  return getDefaultEnabledSkillIds(capabilities)
}

export function normalizeGameLibrarySkillIds(skillIds, capabilities = getGameLibraryCapabilities()) {
  return normalizeEnabledSkillIds(skillIds, capabilities)
}

export function getGameLibraryCapabilityIcon(skillId, capabilities = getGameLibraryCapabilities()) {
  return getAgentCapabilityIcon(skillId, capabilities)
}

export function getGameLibraryCapabilityLabel(skillId, options = {}) {
  return getAgentCapabilityLabel(skillId, {
    ...options,
    capabilities: options.capabilities || getGameLibraryCapabilities(),
  })
}

export function createDefaultGameLibrarySkills(options = {}) {
  return [
    createScanOverrideMemorySkill(options.memory),
    ...gameLibraryRegistry.getExtensionSkills(),
  ]
}

export function createGameLibraryCuratorAgent(options = {}) {
  const skills = options.skills || createDefaultGameLibrarySkills(options.skillsOptions)

  return createAgent({
    id: GAME_LIBRARY_AGENT_ID,
    skills,
    createContext(apps, runOptions) {
      return {
        apps,
        events: [],
        stats: {},
        options: runOptions,
      }
    },
  })
}

export async function runGameLibraryCuratorAgent(apps, options = {}) {
  return createGameLibraryCuratorAgent(options.agentOptions).run(apps, options)
}

const memorySkill = createScanOverrideMemorySkill()

export function applyGameLibraryOverrides(apps) {
  return memorySkill.apply(apps)
}

export function rememberGameLibraryApp(scannedApp, finalApp) {
  return memorySkill.remember(scannedApp, finalApp)
}
