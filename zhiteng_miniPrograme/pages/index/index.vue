<template>
  <view class="page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="知疼" />

    <view class="page-shell page-shell--tabbar">
    <view class="hero">
      <view>
        <text class="hero__eyebrow">让每一次疼痛，都被看见。</text>
        <text class="hero__title">现在感觉怎么样？</text>
        <text class="hero__copy">如果现在不舒服，先记录最重要的信息就好。</text>
      </view>
      <view class="hero__mark">知疼</view>
    </view>

    <view v-if="ongoingRecord" class="ongoing surface-card tap-card" @click="goHistory">
      <view>
        <text class="ongoing__tag">进行中</text>
        <text class="ongoing__title">{{ ongoingRecord.locations.map((item) => item.name).join('、') }}</text>
        <text class="ongoing__caption">可以继续记录变化，或确认这次疼痛已经结束。</text>
      </view>
      <text class="ongoing__arrow">›</text>
    </view>

    <view class="record-card surface-card">
      <view class="record-card__heading">
        <view>
          <text class="section-title">从身体上找找看</text>
          <text class="section-caption">不需要知道准确部位，先点大概位置。</text>
        </view>
        <text class="record-card__link" @click="startRecord">查看全身</text>
      </view>

      <view class="focus-grid">
        <view v-for="part in focusParts" :key="part.name" class="focus-card tap-card" @click="startRecord(part.name)">
          <view class="focus-card__icon">{{ part.icon }}</view>
          <view>
            <text class="focus-card__name">{{ part.name }}</text>
            <text class="focus-card__caption">快速记录</text>
          </view>
        </view>
        <view class="focus-card focus-card--other tap-card" @click="startRecord()">
          <view class="focus-card__icon">＋</view>
          <view>
            <text class="focus-card__name">其他部位</text>
            <text class="focus-card__caption">查看全身</text>
          </view>
        </view>
      </view>

      <AppButton @click="startRecord()">记一次疼痛</AppButton>
    </view>

    <view class="quick-row">
      <view class="quick-card surface-card tap-card" @click="goHistory">
        <text class="quick-card__icon">◷</text>
        <text class="quick-card__title">最近记录</text>
        <text class="quick-card__caption">{{ records.length ? `已有 ${records.length} 次` : '还没有记录' }}</text>
      </view>
      <view class="quick-card surface-card tap-card" @click="goTrends">
        <text class="quick-card__icon">↗</text>
        <text class="quick-card__title">变化趋势</text>
        <text class="quick-card__caption">从第一次开始回看</text>
      </view>
    </view>

    <view class="care-card">
      <text class="care-card__title">说不清也没关系</text>
      <text class="care-card__copy">我们先把发生的事情留下来。知疼只整理你的记录，不提供疾病诊断。</text>
    </view>
    </view>

    <AppTabBar value="index" />
  </view>
</template>

<script setup>
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import AppButton from '../../components/ui/AppButton.vue'
import AppNavbar from '../../components/ui/AppNavbar.vue'
import AppTabBar from '../../components/ui/AppTabBar.vue'
import { useAppStore } from '../../stores/app'
import { listRecords } from '../../services/recordRepository'

const app = useAppStore()
const records = ref([])
const focusParts = [
  { name: '头部', icon: '头' },

  { name: '颈肩', icon: '颈' }
]

const ongoingRecord = computed(() => records.value.find((record) => record.status === 'ongoing'))

onShow(() => {
  records.value = listRecords()
  if (app.state.ready && !app.state.onboardingCompleted) {
    uni.navigateTo({ url: '/pages/onboarding/index' })
  }
})

function startRecord(partName = '') {
  const query = partName ? `?part=${encodeURIComponent(partName)}` : ''
  if (!app.state.authenticated) {
    uni.navigateTo({ url: `/pages/login/index?next=${encodeURIComponent(`/packages/locate/pages/record/index${query}`)}` })
    return
  }
  uni.navigateTo({ url: `/packages/locate/pages/record/index${query}` })
}

function goHistory() {
  uni.redirectTo({ url: '/pages/history/index' })
}

function goTrends() {
  if (!app.state.authenticated) {
    uni.navigateTo({ url: `/pages/login/index?next=${encodeURIComponent('/pages/trends/index')}` })
    return
  }
  uni.navigateTo({ url: '/pages/trends/index' })
}
</script>

<style scoped>
.hero { display: flex; align-items: flex-start; justify-content: space-between; padding: 24rpx 8rpx 36rpx; }
.hero__eyebrow { display: block; margin-bottom: 12rpx; color: var(--color-primary); font-size: 24rpx; font-weight: 650; }
.hero__title { display: block; color: var(--color-text-primary); font-size: 48rpx; font-weight: 720; letter-spacing: -1rpx; }
.hero__copy { display: block; max-width: 500rpx; margin-top: 14rpx; color: var(--color-text-secondary); font-size: 27rpx; line-height: 1.55; }
.hero__mark { display: flex; width: 88rpx; height: 88rpx; align-items: center; justify-content: center; border-radius: 28rpx; background: var(--color-primary-soft); color: var(--color-primary-pressed); font-size: 25rpx; font-weight: 750; }
.ongoing { display: flex; align-items: center; justify-content: space-between; margin-bottom: 24rpx; padding: 26rpx; }
.ongoing__tag { display: inline-block; margin-bottom: 8rpx; padding: 5rpx 14rpx; border-radius: 999rpx; background: var(--color-primary-soft); color: var(--color-primary-pressed); font-size: 21rpx; }
.ongoing__title { display: block; font-size: 30rpx; font-weight: 650; }
.ongoing__caption { display: block; margin-top: 6rpx; color: var(--color-text-secondary); font-size: 24rpx; }
.ongoing__arrow { color: var(--color-text-tertiary); font-size: 52rpx; }
.record-card { padding: 28rpx; }
.record-card__heading { display: flex; align-items: flex-start; justify-content: space-between; }
.record-card__link { padding: 8rpx 0 8rpx 20rpx; color: var(--color-primary); font-size: 25rpx; }
.focus-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16rpx; margin: 28rpx 0; }
.focus-card { display: flex; min-height: 116rpx; align-items: center; box-sizing: border-box; padding: 18rpx; border: 1rpx solid var(--color-border); border-radius: 22rpx; background: var(--color-bg-subtle); }
.focus-card__icon { display: flex; width: 62rpx; height: 62rpx; margin-right: 16rpx; align-items: center; justify-content: center; border-radius: 50%; background: var(--color-body-focus); color: var(--color-primary-pressed); font-size: 23rpx; font-weight: 700; }
.focus-card__name { display: block; font-size: 27rpx; font-weight: 650; }
.focus-card__caption { display: block; margin-top: 4rpx; color: var(--color-text-secondary); font-size: 22rpx; }
.focus-card--other { background: transparent; }
.quick-row { display: grid; grid-template-columns: 1fr 1fr; gap: 18rpx; margin-top: 22rpx; }
.quick-card { padding: 24rpx; }
.quick-card__icon { display: block; color: var(--color-primary); font-size: 38rpx; }
.quick-card__title { display: block; margin-top: 18rpx; font-size: 28rpx; font-weight: 650; }
.quick-card__caption { display: block; margin-top: 7rpx; color: var(--color-text-secondary); font-size: 22rpx; }
.care-card { margin-top: 22rpx; padding: 26rpx; border-radius: 24rpx; background: var(--color-bg-warm); }
.care-card__title { display: block; color: var(--color-text-primary); font-size: 27rpx; font-weight: 650; }
.care-card__copy { display: block; margin-top: 8rpx; color: var(--color-text-secondary); font-size: 24rpx; line-height: 1.6; }
</style>
