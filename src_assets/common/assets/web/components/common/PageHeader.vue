<template>
  <PageHeading class="lite-page-header" :title="page ? t.sidebar[WEBUI_PAGES.find(item => item.id === page)?.label] : title" :description="description || t.pageNotes[page]">
    <template #icon><component v-if="page" :is="WEBUI_ICONS[page]" /><i v-else :class="icon"></i></template>
    <template v-if="$slots.actions" #actions><slot name="actions" /></template>
  </PageHeading>
</template>
<script setup>
import { WEBUI_ICONS } from '@/composables/toolsRegistry.js'
import { WEBUI_PAGES } from '@/composables/webuiNavigation.js'
import { useI18n } from '@/desktop/i18n/index.js'
import PageHeading from '@/components/PageHeading.vue'
const { t } = useI18n()
defineProps({ page: String, title: String, description: String, icon: String })
</script>
<style>
.lite-page-header .btn-primary { --bs-btn-disabled-bg:var(--ui-accent); --bs-btn-disabled-border-color:var(--ui-accent); --bs-btn-disabled-color:var(--ui-accent-contrast); }
.page-config > .container, .pin-page > .container, .apps-page > .container-fluid { width:100%; max-width:1440px; margin:0 auto; padding:20px 24px 32px !important; }
.page-config > .config-heading-container { padding-bottom:0 !important; }
.page-config > .config-content-container { padding-top:0 !important; }
.page-config .lite-page-header .config-floating-buttons { position:static; float:none; clear:none; top:auto; right:auto; margin:0; display:flex; flex-direction:row; align-items:center; gap:10px; }
.lite-page-header .floating-toast-container { position:fixed; right:24px; bottom:48px; z-index:1100; }
</style>
