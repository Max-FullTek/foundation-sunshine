import i18n from './config/i18n.js'
import { markWebUiReady } from './utils/appReady.js'
import { installExternalLinkHandler } from './utils/helpers.js'
import { createApp, h } from 'vue'
import SharedShell from './components/layout/SharedShell.vue'

export const createSharedApp = (page) => createApp({
    render: () => h(SharedShell, null, { default: () => h(page) }),
})

// must import even if not implicitly using here
// https://github.com/aurelia/skeleton-navigation/issues/894
// https://discourse.aurelia.io/t/bootstrap-import-bootstrap-breaks-dropdown-menu-in-navbar/641/9
// 导入 Bootstrap 并手动设置到全局对象（ES 模块不会自动注册到 window）
import * as bootstrap from 'bootstrap'

// 将 Bootstrap 设置到全局对象，以便在组件中使用
if (typeof window !== 'undefined') {
  window.bootstrap = bootstrap
}

export async function initApp(app, config) {
    try {
        installExternalLinkHandler()
        const i18nInstance = await i18n()

        app.use(i18nInstance)
        app.provide('i18n', i18nInstance.global)
        app.provide('shared-shell', true)
        const root = app.mount('#app')
        config?.(app)
        // Let Vue finish the mount microtask before reporting page readiness.
        await Promise.resolve()
        return root
    } finally {
        markWebUiReady()
    }
}
