<template>
  <view class="page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="我的" />

    <view class="page-shell page-shell--tabbar">
    <view class="profile-card surface-card">
      <view class="profile-card__avatar">知</view>
      <view>
        <text class="profile-card__name">知疼</text>
        <text class="profile-card__status">前端开发阶段 · 后端账号尚未接入</text>
      </view>
    </view>

    <view class="settings surface-card">
      <text class="settings__title">显示设置</text>
      <view class="setting-row">
        <view>
          <text class="setting-row__label">主题模式</text>
          <text class="setting-row__caption">暗色模式会降低发作时的视觉刺激</text>
        </view>
      </view>
      <view class="theme-options">
        <view v-for="item in themeOptions" :key="item.value" class="theme-option" :class="{ 'theme-option--active': app.state.theme === item.value }" @click="app.setTheme(item.value)">{{ item.label }}</view>
      </view>
    </view>

    <view class="settings surface-card">
      <view class="menu-row tap-card" @click="openOnboarding">
        <text>重新查看新手引导</text><text>›</text>
      </view>
      <view class="menu-row tap-card" @click="showPending('关注部位管理')">
        <text>关注部位管理</text><text>›</text>
      </view>
      <view class="menu-row tap-card" @click="showPending('数据导出')">
        <text>导出我的记录</text><text>›</text>
      </view>
      <view class="menu-row menu-row--danger tap-card" @click="confirmDelete">
        <text>删除本地演示记录</text><text>›</text>
      </view>
    </view>

    <view class="boundary-card">
      <text class="boundary-card__title">产品边界</text>
      <text class="boundary-card__copy">知疼帮助你描述、保存和整理主观感受，不判断疾病，不替代医生，也不会推荐具体药物。</text>
    </view>
    </view>

    <AppTabBar value="profile" />
  </view>
</template>

<script setup>
import AppNavbar from '../../components/ui/AppNavbar.vue'
import AppTabBar from '../../components/ui/AppTabBar.vue'
import { useAppStore } from '../../stores/app'
import { deleteAllLocalDemoRecords } from '../../services/recordRepository'

const app = useAppStore()
const themeOptions = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '暗色' }
]

function openOnboarding() {
  uni.navigateTo({ url: '/pages/onboarding/index?replay=1' })
}

function showPending(name) {
  uni.showToast({ title: `${name}将在下一阶段接入`, icon: 'none' })
}

function confirmDelete() {
  uni.showModal({
    title: '删除本地演示记录？',
    content: '删除后无法找回。当前只会删除前端开发阶段保存在本机的演示数据。',
    confirmText: '确认删除',
    confirmColor: app.state.resolvedTheme === 'dark' ? '#E8E8E8' : '#141414',
    success(result) {
      if (!result.confirm) return
      deleteAllLocalDemoRecords()
      uni.showToast({ title: '已删除', icon: 'success' })
    }
  })
}
</script>

<style scoped>
.profile-card { display: flex; align-items: center; padding: 28rpx; }
.profile-card__avatar { display: flex; width: 90rpx; height: 90rpx; margin-right: 20rpx; align-items: center; justify-content: center; border-radius: 30rpx; background: var(--color-primary-soft); color: var(--color-primary-pressed); font-size: 34rpx; font-weight: 750; }
.profile-card__name { display: block; font-size: 34rpx; font-weight: 680; }
.profile-card__status { display: block; margin-top: 7rpx; color: var(--color-text-secondary); font-size: 23rpx; }
.settings { margin-top: 22rpx; padding: 26rpx; }
.settings__title { display: block; margin-bottom: 20rpx; font-size: 30rpx; font-weight: 680; }
.setting-row__label { display: block; font-size: 27rpx; font-weight: 620; }
.setting-row__caption { display: block; margin-top: 7rpx; color: var(--color-text-secondary); font-size: 22rpx; }
.theme-options { display: flex; gap: 12rpx; margin-top: 22rpx; }
.theme-option { flex: 1; padding: 17rpx 8rpx; border: 2rpx solid var(--color-border); border-radius: 999rpx; color: var(--color-text-secondary); font-size: 23rpx; text-align: center; }
.theme-option--active { border-color: var(--color-primary); background: var(--color-primary-soft); color: var(--color-primary-pressed); font-weight: 650; }
.menu-row { display: flex; min-height: 92rpx; align-items: center; justify-content: space-between; border-bottom: 1rpx solid var(--color-border); color: var(--color-text-primary); font-size: 27rpx; }
.menu-row:last-child { border-bottom: 0; }
.menu-row--danger { color: var(--td-error-color-6); }
.boundary-card { margin-top: 22rpx; padding: 26rpx; border-radius: 24rpx; background: var(--color-bg-warm); }
.boundary-card__title { display: block; font-size: 27rpx; font-weight: 650; }
.boundary-card__copy { display: block; margin-top: 8rpx; color: var(--color-text-secondary); font-size: 24rpx; line-height: 1.6; }
</style>
