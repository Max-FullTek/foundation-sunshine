<template>
  <div class="accordion-item">
    <h2 class="accordion-header" :id="id + 'Heading'">
      <button
        class="accordion-button"
        :class="{ collapsed: !show }"
        type="button"
        data-bs-toggle="collapse"
        :data-bs-target="'#' + id + 'Collapse'"
        :aria-expanded="show"
        :aria-controls="id + 'Collapse'"
      >
        <i :class="['fas', icon, 'me-2']"></i>{{ title }}
      </button>
    </h2>
    <div
      :id="id + 'Collapse'"
      class="accordion-collapse collapse"
      :class="{ show }"
      :aria-labelledby="id + 'Heading'"
      :data-bs-parent="'#' + parentId"
    >
      <div class="accordion-body">
        <slot></slot>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'AccordionItem',
  props: {
    id: { type: String, required: true },
    icon: { type: String, required: true },
    title: { type: String, required: true },
    parentId: { type: String, required: true },
    show: { type: Boolean, default: false },
  },
}
</script>

<style scoped>
.accordion-item {
  --bs-accordion-color: var(--ui-text-primary);
  --bs-accordion-bg: var(--ui-surface);
  --bs-accordion-border-color: var(--ui-border);
  --bs-accordion-btn-color: var(--ui-text-primary);
  --bs-accordion-btn-bg: var(--ui-surface);
  --bs-accordion-active-color: var(--ui-accent);
  --bs-accordion-active-bg: var(--ui-accent-soft);
  --bs-accordion-btn-focus-box-shadow: 0 0 0 3px var(--ui-accent-soft);
}
.accordion-button::after {
  background-image: none;
  width: 9px;
  height: 9px;
  border-right: 1.5px solid currentColor;
  border-bottom: 1.5px solid currentColor;
  transform: rotate(45deg);
}
.accordion-button:not(.collapsed)::after { transform: rotate(225deg); }
</style>
