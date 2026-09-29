<template>
  <view class="onboarding page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="认识知疼">
      <template #right>
        <text class="onboarding__skip" @click="finish(false)">跳过</text>
      </template>
    </AppNavbar>

    <view class="onboarding__body">
    <swiper class="onboarding__swiper" :current="current" @change="current = $event.detail.current">
      <swiper-item v-for="slide in slides" :key="slide.title">
        <view class="slide">
          <view class="slide__visual">
            <view class="pulse pulse--one" />
            <view class="pulse pulse--two" />
            <view class="slide__symbol">{{ slide.symbol }}</view>
          </view>
          <text class="slide__title">{{ slide.title }}</text>
          <text class="slide__copy">{{ slide.copy }}</text>
        </view>
      </swiper-item>
    </swiper>

    <view class="onboarding__bottom">
      <view class="dots">
        <view v-for="(_, index) in slides" :key="index" class="dot" :class="{ 'dot--active': current === index }" />
      </view>
      <AppButton v-if="current < slides.length - 1" @click="current += 1">继续</AppButton>
      <AppButton v-else @click="finish(true)">开始第一次记录</AppButton>
      <text v-if="current === slides.length - 1" class="onboarding__secondary" @click="finish(false)">暂时不记录，先进入首页</text>
    </view>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'
import AppButton from '../../components/ui/AppButton.vue'
import AppNavbar from '../../components/ui/AppNavbar.vue'
import { useAppStore } from '../../stores/app'

const app = useAppStore()
const current = ref(0)
const slides = [
  {
    symbol: '身',
    title: '从身体上找到它',
    copy: '不需要知道准确的医学部位，大概标出哪里不舒服就可以。'
  },
  {
    symbol: '记',
    title: '疼的时候少填一点',
    copy: '先记位置、程度和时间。等舒服一些，再补充感受、用药和备注。'
  },
  {
    symbol: '懂',
    title: '把变化慢慢整理清楚',
    copy: '记录会形成时间线、趋势和就医摘要，但不会替你诊断疾病。'
  }
]

function finish(startRecord) {
  app.completeOnboarding()
  if (startRecord) {
    uni.redirectTo({ url: '/pages/login/index?next=%2Fpages%2Frecord%2Findex' })
  } else {
    uni.navigateBack({ fail: () => uni.reLaunch({ url: '/pages/index/index' }) })
  }
}
</script>

<style scoped>
.onboarding { display: flex; min-height: 100vh; box-sizing: border-box; flex-direction: column; background: var(--color-bg-page); color: var(--color-text-primary); }
.onboarding__body { display: flex; flex: 1; box-sizing: border-box; flex-direction: column; padding: 0 32rpx calc(36rpx + env(safe-area-inset-bottom)); }
.onboarding__skip { padding: 16rpx 8rpx; color: var(--color-text-secondary); font-size: 25rpx; }
.onboarding__swiper { flex: 1; min-height: 780rpx; }
.slide { display: flex; height: 100%; box-sizing: border-box; flex-direction: column; align-items: center; justify-content: center; padding: 30rpx 18rpx; text-align: center; }
.slide__visual { position: relative; display: flex; width: 340rpx; height: 340rpx; align-items: center; justify-content: center; margin-bottom: 54rpx; }
.pulse { position: absolute; border-radius: 50%; background: var(--color-primary-soft); }
.pulse--one { width: 330rpx; height: 330rpx; opacity: 0.45; }
.pulse--two { width: 230rpx; height: 230rpx; opacity: 0.8; }
.slide__symbol { position: relative; display: flex; width: 130rpx; height: 130rpx; align-items: center; justify-content: center; border-radius: 44rpx; background: var(--color-primary); color: var(--color-on-primary); font-size: 52rpx; font-weight: 750; }
.slide__title { font-size: 42rpx; font-weight: 720; }
.slide__copy { max-width: 580rpx; margin-top: 22rpx; color: var(--color-text-secondary); font-size: 28rpx; line-height: 1.7; }
.onboarding__bottom { padding-top: 20rpx; }
.dots { display: flex; justify-content: center; gap: 12rpx; margin-bottom: 28rpx; }
.dot { width: 12rpx; height: 12rpx; border-radius: 999rpx; background: var(--color-border); }
.dot--active { width: 34rpx; background: var(--color-primary); }
.onboarding__secondary { display: block; margin-top: 20rpx; padding: 10rpx; color: var(--color-text-secondary); font-size: 24rpx; text-align: center; }
</style>
