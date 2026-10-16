<template>
  <header class="lite-page-header">
    <div class="lite-page-title">
      <span class="lite-page-icon" aria-hidden="true"><i :class="icon"></i></span>
      <div><h1>{{ title }}</h1><p v-if="description">{{ description }}</p></div>
    </div>
    <div v-if="$slots.actions" class="lite-page-actions"><slot name="actions" /></div>
  </header>
</template>
<script setup>
defineProps({ title: String, description: String, icon: String })
</script>
<style>
.lite-page-header { display:flex; align-items:center; justify-content:space-between; flex-wrap:wrap; gap:16px; padding:10px 0 20px; }
.lite-page-title { display:flex; align-items:center; gap:14px; min-width:0; }
.lite-page-title h1 { font-size:26px; font-weight:650; line-height:1.3; margin:0; color:var(--ui-text-primary); }
.lite-page-title p { margin:6px 0 0; font-size:14px; color:var(--ui-text-secondary); }
.lite-page-icon { display:flex; align-items:center; justify-content:center; flex:0 0 52px; width:52px; height:52px; border:1px solid var(--ui-border); border-radius:14px; background:var(--ui-surface); font-size:25px; }
.lite-page-actions { display:flex; align-items:center; flex-wrap:wrap; gap:10px; }
.page-config > .container, .pin-page > .container, .apps-page > .container-fluid { width:100%; max-width:1440px; margin:0 auto; padding:20px 24px 32px !important; }
.page-config > .config-heading-container { padding-bottom:0 !important; }
.page-config > .config-content-container { padding-top:0 !important; }
.page-config .lite-page-header .config-floating-buttons { position:static; float:none; clear:none; top:auto; right:auto; margin:0; display:flex; flex-direction:row; align-items:center; gap:10px; }
.lite-page-header .floating-toast-container { position:fixed; right:24px; bottom:48px; z-index:1100; }
</style>
