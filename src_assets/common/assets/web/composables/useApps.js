import { computed, ref } from 'vue'
import { translateFallback } from '../utils/localizedMessage.js'
import { AppService } from '../services/appService.js'
import { APP_CONSTANTS, ENV_VARS_CONFIG } from '../utils/constants.js'
import { debounce, deepClone } from '../utils/helpers.js'
import { trackEvents } from '../config/firebase.js'
const MESSAGE_DURATION = 3000
/**
 * 应用管理组合式函数
 */
export function useApps() {
  // 状态
  const apps = ref([])
  const originalApps = ref([])
  const searchQuery = ref('')
  const committedSearchQuery = ref('')
  const editingApp = ref(null)
  const platform = ref('')
  const isSaving = ref(false)
  const isDragging = ref(false)
  const viewMode = ref('grid')
  const message = ref('')
  const messageType = ref('success')
  const envVars = ref({})
  const debouncedSearch = ref(null)
  const deleteConfirmIndex = ref(null)

  // 批量删除：selectionMode 仅控制 UI 是否显示多选 checkbox；
  // selectedIndices 是 Set<number>，存的是 apps.value 的原始 index，
  // 不能存 filteredApps 的下标，否则搜索后下标会错位。
  const selectionMode = ref(false)
  const selectedIndices = ref(new Set())
  const batchDeleteConfirm = ref(false)
  const isBatchDeleting = ref(false)
  const appRenderKeys = new WeakMap()
  let nextAppRenderKey = 0

  // 计算属性
  const messageClass = computed(() => ({
    [`alert-${messageType.value}`]: true,
  }))

  const normalizeAppForChangeCheck = (app) => {
    const { index, ...rest } = app
    return rest
  }

  const filteredApps = computed(() => AppService.searchApps(apps.value, committedSearchQuery.value))
  const appIndexByReference = computed(() => new Map(apps.value.map((app, index) => [app, index])))
  const filteredAppsWithIndex = computed(() =>
    filteredApps.value.map((app) => ({
      app,
      index: appIndexByReference.value.get(app) ?? -1,
    }))
  )
  // 消息图标映射
  const MESSAGE_ICONS = {
    success: 'fa-check-circle',
    error: 'fa-exclamation-circle',
    warning: 'fa-exclamation-triangle',
    info: 'fa-info-circle',
  }

  const showMessage = (msg, type = APP_CONSTANTS.MESSAGE_TYPES.SUCCESS) => {
    message.value = msg
    messageType.value = type
    setTimeout(() => {
      message.value = ''
    }, MESSAGE_DURATION)
  }

  const getMessageIcon = () => MESSAGE_ICONS[messageType.value] || MESSAGE_ICONS.success

  const createDefaultApp = (overrides = {}) => ({
    ...APP_CONSTANTS.DEFAULT_APP,
    index: -1,
    ...overrides,
  })

  let translate = translateFallback

  // 初始化
  const init = (t) => {
    translate = t
    envVars.value = Object.fromEntries(
      Object.entries(ENV_VARS_CONFIG).map(([key, translationKey]) => [key, t(translationKey)])
    )
    debouncedSearch.value = debounce(performSearch, APP_CONSTANTS.SEARCH_DEBOUNCE_TIME)
  }

  // 数据加载
  const loadApps = async () => {
    try {
      apps.value = await AppService.getApps()
      originalApps.value = deepClone(apps.value)
    } catch (error) {
      console.error('加载应用失败:', error)
      showMessage(translate('apps.feedback.load_failed'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)
    }
  }

  const loadPlatform = async () => {
    try {
      platform.value = await AppService.getPlatform()
    } catch (error) {
      console.error('加载平台信息失败:', error)
      platform.value = APP_CONSTANTS.PLATFORMS.WINDOWS
    }
  }

  // 搜索
  const performSearch = () => {
    committedSearchQuery.value = searchQuery.value
  }

  const clearSearch = () => {
    searchQuery.value = ''
    committedSearchQuery.value = ''
    performSearch()
  }

  // 应用操作
  const getAppRenderKey = (app) => {
    const existingKey = appRenderKeys.get(app)
    if (existingKey) return existingKey

    const key = `app-${++nextAppRenderKey}`
    appRenderKeys.set(app, key)
    return key
  }

  const newApp = () => {
    trackEvents.userAction('new_app_clicked')
    editingApp.value = createDefaultApp()
  }

  const editApp = (index) => {
    editingApp.value = { ...deepClone(apps.value[index]), index }
  }

  const closeAppEditor = () => {
    editingApp.value = null
  }

  const handleSaveApp = async (appData) => {
    try {
      isSaving.value = true

      await AppService.saveApps(apps.value, appData)
      await loadApps()
        editingApp.value = null
      showMessage(translate('apps.feedback.save_success'), APP_CONSTANTS.MESSAGE_TYPES.SUCCESS)
    } catch (error) {
      console.error('保存应用失败:', error)
      showMessage(translate('apps.feedback.save_failed'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)
    } finally {
      isSaving.value = false
    }
  }

  const showDeleteForm = (index) => {
    deleteConfirmIndex.value = index
  }

  const cancelDeleteApp = () => {
    deleteConfirmIndex.value = null
  }

  const confirmDeleteApp = async () => {
    const index = deleteConfirmIndex.value
    if (index === null) return
    deleteConfirmIndex.value = null
    await deleteApp(index)
  }

  const deleteApp = async (index) => {
    const appName = apps.value[index]?.name || 'unknown'
    try {
      apps.value.splice(index, 1)
      await AppService.saveApps(apps.value, null)
      await loadApps()
      showMessage(translate('apps.feedback.delete_success'), APP_CONSTANTS.MESSAGE_TYPES.SUCCESS)
      trackEvents.appDeleted(appName)
    } catch (error) {
      console.error('删除应用失败:', error)
      showMessage(translate('apps.feedback.delete_failed'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)
    }
  }

  // 进入/退出多选模式，退出时清空选择
  const toggleSelectionMode = () => {
    selectionMode.value = !selectionMode.value
    if (!selectionMode.value) {
      selectedIndices.value = new Set()
    }
  }

  const toggleAppSelection = (index) => {
    const next = new Set(selectedIndices.value)
    if (next.has(index)) next.delete(index)
    else next.add(index)
    selectedIndices.value = next
  }

  const isAppSelected = (index) => selectedIndices.value.has(index)

  // 全选/反选
  const selectAllFiltered = () => {
    const next = new Set(selectedIndices.value)
    filteredAppsWithIndex.value.forEach(({ index }) => {
      if (index >= 0) next.add(index)
    })
    selectedIndices.value = next
  }

  const clearSelection = () => {
    selectedIndices.value = new Set()
  }

  const askBatchDelete = () => {
    if (selectedIndices.value.size === 0) return
    batchDeleteConfirm.value = true
  }

  const cancelBatchDelete = () => {
    batchDeleteConfirm.value = false
  }

  const confirmBatchDelete = async () => {
    const indices = Array.from(selectedIndices.value)
    if (indices.length === 0) {
      batchDeleteConfirm.value = false
      return
    }
    try {
      isBatchDeleting.value = true
      const result = await AppService.batchDeleteApps(indices)
      await loadApps()
      selectedIndices.value = new Set()
      selectionMode.value = false
      batchDeleteConfirm.value = false
      showMessage(
        translate('apps.batch_delete_result', { deleted: result.deleted, remaining: result.remaining }),
        APP_CONSTANTS.MESSAGE_TYPES.SUCCESS
      )
    } catch (error) {
      console.error('批量删除失败:', error)
      showMessage(
        translate('apps.batch_delete_failed'),
        APP_CONSTANTS.MESSAGE_TYPES.ERROR
      )
    } finally {
      isBatchDeleting.value = false
    }
  }

  // 检测是否有未保存的更改
  const hasUnsavedChanges = computed(() => {
    if (apps.value.length !== originalApps.value.length) {
      return true
    }
  
    // 深度比较应用列表
    const appsStr = JSON.stringify(apps.value.map(normalizeAppForChangeCheck))
    const originalStr = JSON.stringify(originalApps.value.map(normalizeAppForChangeCheck))
    
    return appsStr !== originalStr
  })

  const save = async () => {
    // 如果没有更改，直接返回
    if (!hasUnsavedChanges.value) {
      showMessage(translate('_common.no_changes'), APP_CONSTANTS.MESSAGE_TYPES.INFO)
      return
    }

    try {
      isSaving.value = true
      await AppService.saveApps(apps.value, null)
      // 保存成功后更新原始列表
      originalApps.value = deepClone(apps.value)
      showMessage(translate('apps.feedback.save_success'), APP_CONSTANTS.MESSAGE_TYPES.SUCCESS)
      trackEvents.userAction('apps_saved', { count: apps.value.length })
    } catch (error) {
      console.error('保存应用列表失败:', error)
      showMessage(translate('apps.feedback.save_failed'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)
    } finally {
      isSaving.value = false
    }
  }

  // 拖拽排序
  const restoreDefaultApps = async () => {
    try {
      const result = AppService.restoreDefaultBuiltInApps(apps.value, platform.value)

      if (result.changed === 0) {
        showMessage(translate('apps.restore_default_apps_none'), APP_CONSTANTS.MESSAGE_TYPES.INFO)
        return
      }

      isSaving.value = true
      apps.value = result.apps
      await AppService.saveApps(apps.value, null)
      await loadApps()
      showMessage(
        translate('apps.restore_default_apps_result', { restored: result.restored, added: result.added }),
        APP_CONSTANTS.MESSAGE_TYPES.SUCCESS
      )
      trackEvents.userAction('default_apps_restored', {
        platform: platform.value,
        restored: result.restored,
        added: result.added,
      })
    } catch (error) {
      console.error('Restore default apps failed:', error)
      showMessage(translate('apps.restore_default_apps_failed'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)
    } finally {
      isSaving.value = false
    }
  }

  const onDragStart = () => {
    isDragging.value = true
  }

  const onDragEnd = async () => {
    isDragging.value = false
    await save()
  }

  const handleCopySuccess = () => showMessage(translate('_common.copied'), APP_CONSTANTS.MESSAGE_TYPES.SUCCESS)
  const handleCopyError = () => showMessage(translate('apps.copy_failed_manual'), APP_CONSTANTS.MESSAGE_TYPES.ERROR)

  return {
    // 状态
    apps,
    filteredApps,
    filteredAppsWithIndex,
    searchQuery,
    editingApp,
    platform,
    isSaving,
    isDragging,
    viewMode,
    message,
    envVars,
    debouncedSearch,
    selectionMode,
    selectedIndices,
    batchDeleteConfirm,
    isBatchDeleting,
    // 计算属性
    messageClass,
    // 方法
    init,
    loadApps,
    loadPlatform,
    clearSearch,
    getAppRenderKey,
    newApp,
    editApp,
    closeAppEditor,
    handleSaveApp,
    showDeleteForm,
    cancelDeleteApp,
    confirmDeleteApp,
    deleteConfirmIndex,
    toggleSelectionMode,
    toggleAppSelection,
    isAppSelected,
    selectAllFiltered,
    clearSelection,
    askBatchDelete,
    cancelBatchDelete,
    confirmBatchDelete,
    save,
    restoreDefaultApps,
    hasUnsavedChanges,
    onDragStart,
    onDragEnd,
    getMessageIcon,
    handleCopySuccess,
    handleCopyError,
  }
}
