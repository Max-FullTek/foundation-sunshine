import { resolve } from 'node:path'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

// Production and development must resolve the same Vue instance and shell.
export const sharedResolve = {
  dedupe: ['vue', 'vue-i18n', 'element-plus', '@tauri-apps/api'],
  alias: {
    vue: 'vue/dist/vue.esm-bundler.js',
    '@': resolve('src_assets/common/sunshine-control-panel/src/renderer'),
  },
}

export const sharedCss = {
  preprocessorOptions: {
    less: {
      javascriptEnabled: true,
      additionalData: '@import "@/styles/variables.less"; @import "@/styles/mixins.less";',
    },
  },
}

export const sharedComponents = () => Components({
  dts: false,
  resolvers: [ElementPlusResolver({ importStyle: 'css' })],
})
