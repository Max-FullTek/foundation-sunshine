<template>
  <div class="apps-page">
    <Navbar />
    <main class="container-fluid">
      <PageHeader page="apps">
        <template #actions>
          <button class="btn btn-primary" type="button" @click="newApp">{{ $t('apps.add_new') }}</button>
          <button class="btn btn-outline-secondary" type="button" :disabled="isSaving" @click="restoreDefaultApps">{{ $t('apps.restore_default_apps') }}</button>
        </template>
      </PageHeader>
      <section class="card p-3">
        <input class="form-control mb-3" v-model="searchQuery" :placeholder="$t('apps.search_placeholder')" :aria-label="$t('apps.search_placeholder')" />
        <div class="table-responsive">
          <table class="table align-middle mb-0">
            <thead><tr><th>{{ $t('apps.app_name') }}</th><th>{{ $t('apps.cmd') }}</th><th></th></tr></thead>
            <tbody>
              <tr v-for="{ app, index } in filteredAppsWithIndex" :key="getAppRenderKey(app)">
                <td>{{ app.name }}</td><td class="app-command">{{ app.cmd || '—' }}</td>
                <td class="text-end">
                  <button class="btn btn-outline-secondary btn-sm me-2" :disabled="isSaving" @click="editApp(index)">{{ $t('apps.edit') }}</button>
                  <button class="btn btn-outline-danger btn-sm" :disabled="isSaving" @click="showDeleteForm(index)">{{ $t('_common.delete') }}</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
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
const AppEditor = defineAsyncComponent(() => import('../components/AppEditor.vue'))
const { t } = useI18n()
const { apps, filteredAppsWithIndex, getAppRenderKey, searchQuery, debouncedSearch, editingApp, platform, isSaving, message, messageClass, init, loadApps, loadPlatform, newApp, editApp, closeAppEditor, handleSaveApp, showDeleteForm, deleteConfirmIndex, cancelDeleteApp, confirmDeleteApp, restoreDefaultApps } = useApps()
onMounted(async () => { init(t); await Promise.all([loadApps(), loadPlatform()]) })
watch(searchQuery, () => debouncedSearch.value?.())
</script>
<style>
@import '../styles/global.less';
.app-command { max-width:480px; overflow-wrap:anywhere; }
</style>
