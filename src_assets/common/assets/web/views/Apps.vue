<template>
  <div class="apps-page">
    <Navbar />
    <main class="container-fluid">
      <PageHeader page="apps">
        <template #actions>
          <div class="search-container apps-heading-search">
            <div class="search-box">
              <i class="fas fa-search search-icon" aria-hidden="true"></i>
              <input class="form-control search-input" v-model="searchQuery" :placeholder="$t('apps.search_placeholder')" :aria-label="$t('apps.search_placeholder')" />
              <button v-if="searchQuery" type="button" class="btn-clear-search" :aria-label="$t('apps.clear_search')" @click="clearSearch"><i class="fas fa-times" aria-hidden="true"></i></button>
            </div>
          </div>
          <button class="btn btn-primary" type="button" :disabled="isSaving" @click="newApp">{{ $t('apps.add_new') }}</button>
        </template>
      </PageHeader>
      <section class="apps-guide mb-4">
        <p>{{ shellT.appsGuide.body }} {{ shellT.appsGuide.restorePrefix }} <button class="restore-inline" type="button" :disabled="isSaving" @click="restoreDefaultApps">{{ shellT.appsGuide.restoreLabel }}</button> {{ shellT.appsGuide.restoreSuffix }}</p>
      </section>
      <div class="apps-grid-container">
        <draggable v-if="!searchQuery" v-model="apps" :item-key="getAppRenderKey" class="apps-grid" handle=".drag-handle" :disabled="isSaving" :delay="180" :delay-on-touch-only="true" :touch-start-threshold="8" :fallback-tolerance="8" ghost-class="app-card-ghost" @start="onDragStart" @end="onDragEnd">
          <template #item="{ element: app, index }">
            <div class="app-card-wrapper">
              <AppCard :app="app" :disabled="isSaving" :is-dragging="isDragging" @edit="editApp(index)" @delete="showDeleteForm(index)" @copy-success="handleCopySuccess" @copy-error="handleCopyError" />
            </div>
          </template>
        </draggable>
        <div v-else class="apps-grid">
          <div v-for="{ app, index } in filteredAppsWithIndex" :key="getAppRenderKey(app)" class="app-card-wrapper">
            <AppCard :app="app" :disabled="isSaving" :draggable="false" :is-search-result="true" @edit="editApp(index)" @delete="showDeleteForm(index)" @copy-success="handleCopySuccess" @copy-error="handleCopyError" />
          </div>
        </div>
        <div v-if="!filteredAppsWithIndex.length" class="empty-state" role="status"><p>{{ $t(searchQuery ? 'apps.scan_result_no_matches' : 'apps.no_apps') }}</p></div>
      </div>
      <div v-if="message" class="alert app-status mt-3" :class="messageClass" role="status">{{ message }}</div>
      <AppEditor v-if="editingApp" :app="editingApp" :platform="platform" :disabled="isSaving" @save-app="handleSaveApp" @close="closeAppEditor" />
      <ConfirmDialog :show="deleteConfirmIndex !== null" dialog-id="delete-app-confirm" :title="$t('_common.delete')" :close-label="$t('_common.cancel')" @close="cancelDeleteApp">
        <p>{{ apps[deleteConfirmIndex]?.name }}</p>
        <template #actions>
      <div class="search-container apps-heading-search">
        <div class="search-box">
          <i class="fas fa-search search-icon" aria-hidden="true"></i>
          <input class="form-control search-input" v-model="searchQuery" :placeholder="$t('apps.search_placeholder')" :aria-label="$t('apps.search_placeholder')" />
          <button v-if="searchQuery" type="button" class="btn-clear-search" :aria-label="$t('apps.clear_search')" @click="clearSearch"><i class="fas fa-times" aria-hidden="true"></i></button>
        </div>
      </div>
<button class="btn btn-danger" @click="confirmDeleteApp">{{ $t('_common.delete') }}</button></template>
      </ConfirmDialog>
    </main>
  </div>
</template>
<script setup>
import { defineAsyncComponent, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useI18n as useShellI18n } from '@/desktop/i18n/index.js'
import Navbar from '../components/layout/Navbar.vue'
import PageHeader from '../components/common/PageHeader.vue'
import ConfirmDialog from '../components/common/ConfirmDialog.vue'
import { useApps } from '../composables/useApps.js'
import AppCard from '../components/AppCard.vue'
import draggable from 'vuedraggable-es'
const AppEditor = defineAsyncComponent(() => import('../components/AppEditor.vue'))
const { t } = useI18n()
const { t: shellT } = useShellI18n()
const { apps, filteredAppsWithIndex, getAppRenderKey, searchQuery, clearSearch, debouncedSearch, editingApp, platform, isSaving, isDragging, message, messageClass, init, loadApps, loadPlatform, newApp, editApp, closeAppEditor, handleSaveApp, showDeleteForm, deleteConfirmIndex, cancelDeleteApp, confirmDeleteApp, restoreDefaultApps, onDragStart, onDragEnd, handleCopySuccess, handleCopyError } = useApps()
onMounted(async () => { init(t); await Promise.all([loadApps(), loadPlatform()]) })
watch(searchQuery, () => debouncedSearch.value?.())
</script>
<style lang="less">
@import '../styles/global.less';
@import '../styles/apps/mixins.less';
@import '../styles/apps/toolbar.less';
@import '../styles/apps/app-cards.less';
@import '../styles/apps/feedback.less';
.apps-page .app-card { animation:none; }
.apps-page .app-card:hover { transform:none; }
.apps-page .apps-heading-search { margin:0; gap:0; flex-wrap:nowrap; }
.apps-page .apps-heading-search .search-box { width:240px; min-width:0; max-width:100%; }
.apps-heading-search .search-input { padding:8px 32px 8px 38px; font-size:14px; }
.apps-heading-search .search-icon { left:10px; width:20px; height:20px; font-size:14px; }
.apps-heading-search .btn-clear-search { right:6px; }
.apps-guide { padding:24px; background:var(--fd-bg-secondary); border:1px solid rgba(var(--fd-text-primary-rgb), .16); border-radius:var(--ui-radius-lg); font-family:'Segoe UI', 'Microsoft YaHei', sans-serif; }
.apps-guide p { font-size:14px; line-height:1.9; margin:0; color:var(--fd-text-secondary); }
.restore-inline { display:inline; padding:0; border:0; background:none; color:var(--fd-accent); font:inherit; text-decoration:underline; text-underline-offset:3px; cursor:pointer; }
.restore-inline:hover { color:var(--fd-text-primary); }
.restore-inline:disabled { opacity:.5; cursor:default; }
@media (max-width:600px) { .apps-page .apps-heading-search .search-box { width:min(240px, 55vw); } }
.app-status.alert { background:var(--ui-surface-strong); border-radius:var(--ui-radius-md); box-shadow:var(--ui-shadow-sm); }
.app-status.alert-error { color:var(--ui-danger-text); border-color:var(--ui-danger-border); }
</style>
