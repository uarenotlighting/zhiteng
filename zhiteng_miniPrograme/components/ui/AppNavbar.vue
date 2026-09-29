<template>
  <view class="app-navbar-host">
    <view
      v-if="fixed && placeholder"
      class="app-navbar-host__placeholder"
      :style="{ height: `${navbarTotalHeight}px` }"
    />
    <view
      class="app-navbar-host__fixed"
      :class="{ 'app-navbar-host__fixed--attached': fixed }"
      :style="fixedStyle"
    >
      <view class="app-navbar-host__bar" :style="barStyle">
        <view class="app-navbar-host__side app-navbar-host__side--left">
          <view
            v-if="leftArrow"
            class="app-navbar-host__back"
            hover-class="app-navbar-host__back--active"
            @tap.stop="goBack"
          >
            <text class="app-navbar-host__back-icon">‹</text>
          </view>
          <slot name="left" />
        </view>

        <view class="app-navbar-host__title">
          <slot name="title">
            <text v-if="title" class="app-navbar-host__title-text">{{ title }}</text>
          </slot>
        </view>

        <view class="app-navbar-host__side app-navbar-host__side--right" @click="$emit('right-click')">
          <slot name="right" />
        </view>
      </view>
    </view>
  </view>
</template>

<script setup>
import { computed, ref } from 'vue'
import { getSafeAreaMetrics } from '../../utils/safeArea'

const props = defineProps({
  title: { type: String, default: '' },
  leftArrow: { type: Boolean, default: false },
  fixed: { type: Boolean, default: true },
  placeholder: { type: Boolean, default: true },
  safeAreaInsetTop: { type: Boolean, default: true },
  delta: { type: Number, default: 1 },
  /** 页面栈不足时（如 login reLaunch 直达）的回退地址 */
  fallbackUrl: { type: String, default: '/pages/index/index' },
  zIndex: { type: Number, default: 100 }
})

const emit = defineEmits(['go-back', 'complete', 'fail', 'success', 'right-click'])

const metrics = ref(getSafeAreaMetrics())

const statusBarHeight = computed(() => (props.safeAreaInsetTop ? metrics.value.statusBarHeight : 0))
const navBarHeight = computed(() => metrics.value.navBarHeight)
const navbarTotalHeight = computed(() => statusBarHeight.value + navBarHeight.value)

const fixedStyle = computed(() => ({
  paddingTop: `${statusBarHeight.value}px`,
  height: `${navbarTotalHeight.value}px`,
  zIndex: props.zIndex
}))

const barStyle = computed(() => ({
  height: `${navBarHeight.value}px`,
  paddingRight: `${Math.max(metrics.value.capsuleRight - 12, 12)}px`
}))

function fallbackBack() {
  const url = props.fallbackUrl || '/pages/index/index'
  uni.reLaunch({ url })
}

function goBack() {
  emit('go-back')
  if (props.delta <= 0) return

  const stack = typeof getCurrentPages === 'function' ? getCurrentPages() : []
  if (!stack || stack.length <= 1) {
    fallbackBack()
    return
  }

  uni.navigateBack({
    delta: Math.min(props.delta, stack.length - 1),
    fail(e) {
      emit('fail', e)
      fallbackBack()
    },
    complete(e) {
      emit('complete', e)
    },
    success(e) {
      emit('success', e)
    }
  })
}
</script>

<style>
.app-navbar-host__placeholder {
  width: 100%;
}

.app-navbar-host__fixed {
  box-sizing: border-box;
  width: 100%;
  background: var(--color-bg-page);
  color: var(--color-text-primary);
}

.app-navbar-host__fixed--attached {
  position: fixed;
  top: 0;
  right: 0;
  left: 0;
}

.app-navbar-host__bar {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-sizing: border-box;
  padding-left: 12rpx;
}

.app-navbar-host__side {
  z-index: 1;
  display: flex;
  min-width: 80rpx;
  align-items: center;
}

.app-navbar-host__side--right {
  justify-content: flex-end;
}

.app-navbar-host__back {
  display: flex;
  width: 64rpx;
  height: 64rpx;
  align-items: center;
  justify-content: center;
}

.app-navbar-host__back--active {
  opacity: 0.65;
}

.app-navbar-host__back-icon {
  color: var(--color-text-primary);
  font-size: 48rpx;
  line-height: 1;
  font-weight: 500;
}

.app-navbar-host__title {
  position: absolute;
  top: 0;
  right: 160rpx;
  bottom: 0;
  left: 160rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  pointer-events: none;
}

.app-navbar-host__title-text {
  max-width: 100%;
  color: var(--color-text-primary);
  font-size: 34rpx;
  font-weight: 650;
  line-height: 1.2;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
</style>
