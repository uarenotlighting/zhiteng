<template>
  <view class="app-tab-bar-host">
    <view
      v-if="fixed && placeholder"
      class="app-tab-bar-host__placeholder"
      :style="{ height: `${totalHeight}px` }"
    />
    <view
      class="app-tab-bar"
      :class="{ 'app-tab-bar--fixed': fixed }"
      :style="barStyle"
    >
      <view
        v-for="item in tabs"
        :key="item.value"
        class="app-tab-bar__item"
        :class="{
          'app-tab-bar__item--active': item.value === value,
          'app-tab-bar__item--busy': switching
        }"
        hover-class="app-tab-bar__item--pressed"
        :hover-start-time="0"
        :hover-stay-time="80"
        @tap.stop="onSelect(item)"
      >
        <view class="app-tab-bar__icon-wrap">
          <t-icon :name="item.icon" size="44rpx" :color="iconColor(item.value)" />
        </view>
        <text class="app-tab-bar__label">{{ item.label }}</text>
      </view>
    </view>
  </view>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useAppStore } from '../../stores/app'
import { getSafeAreaMetrics } from '../../utils/safeArea'

const props = defineProps({
  value: { type: String, required: true },
  fixed: { type: Boolean, default: true },
  placeholder: { type: Boolean, default: true },
  safeAreaInsetBottom: { type: Boolean, default: true },
  zIndex: { type: Number, default: 100 }
})

defineEmits(['change'])

const app = useAppStore()
const metrics = ref(getSafeAreaMetrics())
const switching = ref(false)
const contentHeight = 58
const safeBottom = computed(() => (props.safeAreaInsetBottom ? metrics.value.safeAreaBottom : 0))
const totalHeight = computed(() => contentHeight + safeBottom.value)

const barStyle = computed(() => ({
  paddingTop: '8px',
  paddingBottom: `${safeBottom.value}px`,
  zIndex: props.zIndex
}))

const tabs = [
  {
    value: 'index',
    label: '记录',
    icon: 'assignment',
    url: '/pages/index/index'
  },
  {
    value: 'history',
    label: '历史',
    icon: 'time',
    url: '/pages/history/index'
  },
  {
    value: 'profile',
    label: '我的',
    icon: 'user',
    url: '/pages/profile/index'
  }
]

function iconColor(tabValue) {
  const dark = app.state.resolvedTheme === 'dark'
  if (tabValue === props.value) return dark ? '#E8E8E8' : '#141414'
  return dark ? '#939393' : '#5E5E5E'
}

function onSelect(item) {
  if (!item || item.value === props.value || switching.value) return
  switching.value = true
  uni.redirectTo({
    url: item.url,
    fail() {
      uni.reLaunch({
        url: item.url,
        complete() {
          switching.value = false
        }
      })
    }
  })
}
</script>

<style>
.app-tab-bar-host__placeholder {
  width: 100%;
}

.app-tab-bar {
  display: flex;
  align-items: stretch;
  box-sizing: content-box;
  min-height: 50px;
  border-top: 1rpx solid var(--color-border);
  background: var(--color-bg-surface);
}

.app-tab-bar--fixed {
  position: fixed;
  right: 0;
  bottom: 0;
  left: 0;
}

.app-tab-bar__item {
  display: flex;
  flex: 1;
  min-height: 50px;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4rpx;
  color: var(--color-text-secondary);
}

.app-tab-bar__item--active {
  color: var(--color-primary);
}

.app-tab-bar__item--active .app-tab-bar__label {
  color: var(--color-primary);
  font-weight: 650;
}

.app-tab-bar__item--busy {
  pointer-events: none;
  opacity: 0.7;
}

.app-tab-bar__item--pressed {
  opacity: 0.72;
}

.app-tab-bar__icon-wrap {
  pointer-events: none;
  line-height: 1;
}

.app-tab-bar__label {
  pointer-events: none;
  color: inherit;
  font-size: 22rpx;
  line-height: 1.2;
  font-weight: 560;
}
</style>
