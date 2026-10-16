<template>
  <div class="setup-container">
    <Teleport to="body">
      <TransitionGroup
        v-if="visibleCompletionNotices.length"
        name="setup-toast"
        tag="div"
        class="setup-completion-toasts"
        aria-live="polite"
        aria-atomic="false"
      >
        <div
          v-for="notice in visibleCompletionNotices"
          :key="notice.id"
          class="setup-completion-toast"
          :class="`setup-completion-toast-${notice.tone}`"
          role="status"
        >
          <i :class="notice.icon" aria-hidden="true"></i>
          <span :class="{ 'setup-completion-toast-title': notice.emphasis }">
            {{ $t(notice.messageKey) }}
          </span>
          <button
            type="button"
            class="setup-completion-toast-close"
            :aria-label="$t('_common.close')"
            @click="dismissCompletionNotice(notice.id)"
          >
            <i class="fas fa-times" aria-hidden="true"></i>
          </button>
        </div>
      </TransitionGroup>
    </Teleport>

    <div class="setup-card">
      <div class="setup-header">
        <div class="setup-brand"><img src="/images/logo-sunshine-256.png" height="48" alt=""><span>Foundation Sunshine Lite</span></div>
        <h1>{{ shellT.setupLite.title }}</h1>
      </div>

      <div class="setup-content">
        <!-- 步骤指示器 -->
        <div class="step-indicator">
          <div class="step" :class="{ active: currentStep === 1, completed: currentStep > 1 }">
            <div class="step-number">1</div>
            <span>{{ $t('setup.step0_title') }}</span>
          </div>
          <div class="step-connector"></div>
          <div class="step" :class="{ active: currentStep === 2, completed: currentStep > 2 }">
            <div class="step-number">2</div>
            <span>{{ $t('setup.step2_title') }}</span>
          </div>
          <div class="step-connector"></div>
          <div class="step" :class="{ active: currentStep === 3, completed: currentStep > 3 }">
            <div class="step-number">3</div>
            <span>{{ $t('setup.step1_title') }}</span>
          </div>
          <div class="step-connector"></div>
          <div class="step" :class="{ active: currentStep === 4, completed: currentStep > 4 }">
            <div class="step-number">4</div>
            <span>{{ $t('setup.step3_title') }}</span>
          </div>
          <div class="step-connector"></div>
          <div class="step" :class="{ active: currentStep === 5 }">
            <div class="step-number">5</div>
            <span>{{ $t('setup.step4_title') }}</span>
          </div>
        </div>

        <!-- 步骤内容 -->
        <div class="step-content">
          <!-- 步骤 1: 选择语言 -->
          <div v-if="currentStep === 1">
            <h3 class="mb-4">{{ $t('setup.step0_description') }}</h3>
            
            <button v-for="language in wizardLocales" :key="language.value" type="button" class="option-card language-option"
                    :class="{ selected: selectedLocale === language.value }" :aria-pressed="selectedLocale === language.value"
                    @click="selectedLocale = language.value">
              <i class="fas fa-language" aria-hidden="true"></i><span>{{ language.label }}</span>
            </button>
          </div>

          <!-- 步骤 2: 选择显卡 -->
          <div v-else-if="currentStep === 2">
            <h3 class="mb-4">{{ $t('setup.step2_description') }}</h3>
            
            <div class="mb-3">
              <label for="adapterSelect" class="form-label adapter-label">{{ $t('setup.select_adapter') }}</label>
              <select id="adapterSelect" 
                      class="form-select form-select-large" 
                      v-model="selectedAdapter">
                <option value="">{{ $t('setup.choose_adapter') }}</option>
                <option v-for="adapter in uniqueAdapters" :key="adapter.name" :value="adapter.name">
                  {{ adapter.name }}
                </option>
              </select>
            </div>

              <div v-if="selectedAdapter" class="adapter-info">
                <h5>
                  <i class="fas fa-info-circle"></i>
                  {{ $t('setup.adapter_info') }}
                </h5>
                <p><strong>{{ $t('setup.selected_adapter') }}:</strong> {{ selectedAdapter }}</p>
              </div>

              <!-- GPU选择提示框 -->
              <div class="form-text mt-3 adapter-hint-box" v-html="$t('config.adapter_name_desc_windows')"></div>
          </div>

          <!-- 步骤 3: 选择串流显示器 -->
          <div v-else-if="currentStep === 3">
            <h3 class="mb-4">{{ $t('setup.step1_description') }}</h3>
            <p class="vdd-intro-text mb-4">{{ $t('setup.step1_vdd_intro') }}</p>
            
            <!-- 基地显示器标题 -->
            <h5 class="my-3 physical-display-title">
              <i class="fas fa-tv"></i>
              {{ $t('setup.base_display_title') }}
            </h5>
            <!-- 虚拟显示器选项 -->
            <div class="option-card"
                 :class="{ selected: isVirtualDisplay, disabled: !vddReady }"
                 :aria-disabled="!vddReady"
                 @click="selectVirtualDisplay">
              <div class="d-flex align-items-center">
                <div class="option-icon-small">
                  <i class="fas fa-tv"></i>
                </div>
                <div class="flex-grow-1">
                  <h4>{{ $t('setup.virtual_display') }}</h4>
                  <p>{{ $t('setup.virtual_display_desc') }}</p>
                </div>
              </div>
            </div>

            <div v-if="!vddReady" class="alert alert-warning vdd-wizard-prerequisite">
              <strong>{{ $t('setup.vdd_driver_required') }}</strong>
              <p class="mb-2 mt-1">
                {{ canManageVdd ? $t('setup.vdd_driver_desktop_hint') : $t('setup.vdd_driver_browser_hint') }}
              </p>
              <small v-if="vddStatusError" class="d-block">{{ vddStatusError }}</small>
              <small v-else-if="vddStatus.state !== 'unknown'" class="d-block">
                {{ $t(`config.vdd_driver_state_${vddStatus.state}`) }}
              </small>
            </div>

            <!-- 物理显示器列表 -->
            <div v-if="physicalDisplayDevices.length > 0">
              <h5 class="my-3 physical-display-title">
                <i class="fas fa-desktop"></i>
                {{ $t('setup.physical_display') }}
              </h5>
              <div class="option-card" 
                   v-for="device in physicalDisplayDevices"
                   :key="device.device_id"
                   :class="{ selected: selectedDisplay === device.device_id }"
                   @click="selectedDisplay = device.device_id">
                <div class="d-flex align-items-center">
                  <div class="option-icon-small">
                    <i class="fas fa-desktop"></i>
                  </div>
                  <div class="flex-grow-1">
                    <h4>{{ getDisplayName(device) }}</h4>
                    <p>{{ getDisplayInfo(device) }}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 步骤 4: 选择显示器组合策略 -->
          <div v-else-if="currentStep === 4">
            <h3 class="mb-4">{{ $t('setup.step3_description') }}</h3>
            
            <!-- 显示器组合策略（VDD/物理模式统一） -->
              <div class="option-card-compact"
                   :class="{ selected: displayDevicePrep === 'ensure_only_display' }"
                   @click="displayDevicePrep = 'ensure_only_display'">
                <div class="option-icon-compact"><i class="fas fa-desktop"></i></div>
                <div class="option-text">
                  <h4>{{ $t('setup.step3_ensure_only_display') }}</h4>
                  <p>{{ $t('setup.step3_ensure_only_display_desc') }}</p>
                </div>
              </div>

              <div class="option-card-compact" 
                   :class="{ selected: displayDevicePrep === 'ensure_primary' }"
                   @click="displayDevicePrep = 'ensure_primary'">
                <div class="option-icon-compact"><i class="fas fa-star"></i></div>
                <div class="option-text">
                  <h4>{{ $t('setup.step3_ensure_primary') }}</h4>
                  <p>{{ $t('setup.step3_ensure_primary_desc') }}</p>
                </div>
              </div>

              <div class="option-card-compact" 
                   :class="{ selected: displayDevicePrep === 'ensure_active' }"
                   @click="displayDevicePrep = 'ensure_active'">
                <div class="option-icon-compact"><i class="fas fa-check-circle"></i></div>
                <div class="option-text">
                  <h4>{{ $t('setup.step3_ensure_active') }}</h4>
                  <p>{{ $t('setup.step3_ensure_active_desc') }}</p>
                </div>
              </div>

              <div class="option-card-compact" 
                   :class="{ selected: displayDevicePrep === 'ensure_secondary' }"
                   @click="displayDevicePrep = 'ensure_secondary'">
                <div class="option-icon-compact"><i class="fas fa-columns"></i></div>
                <div class="option-text">
                  <h4>{{ $t('setup.step3_ensure_secondary') }}</h4>
                  <p>{{ $t('setup.step3_ensure_secondary_desc') }}</p>
                </div>
              </div>

              <div class="option-card-compact" 
                   :class="{ selected: displayDevicePrep === 'no_operation' }"
                   @click="displayDevicePrep = 'no_operation'">
                <div class="option-icon-compact"><i class="fas fa-hand-paper"></i></div>
                <div class="option-text">
                  <h4>{{ $t('setup.step3_no_operation') }}</h4>
                  <p>{{ $t('setup.step3_no_operation_desc') }}</p>
                </div>
              </div>
          </div>

          <!-- 步骤 5: 完成 -->
          <div v-else-if="currentStep === 5">
            <div>
              <div class="alert alert-danger" v-if="saveError">
                <i class="fas fa-exclamation-triangle"></i>
                {{ saveError }}
              </div>


            </div>
          </div>

          <div v-if="currentStep < 5" class="setup-skip-entry">
            <button class="btn btn-setup btn-setup-skip"
                    @click="skipWizard"
                    :disabled="saving"
                    type="button">
              <i class="fas fa-forward"></i>
              {{ $t('setup.skip') }}
            </button>
          </div>
        </div>
      </div>

      <!-- 操作按钮（固定底栏） -->
      <div class="action-buttons">
          <button class="btn btn-setup btn-setup-secondary" 
                  @click="previousStep" 
                  v-if="currentStep > 1 && currentStep < 5"
                  :disabled="saving">
            <i class="fas fa-arrow-left"></i>
            {{ $t('setup.previous') }}
          </button>
          <button class="btn btn-setup btn-setup-primary" 
                  @click="nextStep" 
                  v-if="currentStep < 5"
                  :disabled="!canProceed || saving || vddInstalling || vddStatusLoading">
            {{ nextButtonLabel }}
            <i class="fas fa-arrow-right"></i>
          </button>

          <button class="btn btn-setup btn-setup-primary" 
                  @click="goToApps" 
                  v-if="currentStep === 5">
            {{ $t('setup.go_to_apps') }}
            <i class="fas fa-arrow-right"></i>
          </button>
      </div>
    </div>
    <ConfirmDialog
      :show="showSkipModal"
      dialog-id="skip-wizard-confirm"
      :title="$t('setup.skip_confirm_title')"
      title-icon="fas fa-forward"
      tone="warning"
      :close-label="$t('_common.close')"
      @close="closeSkipModal"
    >
      <p>{{ $t('setup.skip_confirm') }}</p>
      <template #actions>
        <button type="button" class="btn btn-secondary" @click="closeSkipModal">{{ $t('_common.cancel') }}</button>
        <button type="button" class="btn btn-warning" @click="confirmSkipWizard">{{ $t('setup.skip') }}</button>
      </template>
    </ConfirmDialog>


    <ConfirmDialog
      :show="showRestartModal"
      dialog-id="setup-restart-countdown"
      :title="$t('setup.restart_title')"
      title-icon="fas fa-sync-alt"
      :dismissible="false"
    >
      <div class="text-center">
        <p>{{ $t('setup.restart_desc') }}</p>
        <div class="restart-countdown my-3">
          <span class="display-4 fw-bold text-primary">{{ restartCountdown }}</span>
          <p class="text-muted mt-1">{{ $t('setup.restart_countdown_unit') }}</p>
        </div>
        <div class="progress" style="height: 6px;">
          <div class="progress-bar bg-primary" :style="{ width: (restartCountdown / 8 * 100) + '%' }" role="progressbar"></div>
        </div>
      </div>
      <template #actions>
        <button type="button" class="btn btn-primary" @click="skipRestartCountdown">
          <i class="fas fa-arrow-right me-1"></i>
          {{ $t('setup.restart_go_now') }}
        </button>
      </template>
    </ConfirmDialog>
  </div>
</template>

<script>
import { trackEvents } from '../config/firebase.js'
import { apiFetch, apiJson } from '../utils/apiFetch.js'
import { saveSetupWizardLocale } from '../services/setupWizardService.js'
import { detectSystemLocale } from '../config/i18n.js'
import { useI18n as useShellI18n } from '@/desktop/i18n/index.js'
import { getWizardLocale, SETUP_WIZARD_LANGUAGE_SAVED_KEY } from '../composables/useSetupWizard.js'
import { useVddStatus } from '../composables/useVddStatus.js'
import ConfirmDialog from './common/ConfirmDialog.vue'

const COMPLETION_NOTICES = Object.freeze([
  {
    id: 'complete',
    messageKey: 'setup.setup_complete',
    icon: 'fas fa-check-circle',
    tone: 'success',
    emphasis: true,
  },
  {
    id: 'ready',
    messageKey: 'setup.setup_complete_desc',
    icon: 'fas fa-moon',
    tone: 'info',
  },
  {
    id: 'saved',
    messageKey: 'setup.config_saved',
    icon: 'fas fa-save',
    tone: 'success',
  },
])

const COMPLETION_NOTICE_DURATION_MS = 5000

function detectInitialWizardLocale() {
  return getWizardLocale(detectSystemLocale())
}

function isPhysicalDisplay(device) {
  return !/^FRIENDLY NAME:\s*Zako HDR\s*$/im.test(device?.data || '')
}

function markLanguageSavedForReload() {
  try {
    window.sessionStorage.setItem(SETUP_WIZARD_LANGUAGE_SAVED_KEY, 'true')
  } catch (e) {
    // If sessionStorage is unavailable, the saved locale still takes effect;
    // the user may simply see the language step again in Chinese environments.
  }
}

export default {
  name: 'SetupWizard',
  components: { ConfirmDialog },
  props: {
    adapters: {
      type: Array,
      default: () => []
    },
    displayDevices: {
      type: Array,
      default: () => []
    },
    hasLocale: {
      type: Boolean,
      default: false
    }
  },
  data() {
    return {
      currentStep: 1,
      // 已有 locale 时向导会跳过第一步，不预置，避免 saveConfiguration() 覆盖已有设置（如 de / ja）
      // 首次进入向导时保留繁体中文、简体中文或英语预选。
      selectedLocale: this.hasLocale ? null : detectInitialWizardLocale(),
      selectedDisplay: 'ZakoHDR', // 默认选择基地显示器
      selectedAdapter: '',
      displayDevicePrep: 'ensure_only_display', // 默认选择：确保唯一显示器（VDD 和普通模式通用）
      saveError: null,
      saving: false,
      showSkipModal: false, // 跳过向导确认弹窗
      showRestartModal: false, // 重启倒计时弹窗
      restartCountdown: 8, // 倒计时秒数
      restartTimer: null, // 倒计时定时器
      visibleCompletionNoticeIds: [],
      completionNoticeTimer: null,
      // 客户端下载链接
    }
  },
  setup() {
    const { t: shellT } = useShellI18n()
    return { ...useVddStatus(), shellT, wizardLocales: [
      { value: 'zh_TW', label: '繁體中文' },
      { value: 'zh', label: '简体中文' },
      { value: 'en', label: 'English' },
    ] }
  },
  mounted() {
    // 记录进入设置向导
    trackEvents.pageView('setup_wizard')
    trackEvents.userAction('setup_wizard_started', {
      has_locale: this.hasLocale,
      adapter_count: this.adapters.length
    })
    
    // 如果已经有语言配置，跳过第一步
    if (this.hasLocale) {
      this.currentStep = 2
      trackEvents.userAction('setup_wizard_skip_language', { 
        reason: 'already_configured' 
      })
    }
    
    // 如果只有一个显卡，自动选择
    if (this.uniqueAdapters.length === 1) {
      this.selectedAdapter = this.uniqueAdapters[0].name
    }
    this.refreshVddStatus()
  },
  beforeUnmount() {
    if (this.restartTimer) {
      clearInterval(this.restartTimer)
      this.restartTimer = null
    }
    this.clearCompletionNoticeTimer()
  },
  computed: {
    visibleCompletionNotices() {
      return COMPLETION_NOTICES.filter((notice) =>
        this.visibleCompletionNoticeIds.includes(notice.id)
      )
    },
    canProceed() {
      if (this.currentStep === 1) {
        return this.selectedLocale !== null
      } else if (this.currentStep === 2) {
        return this.selectedAdapter !== null
      } else if (this.currentStep === 3) {
        return this.selectedDisplay !== null
      } else if (this.currentStep === 4) {
        return this.displayDevicePrep !== null
      }
      return false
    },
    isVirtualDisplay() {
      return this.selectedDisplay === 'ZakoHDR'
    },
    nextButtonLabel() {
      if (this.currentStep === 3 && this.isVirtualDisplay && !this.vddReady) {
        return this.canManageVdd
          ? this.$t('setup.vdd_install_continue')
          : this.$t('setup.vdd_recheck_continue')
      }
      return this.currentStep === 4 ? this.$t('setup.finish') : this.$t('setup.next')
    },
    physicalDisplayDevices() {
      return (this.displayDevices || []).filter(isPhysicalDisplay)
    },
    // 按 name 去重，同一名称只保留一项（保持首次出现顺序）
    uniqueAdapters() {
      const list = this.adapters ?? []
      const seen = new Set()
      return list.filter((a) => {
        const name = a?.name ?? ''
        if (seen.has(name)) return false
        seen.add(name)
        return true
      })
    },

  },
  methods: {
    selectVirtualDisplay() {
      if (this.vddReady) {
        this.selectedDisplay = 'ZakoHDR'
      }
    },
    previousStep() {
      if (this.currentStep > 1) {
        this.currentStep--
      }
    },
    async nextStep() {
      if (this.currentStep === 1 && this.canProceed) {
        // 保存语言设置并刷新
        await this.saveLanguage()
      } else if (this.currentStep === 2 && this.canProceed) {
        this.currentStep++
      } else if (this.currentStep === 3 && this.canProceed) {
        if (this.isVirtualDisplay && !this.vddReady) {
          try {
            if (this.canManageVdd) {
              await this.installVdd()
            } else {
              await this.refreshVddStatus()
            }
          } catch {
            // The status panel keeps the selection and shows the actionable error.
          }
          if (!this.vddReady) return
        }
        this.currentStep++
      } else if (this.currentStep === 4 && this.canProceed) {
        await this.saveConfiguration()
      }
    },
    async saveLanguage() {
      try {
        const response = await saveSetupWizardLocale(this.selectedLocale)
        if (!response.ok) {
          throw new Error(`Failed to save language: HTTP ${response.status}`)
        }
        markLanguageSavedForReload()
        // 重新加载页面以应用新语言
        window.location.reload()
      } catch (error) {
        console.error('Failed to save language:', error)
      }
    },
    async saveConfiguration() {
      this.saving = true
      this.saveError = null

      try {
        // 先获取当前完整配置，保留所有已有设置
        const currentConfig = await apiJson('/api/config')
        
        // 从完整配置中复制所有字段，避免覆盖其他配置
        const config = { ...currentConfig }

        // 标记新手引导已完成
        config.setup_wizard_completed = true
        
        // 确保 locale 被保存（如果用户在步骤1选择了语言，或者已有配置中有 locale）
        if (this.selectedLocale) {
          config.locale = this.selectedLocale
        } else if (currentConfig.locale) {
          config.locale = currentConfig.locale
        }
        
        // 设置 adapter_name
        config.adapter_name = this.selectedAdapter || ''

        // 设置选择的显示器
        config.output_name = this.selectedDisplay

        // 统一保存 display_device_prep（VDD 和物理模式通用）
        config.display_device_prep = this.displayDevicePrep

        console.log('保存配置:', config)

        const response = await apiFetch('/api/config', {
          method: 'POST',
          body: config,
        })

        if (response.ok) {
          this.currentStep = 5
          this.showCompletionNotices()
          
          // 记录设置完成
          trackEvents.userAction('setup_wizard_completed', {
            selected_display: this.selectedDisplay,
            adapter: this.selectedAdapter,
            display_device_prep: this.displayDevicePrep,
            is_virtual_display: this.isVirtualDisplay
          })
          
          this.$emit('setup-complete', config)
        } else {
          const errorText = await response.text()
          this.saveError = `${this.$t('setup.save_error')}: ${errorText}`
          
          // 记录保存失败
          trackEvents.errorOccurred('setup_config_save_failed', errorText)
        }
      } catch (error) {
        console.error('Failed to save configuration:', error)
        this.saveError = `${this.$t('setup.save_error')}: ${error.message}`
      } finally {
        this.saving = false
      }
    },
    skipWizard(event) {
      if (event) {
        event.preventDefault()
        event.stopPropagation()
      }
      
      if (this.saving) return
      
      this.openSkipModal()
    },
    openSkipModal() {
      this.showSkipModal = true
    },
    closeSkipModal() {
      this.showSkipModal = false
    },
    clearCompletionNoticeTimer() {
      if (this.completionNoticeTimer) {
        clearTimeout(this.completionNoticeTimer)
        this.completionNoticeTimer = null
      }
    },
    showCompletionNotices() {
      this.clearCompletionNoticeTimer()
      this.visibleCompletionNoticeIds = COMPLETION_NOTICES.map((notice) => notice.id)
      this.completionNoticeTimer = setTimeout(() => {
        this.visibleCompletionNoticeIds = []
        this.completionNoticeTimer = null
      }, COMPLETION_NOTICE_DURATION_MS)
    },
    dismissCompletionNotice(noticeId) {
      this.visibleCompletionNoticeIds = this.visibleCompletionNoticeIds.filter(
        (id) => id !== noticeId
      )
      if (this.visibleCompletionNoticeIds.length === 0) {
        this.clearCompletionNoticeTimer()
      }
    },
    async confirmSkipWizard() {
      // 关闭模态框
      this.closeSkipModal()
      
      if (this.saving) return

      this.saving = true
      this.saveError = null

      try {
        // 先获取当前完整配置，保留所有已有设置
        const currentConfig = await apiJson('/api/config')
        
        // 从完整配置中复制所有字段，避免覆盖其他配置
        const config = { ...currentConfig }
        // 标记新手引导已完成
        config.setup_wizard_completed = true
        console.log('跳过新手引导，保存配置:', config)
        const response = await apiFetch('/api/config', {
          method: 'POST',
          body: config,
        })

        if (response.ok) {
          // 记录跳过事件
          trackEvents.userAction('setup_wizard_skipped', {
            from_step: this.currentStep
          })
          
          // 触发完成事件，让父组件知道设置向导已完成
          this.$emit('setup-complete', config)
          
          // 重新加载页面以隐藏设置向导
          window.location.reload()
        } else {
          const errorText = await response.text()
          this.saveError = `${this.$t('setup.skip_error')}: ${errorText}`
          
          // 记录跳过失败
          trackEvents.errorOccurred('setup_wizard_skip_failed', errorText)
        }
      } catch (error) {
        console.error('Failed to skip wizard:', error)
        this.saveError = `${this.$t('setup.skip_error')}: ${error.message}`
      } finally {
        this.saving = false
      }
    },
    goToApps() {
      // 记录跳转到应用配置页面
      trackEvents.userAction('setup_go_to_apps', {
        from_step: this.currentStep
      })
      // 触发重启并显示倒计时
      this.triggerRestartAndRedirect()
    },
    async triggerRestartAndRedirect() {
      // 调用重启 API
      try {
        await apiFetch('/api/restart', { method: 'POST' })
      } catch {
        // 重启请求可能会断开连接，忽略错误
      }
      // 显示倒计时弹窗
      this.showRestartModal = true
      this.restartCountdown = 8
      this.restartTimer = setInterval(() => {
        this.restartCountdown--
        if (this.restartCountdown <= 0) {
          this.finishRedirect()
        }
      }, 1000)
    },
    skipRestartCountdown() {
      this.finishRedirect()
    },
    finishRedirect() {
      if (this.restartTimer) {
        clearInterval(this.restartTimer)
        this.restartTimer = null
      }
      this.showRestartModal = false
      window.location.href = '/'
    },
    getDisplayName(device) {
      // 解析 device.data，提取友好名称
      // 数据格式：
      // DISPLAY NAME: \\.\\DISPLAY1
      // FRIENDLY NAME: F32D80U
      // DEVICE STATE: PRIMARY
      // HDR STATE: ENABLED
      try {
        const data = device.data || ''
        const name = data
          .replace(
            /.*?(DISPLAY\d+)?\nFRIENDLY NAME: (.*[^\n])*?\n.*\n.*/g,
            "$2 ($1)"
          )
          .replace("()", "")
        
        return name || device.device_id || this.$t('setup.unknown_display')
      } catch (e) {
        return device.device_id || this.$t('setup.unknown_display')
      }
    },
    getDisplayInfo(device) {
      // 解析 device.data，提取详细信息
      try {
        const data = device.data || ''
        
        // 提取 DEVICE STATE
        const stateMatch = data.match(/DEVICE STATE: (\w+)/)
        const state = stateMatch ? stateMatch[1].toLowerCase() : 'unknown'
        
        // 提取 HDR STATE
        const hdrMatch = data.match(/HDR STATE: (\w+)/)
        const hdr = hdrMatch ? hdrMatch[1] : ''
        
        const stateKey = {
          'primary': 'setup.state_primary',
          'active': 'setup.state_active',
          'inactive': 'setup.state_inactive'
        }[state] || 'setup.state_unknown'
        const stateText = this.$t(stateKey)
        
        let info = `${this.$t('setup.device_state')}: ${stateText}`
        if (hdr) {
          info += ` | HDR: ${hdr}`
        }
        
        return info
      } catch (e) {
        return device.device_id
      }
    }
  }
}
</script>

<style scoped>
.setup-container {
  position: fixed;
  inset: 0;
  padding: 1em;
  display: flex;
  flex-direction: column;
  align-items: center;
  z-index: 1000;
  background:
    radial-gradient(circle at 12% 0%, rgba(var(--ui-accent-rgb), 0.18), transparent 34rem),
    var(--ui-page-bg);
  color: var(--ui-text-primary);
}

.setup-card {
  background: var(--ui-surface-strong);
  border: 1px solid var(--ui-border);
  border-radius: var(--ui-radius-lg);
  box-shadow: var(--ui-shadow-md);
  backdrop-filter: blur(22px);
  overflow: hidden;
  display: flex;
  flex-direction: column;
  width: 100%;
  max-width: 900px;
  flex: 1;
  min-height: 0;
}

.setup-header {
  background: var(--ui-surface-strong);
  color: var(--ui-text-primary);
  padding: 1.2em;
  text-align: center;
  flex-shrink: 0;
  border-bottom: 1px solid var(--ui-border);
}

.setup-brand { display:flex; flex-wrap:wrap; align-items:center; justify-content:center; gap:12px; font-size:18px; font-weight:600; }
.language-option { width:100%; display:flex; align-items:center; gap:16px; text-align:left; color:var(--ui-text-primary); font:inherit; }
.language-option i { font-size:24px; color:var(--ui-accent); }
.setup-skip-entry { margin-top:24px; }
.action-buttons > .btn-setup-primary { margin-left:auto; }
.setup-header img {
  filter: drop-shadow(0 6px 14px rgba(var(--ui-accent-rgb), 0.18));
}

.setup-header h1 {
  margin: 0.3em 0 0 0;
  font-size: 1.5em;
  font-weight: 600;
  color: var(--ui-accent);
}

.setup-header p {
  margin: 0.3em 0 0 0;
  color: var(--ui-text-secondary);
  font-size: 0.95em;
}

.setup-content {
  padding: 1.2em 1.5em;
  display: flex;
  flex-direction: column;
  flex: 1;
  overflow: hidden;
  min-height: 0;
  background: color-mix(in srgb, var(--ui-surface) 74%, transparent);
}

.step-indicator {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-bottom: 1.2em;
  gap: 0.5em;
  flex-shrink: 0;
}

.step {
  display: flex;
  align-items: center;
  gap: 0.3em;
  font-size: 0.85em;
  color: var(--ui-text-secondary);
}

.step-number {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 0.9em;
  background: var(--ui-surface);
  color: var(--ui-text-secondary);
  border: 1px solid var(--ui-border);
  transition: all 0.3s ease;
  flex-shrink: 0;
}

.step.active .step-number {
  background: var(--ui-accent);
  color: var(--ui-accent-contrast);
  border-color: var(--ui-accent);
  transform: scale(1.05);
}

.step.active {
  color: var(--ui-text-primary);
}

.step.completed .step-number {
  background: var(--ui-success);
  color: white;
  border-color: var(--ui-success);
}

.step-connector {
  width: 30px;
  height: 2px;
  background: var(--ui-border);
  flex-shrink: 0;
}

.step-content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding-right: 0.5em;
  padding-bottom: 1em;
  scrollbar-gutter: stable;
}

.step-content h3 {
  font-size: 1.1em;
  margin-bottom: 0.8em;
  color: var(--ui-text-primary);
}

.option-card {
  border: 1px solid var(--ui-border);
  border-radius: 10px;
  padding: 0.8em 1em;
  margin-bottom: 0.6em;
  cursor: pointer;
  transition: all 0.3s ease;
  background: var(--ui-surface);
}

.option-card:hover {
  border-color: var(--ui-border-strong);
  transform: translateY(-1px);
  box-shadow: var(--ui-shadow-sm);
  background: var(--ui-surface-hover);
}

.option-card.selected {
  border-color: var(--ui-accent);
  background: var(--ui-accent-soft);
}

.option-card.disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.option-card.disabled:hover {
  border-color: var(--ui-border);
  transform: none;
  box-shadow: none;
  background: var(--ui-surface);
}

.option-card .option-icon {
  font-size: 1.8em;
  margin-bottom: 0.3em;
  color: var(--ui-accent);
}

.option-card h4 {
  margin: 0.3em 0;
  font-weight: 600;
  font-size: 1em;
  color: var(--ui-text-primary);
}

.option-card p {
  margin: 0;
  color: var(--ui-text-secondary);
  font-size: 0.85em;
  line-height: 1.3;
}

/* 紧凑型选项卡片（水平布局） */
.option-card-compact {
  display: flex;
  align-items: center;
  border: 1px solid var(--ui-border);
  border-radius: 8px;
  padding: 0.5em 0.8em;
  margin-bottom: 0.4em;
  cursor: pointer;
  transition: all 0.3s ease;
  background: var(--ui-surface);
  gap: 0.7em;
}

.option-card-compact:hover {
  border-color: var(--ui-border-strong);
  transform: translateY(-1px);
  box-shadow: var(--ui-shadow-sm);
  background: var(--ui-surface-hover);
}

.option-card-compact.selected {
  border-color: var(--ui-accent);
  background: var(--ui-accent-soft);
}

.option-icon-compact {
  font-size: 1.2em;
  color: var(--ui-accent);
  flex-shrink: 0;
  width: 2em;
  text-align: center;
}

.option-card-compact .option-text h4 {
  margin: 0;
  font-weight: 600;
  font-size: 0.9em;
  color: var(--ui-text-primary);
}

.option-card-compact .option-text p {
  margin: 0;
  color: var(--ui-text-secondary);
  font-size: 0.85em;
  line-height: 1.3;
}

.form-select-large {
  padding: 0.7em;
  font-size: 1em;
  border-radius: 8px;
  border: 1px solid var(--ui-border);
  background-color: var(--ui-surface);
  color: var(--ui-text-primary);
  transition: all 0.3s ease;
}

/* 显卡适配器标签 */
.adapter-label {
  font-size: 1.05em;
  font-weight: 600;
  color: var(--ui-text-primary);
}

/* 物理显示器标题 */
.physical-display-title {
  font-size: 0.95em;
  color: var(--ui-text-primary);
}

.form-select-large:focus {
  border-color: var(--ui-accent);
  box-shadow: 0 0 0 0.2rem var(--ui-accent-soft);
}

.action-buttons {
  display: flex;
  justify-content: space-between;
  gap: 0.8em;
  flex-shrink: 0;
  padding: 1em 1.5em;
  border-top: 1px solid var(--ui-border);
  background: var(--ui-surface-strong);
}

.btn-setup {
  padding: 0.6em 1.5em;
  font-size: 1em;
  border-radius: 8px;
  font-weight: 500;
  transition: all 0.3s ease;
}

.btn-setup-primary {
  background: var(--ui-accent);
  border: 1px solid var(--ui-accent);
  color: var(--ui-accent-contrast);
}

.btn-setup-primary:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: var(--ui-shadow-md);
  color: var(--ui-accent-contrast);
}

.btn-setup-secondary {
  background: var(--ui-surface);
  border: 1px solid var(--ui-border);
  color: var(--ui-text-primary);
}

.btn-setup-secondary:hover:not(:disabled) {
  background: var(--ui-surface-hover);
  border-color: var(--ui-border-strong);
  transform: translateY(-1px);
}

.btn-setup-skip {
  background: var(--ui-accent-soft);
  border: 1px solid var(--ui-border-strong);
  color: var(--ui-accent);
  font-weight: 500;
}

.btn-setup-skip:hover:not(:disabled) {
  background: var(--ui-surface-hover);
  border-color: var(--ui-accent);
  color: var(--ui-accent);
  transform: translateY(-1px);
  box-shadow: var(--ui-shadow-sm);
}

.adapter-info {
  background: var(--ui-surface);
  border: 1px solid var(--ui-border);
  padding: 0.8em;
  border-radius: 8px;
  margin-top: 0.8em;
  font-size: 0.9em;
}

.adapter-info h5 {
  font-size: 1em;
  margin-bottom: 0.5em;
}

.adapter-info p {
  margin-bottom: 0.3em;
  font-size: 0.95em;
}

/* GPU选择提示框样式 */
.adapter-hint-box {
  background: var(--ui-accent-soft);
  padding: 0.8em 1em;
  border-radius: 8px;
  border: 1px solid var(--ui-border);
  font-size: 0.9em;
  line-height: 1.5;
  color: var(--ui-text-secondary);
  font-weight: 500;
}

/* VDD 介绍文字样式 */
.vdd-intro-text {
  color: var(--ui-text-secondary);
  font-size: 0.95em;
}

.adapter-vdd-hint {
  margin: 0.5em 0 0 0;
  padding: 0.5em 0.8em;
  background: color-mix(in srgb, var(--ui-success) 12%, transparent);
  color: var(--ui-success-text);
  border-radius: 4px;
  font-size: 0.95em;
  white-space: pre-wrap;
  word-wrap: break-word;
}

/* 滚动条样式 */
.step-content::-webkit-scrollbar {
  width: 6px;
}

.step-content::-webkit-scrollbar-track {
  background: transparent;
}

.step-content::-webkit-scrollbar-thumb {
  background: var(--ui-border-strong);
  border-radius: 3px;
}

.step-content::-webkit-scrollbar-thumb:hover {
  background: var(--ui-accent);
}

.setup-completion-toasts {
  position: fixed;
  top: max(1rem, env(safe-area-inset-top));
  left: 50%;
  z-index: 1080;
  display: grid;
  width: min(480px, calc(100vw - 2rem));
  gap: 0.6rem;
  transform: translateX(-50%);
  pointer-events: none;
}

.setup-completion-toast {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  min-height: 48px;
  gap: 0.75rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid var(--ui-border);
  border-radius: var(--ui-radius-md);
  color: var(--ui-text-primary);
  background: var(--ui-surface-strong);
  box-shadow: var(--ui-shadow-lg);
  pointer-events: auto;
}

.setup-completion-toast-success {
  border-color: color-mix(in srgb, var(--ui-success) 40%, var(--ui-border));
  background: color-mix(in srgb, var(--ui-success) 10%, var(--ui-surface-strong));
}

.setup-completion-toast-success > i {
  color: var(--ui-success);
}

.setup-completion-toast-info {
  border-color: color-mix(in srgb, var(--ui-accent) 40%, var(--ui-border));
  background: color-mix(in srgb, var(--ui-accent) 10%, var(--ui-surface-strong));
}

.setup-completion-toast-info > i {
  color: var(--ui-accent);
}

.setup-completion-toast-title {
  font-weight: 700;
}

.setup-completion-toast-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  padding: 0;
  border: 0;
  border-radius: var(--ui-radius-sm);
  color: var(--ui-text-secondary);
  background: transparent;
  cursor: pointer;
}

.setup-completion-toast-close:hover,
.setup-completion-toast-close:focus-visible {
  color: var(--ui-text-primary);
  background: var(--ui-surface-hover);
}

.setup-toast-enter-active,
.setup-toast-leave-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s ease;
}

.setup-toast-enter-from,
.setup-toast-leave-to {
  opacity: 0;
  transform: translateY(-0.75rem);
}

.setup-toast-move {
  transition: transform 0.2s ease;
}

/* 小图标样式 */
.option-icon-small {
  font-size: 1.5em;
  color: var(--ui-accent);
  margin-right: 0.8em;
  flex-shrink: 0;
}

.d-flex {
  display: flex;
}

.align-items-center {
  align-items: center;
}

.flex-grow-1 {
  flex-grow: 1;
}

.my-3 {
  margin-top: 1rem;
  margin-bottom: 1rem;
}

.restart-countdown .text-primary {
  color: var(--ui-accent) !important;
}

.restart-countdown + .progress .progress-bar {
  background: var(--ui-accent) !important;
}

@media (max-width: 768px) {
  .setup-container {
    padding: 0;
  }

  .setup-card {
    max-width: none;
    min-height: 100dvh;
    border: 0;
    border-radius: 0;
  }

  .setup-header {
    padding: 0.85rem 1rem;
  }

  .setup-header img {
    height: 44px;
  }

  .setup-header h1 {
    font-size: 1.2rem;
  }

  .setup-header p {
    font-size: 0.82rem;
  }

  .setup-content {
    padding: 1rem;
  }

  .step-indicator {
    gap: 0.35rem;
    margin-bottom: 0.9rem;
  }

  .step span {
    display: none;
  }

  .step-number {
    width: 26px;
    height: 26px;
  }

  .step-connector {
    width: auto;
    min-width: 12px;
    flex: 1;
  }

  .step-content {
    padding-right: 0.25rem;
  }

  .option-card,
  .option-card-compact {
    padding: 0.75rem;
  }

  .action-buttons {
    padding: 0.85rem 1rem;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .btn-setup {
    flex: 1 1 auto;
    padding: 0.65rem 0.85rem;
    white-space: nowrap;
  }




}
</style>

