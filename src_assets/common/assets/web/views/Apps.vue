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
      <div v-if="message" class="alert mt-3" :class="messageClass" role="status">{{ message }}</div>
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
import Navbar from '../components/layout/Navbar.vue'
import PageHeader from '../components/common/PageHeader.vue'
import ConfirmDialog from '../components/common/ConfirmDialog.vue'
import { useApps } from '../composables/useApps.js'
import AppCard from '../components/AppCard.vue'
import draggable from 'vuedraggable-es'
const AppEditor = defineAsyncComponent(() => import('../components/AppEditor.vue'))
const { t } = useI18n()
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
@media (max-width:600px) { .apps-page .apps-grid { grid-template-columns:1fr; } }
</style>
