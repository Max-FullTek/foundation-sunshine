<script setup>
import { useI18n } from 'vue-i18n'
import { LEGAL_RESOURCES } from '../../config/resources.js'
const { t } = useI18n()
</script>

<template>
  <footer class="legal-footer">
    <span>GNU GPL v3.0</span>
    <a v-for="resource in LEGAL_RESOURCES" :key="resource.id" :href="resource.href" target="_blank" rel="noopener noreferrer">{{ t(resource.titleKey) }}</a>
  </footer>
</template>

<style scoped>
.legal-footer { display: flex; flex-wrap: wrap; gap: 16px; padding-top: 24px; margin-top: 24px; border-top: 1px solid var(--bs-border-color); font-size: 13px; }
</style>
