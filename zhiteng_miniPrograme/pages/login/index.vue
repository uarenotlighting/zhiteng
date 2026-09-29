<template>
  <view class="page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="登录知疼" left-arrow />

    <view class="page-shell login-page">
      <view class="login-card surface-card">
        <view class="login-card__mark">知</view>
        <text class="login-card__title">登录后开始记录</text>
        <text class="login-card__copy">健康记录会归属于你的平台账号。后端接口尚未接入，本页目前只保留正式登录流程的位置。</text>
        <AppButton :loading="loading" @click="login">{{ platformName }}账号登录</AppButton>
        <text class="login-card__agreement">继续表示你同意后续上线的用户协议和隐私政策。正式版本会在这里提供完整内容与确认。</text>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import AppButton from '../../components/ui/AppButton.vue'
import AppNavbar from '../../components/ui/AppNavbar.vue'
import { useAppStore } from '../../stores/app'

const app = useAppStore()
const loading = ref(false)
const nextPath = ref('')
let platformName = '当前平台'
// #ifdef MP-WEIXIN
platformName = '微信'
// #endif
// #ifdef MP-TOUTIAO
platformName = '抖音'
// #endif

onLoad((query) => {
  nextPath.value = query?.next ? decodeURIComponent(query.next) : ''
})

function login() {
  if (loading.value) return
  loading.value = true
  uni.login({
    success() {
      app.completeFrontendLogin()
      uni.showToast({ title: '已登录', icon: 'success' })
      const target = nextPath.value || '/pages/index/index'
      setTimeout(() => {
        uni.reLaunch({ url: target })
      }, 200)
    },
    fail() {
      uni.showToast({ title: '未能获取平台登录凭证', icon: 'none' })
    },
    complete() {
      loading.value = false
    }
  })
}
</script>

<style scoped>
.login-page { display: flex; flex-direction: column; }
.login-card { width: 100%; margin-top: 48rpx; padding: 48rpx 32rpx; text-align: center; }
.login-card__mark { display: flex; width: 112rpx; height: 112rpx; margin: 0 auto 28rpx; align-items: center; justify-content: center; border-radius: 38rpx; background: var(--color-primary-soft); color: var(--color-primary-pressed); font-size: 44rpx; font-weight: 750; }
.login-card__title { display: block; font-size: 40rpx; font-weight: 720; }
.login-card__copy { display: block; margin: 18rpx 0 34rpx; color: var(--color-text-secondary); font-size: 26rpx; line-height: 1.65; }
.login-card__agreement { display: block; margin-top: 22rpx; color: var(--color-text-tertiary); font-size: 21rpx; line-height: 1.6; }
</style>
