<template>
  <view class="pain-levels" role="radiogroup" aria-label="疼痛强度">
    <view
      v-for="item in levels"
      :key="item.level"
      class="pain-level tap-card"
      :class="{ 'pain-level--selected': modelValue === item.level }"
      role="radio"
      :aria-checked="modelValue === item.level"
      @click="$emit('update:modelValue', item.level)"
    >
      <text class="pain-level__score">{{ item.value }}</text>
      <text class="pain-level__label">{{ item.label }}</text>
    </view>
  </view>
</template>

<script setup>
defineProps({
  modelValue: { type: Number, default: 0 }
})

defineEmits(['update:modelValue'])

const levels = [
  { level: 1, value: '1/10', label: '轻微' },
  { level: 2, value: '3/10', label: '能忍受' },
  { level: 3, value: '5/10', label: '影响做事' },
  { level: 4, value: '7/10', label: '很难受' },
  { level: 5, value: '9/10', label: '无法忍受' }
]
</script>

<style scoped>
.pain-levels {
  display: flex;
  gap: 12rpx;
  width: 100%;
}

.pain-level {
  display: flex;
  flex: 1;
  min-width: 0;
  min-height: 112rpx;
  box-sizing: border-box;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2rpx solid var(--color-border);
  border-radius: 20rpx;
  background: var(--color-bg-subtle);
  color: var(--color-text-secondary);
}

.pain-level--selected {
  border-color: var(--color-primary);
  background: var(--color-primary-soft);
  color: var(--color-primary-pressed);
}

.pain-level__score {
  font-size: 24rpx;
  font-weight: 700;
}

.pain-level__label {
  margin-top: 7rpx;
  font-size: 21rpx;
  line-height: 1.2;
  text-align: center;
}
</style>
