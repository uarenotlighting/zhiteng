<template>
  <t-button
    :theme="theme"
    :variant="variant"
    :size="size"
    :block="block"
    :disabled="disabled"
    :loading="loading"
    :custom-style="customStyle"
    @click="$emit('click', $event)"
  >
    <slot />
  </t-button>
</template>

<script setup>
defineProps({
  theme: { type: String, default: 'primary' },
  variant: { type: String, default: 'base' },
  size: { type: String, default: 'large' },
  block: { type: Boolean, default: true },
  disabled: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  customStyle: {
    type: String,
    default: 'border-radius: 999px; min-height: 52px; font-weight: 600;'
  }
})

defineEmits(['click'])
</script>
