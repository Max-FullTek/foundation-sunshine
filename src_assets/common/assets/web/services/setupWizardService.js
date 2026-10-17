import { apiFetch, apiJson, getApiErrorMessage } from '../utils/apiFetch.js'

// Core uses property_tree and returns string booleans in its JSON response.
export async function saveSetupWizardConfig(config) {
  const response = await apiFetch('/api/config', { method: 'POST', body: config })
  const data = await response.clone().json().catch(() => null)
  if (!response.ok || ![true, 'true'].includes(data?.status)) {
    const message = getApiErrorMessage(data, response)
    throw new Error(response.ok && message === `HTTP ${response.status}`
      ? 'Configuration save was not confirmed by the server'
      : message)
  }
  return response
}

/**
 * 保存向导语言时保留完整配置。
 *
 * `/api/config` 的 POST 是完整替换，因此不能只提交 locale。
 */
export async function saveSetupWizardLocale(locale) {
  const currentConfig = await apiJson('/api/config')

  return saveSetupWizardConfig({
    ...currentConfig,
    locale,
  })
}
