<template>
  <div class="setup-page">
    <Navbar v-if="!showSetupWizard" />
    <SetupWizard v-if="showSetupWizard" :adapters="adapters" :display-devices="displayDevices" :has-locale="hasLocale" @setup-complete="onSetupComplete" />
    <main v-else class="container">
      <div v-if="failed" class="alert alert-danger" role="alert">{{ $t('index.startup_errors').replace(/<[^>]+>/g, '') }}</div>
      <ErrorLogs :fatal-logs="fatalLogs" />
    </main>
  </div>
</template>
<script setup>
import { ref, onMounted } from 'vue'
import Navbar from '../components/layout/Navbar.vue'
import SetupWizard from '../components/SetupWizard.vue'
import ErrorLogs from '../components/common/ErrorLogs.vue'
import { useLogs } from '../composables/useLogs.js'
import { useSetupWizard } from '../composables/useSetupWizard.js'
import { getBootstrapConfig } from '../config/bootstrapData.js'
const failed = ref(false)
const { fatalLogs, fetchLogs } = useLogs()
const { showSetupWizard, adapters, displayDevices, hasLocale, checkSetupWizard, onSetupComplete } = useSetupWizard()
onMounted(async () => {
  try {
    const config = await getBootstrapConfig()
    const force = new URLSearchParams(window.location.search).get('setup') === '1'
    if (!checkSetupWizard(config, { force })) window.location.replace('/config')
  } catch {
    failed.value = true
    await fetchLogs()
  }
})
</script>
<style>
@import '../styles/global.less';
</style>
