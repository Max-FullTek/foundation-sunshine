<template>
  <SidebarMenu ref="sidebar" :webui-path="path" :host-status="hostStatus" @webui-navigate="navigate">
    <slot />
  </SidebarMenu>
</template>
<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { useI18n as useWebI18n } from 'vue-i18n'
import SidebarMenu from '@/components/SidebarMenu.vue'
import { useI18n as useShellI18n } from '@/desktop/i18n/index.js'
import { setShellLocale } from '@/desktop/i18n/index.js'
import { hasDesktopRuntime } from '@/shared/runtime.js'
import { readHostStatus } from '@/composables/hostStatus.js'
import { isWebuiNavigationPath } from '@/composables/webuiNavigation.js'
import '@/styles/element-theme.less'
import '@/styles/dialog.less'
import { useBackground } from '../../composables/useBackground.js'

const sidebar = ref(null)
const path = ref(location.pathname + location.search + location.hash)
const hostStatus = ref({ state: 'connecting' })
const { locale: shellLocale } = useShellI18n()
const { locale, setLocaleMessage, t } = useWebI18n()
const { loadBackground } = useBackground({ translate: t })
const native = hasDesktopRuntime()
let stopped = false
let statusTimer
const cleanups = []
const navigate = (destination) => {
  if (isWebuiNavigationPath(destination)) location.assign(destination)
}
// Shell labels and page labels share the same current locale. The canonical
// page catalog stays on the server; no second copy is bundled into Desktop.
watch(shellLocale, async (value) => {
  if (locale.value === value) return
  try {
    const response = await fetch(`/assets/locale/${value}.json`)
    if (!response.ok) return
    const catalog = await response.json()
    if (stopped || shellLocale.value !== value) return
    setLocaleMessage(value, catalog)
    locale.value = value
  } catch { /* Existing page language remains usable if fetching fails. */ }
})
const updatePath = () => { path.value = location.pathname + location.search + location.hash }
onMounted(async () => {
  setShellLocale(locale.value)
  document.documentElement.dataset.sunshineNavigation = 'shared'
  loadBackground()
  window.addEventListener('hashchange', updatePath)
  const refresh = async () => {
    if (stopped) return
    if (window.__FOUNDATION_PREVIEW_SAMPLE__) hostStatus.value = { state: 'preview' }
    else if (document.visibilityState !== 'hidden') {
      const nextStatus = await readHostStatus('')
      if (!stopped) hostStatus.value = nextStatus
    }
    if (!stopped) statusTimer = setTimeout(refresh, 15000)
  }
  refresh()
  if (!native) return
  try {
    const { listen } = await import('@tauri-apps/api/event')
    const { invoke } = await import('@tauri-apps/api/core')
    for (const [event, handler] of [
      ['open-vdd-settings', () => sidebar.value?.openVddSettings()],
      ['open-welcome', () => location.assign('/welcome')],
    ]) {
      if (stopped) return
      cleanups.push(await listen(event, handler))
      if (stopped) cleanups.pop()?.()
    }
    if (!stopped) await invoke('main_panel_ready')
  } catch {
    // Leave server-backed pages usable if native initialization fails.
    if (!stopped) hostStatus.value = { state: 'offline' }
  }
})
onUnmounted(() => {
  stopped = true
  clearTimeout(statusTimer)
  window.removeEventListener('hashchange', updatePath)
  cleanups.forEach((fn) => fn())
})
</script>
<style>
html[data-sunshine-navigation='shared'] body { padding:0 !important; overflow:hidden; }
html[data-sunshine-navigation='shared'] #app { height:100vh; }
html[data-sunshine-navigation='shared'] .sidebar-wrapper { background:transparent; }
.sidebar-wrapper .main-content { background:transparent !important; }
.sidebar-wrapper .page-content { scrollbar-gutter:stable; }
.sidebar-wrapper .page-config, .sidebar-wrapper .pin-page, .sidebar-wrapper .apps-page { min-height:0; background:transparent; }
.sidebar-wrapper .page-config > .container, .sidebar-wrapper .pin-page > .container, .sidebar-wrapper .apps-page > .container-fluid { padding-top:52px !important; }
.sidebar-wrapper .page-config > .config-content-container { padding-top:0 !important; }
.sidebar-wrapper .lite-page-header { padding-top:0; }
</style>
