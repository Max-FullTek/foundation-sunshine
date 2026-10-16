<template>
  <div class="apps-page">
    <Navbar />
    <main class="container-fluid">
      <PageHeader page="apps">
        <template #actions>
          <button class="btn btn-primary" type="button" :disabled="isSaving" @click="newApp">{{ $t('apps.add_new') }}</button>
          <button class="btn btn-outline-secondary" type="button" :disabled="isSaving" @click="restoreDefaultApps">{{ $t('apps.restore_default_apps') }}</button>
        </template>
      </PageHeader>
      <details open class="apps-guide mb-4">
        <summary>{{ shellT.appsGuide.title }}</summary>
        <p>{{ shellT.appsGuide.body }}</p>
        <p>{{ shellT.appsGuide.restore }}</p>
      </details>
      <div class="search-container mb-4">
        <div class="search-box">
          <i class="fas fa-search search-icon" aria-hidden="true"></i>
          <input class="form-control search-input" v-model="searchQuery" :placeholder="$t('apps.search_placeholder')" :aria-label="$t('apps.search_placeholder')" />
          <button v-if="searchQuery" type="button" class="btn-clear-search" :aria-label="$t('apps.clear_search')" @click="clearSearch"><i class="fas fa-times" aria-hidden="true"></i></button>
        </div>
      </div>
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
        <template #actions><button class="btn btn-danger" @click="confirmDeleteApp">{{ $t('_common.delete') }}</button></template>
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
.apps-page .search-container { justify-content:flex-start; }
.apps-page .search-box { max-width:520px; width:100%; }
.apps-guide { color:var(--ui-text-secondary); font-size:13px; line-height:1.7; }
.apps-guide summary { cursor:pointer; color:var(--ui-text-primary); }
.apps-guide p { max-width:900px; margin:10px 0 0; }
.app-status.alert { background:var(--ui-surface-strong); border-radius:var(--ui-radius-md); box-shadow:var(--ui-shadow-sm); }
.app-status.alert-error { color:var(--ui-danger-text); border-color:var(--ui-danger-border); }
</style>
