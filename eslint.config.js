import configs from './src_assets/common/sunshine-control-panel/eslint.webui.config.js'
export default configs.map(config => ({ ...config, basePath: 'src_assets/common/sunshine-control-panel' }))
