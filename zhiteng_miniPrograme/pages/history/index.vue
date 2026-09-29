<template>
  <view class="page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="疼痛记录" />

    <view class="page-shell page-shell--tabbar">
    <view class="history-header">
      <view>
        <text class="history-header__title">你的疼痛记录</text>
        <text class="history-header__copy">按发生时间回看，不评价记录多少。</text>
      </view>
      <view class="trend-entry tap-card" @click="goTrends">趋势 ↗</view>
    </view>

    <view class="range-row">
      <view v-for="range in ranges" :key="range" class="range-chip" :class="{ 'range-chip--active': activeRange === range }" @click="activeRange = range">{{ range }}</view>
    </view>

    <view v-if="records.length" class="record-list">
      <view v-for="record in records" :key="record.id" class="record surface-card tap-card">
        <view class="record__top">
          <view>
            <text class="record__time">{{ formatDateTime(record.startAt) }}</text>
            <text class="record__parts">{{ record.locations.map((item) => item.name).join('、') }}</text>
          </view>
          <text class="record__status" :class="{ 'record__status--ongoing': record.status === 'ongoing' }">{{ record.status === 'ongoing' ? '进行中' : '已结束' }}</text>
        </view>
        <view class="record__levels">
          <view v-for="location in record.locations" :key="location.key" class="record__level">
            <text>{{ location.name }}</text>
            <text>{{ levelText(location) }}</text>
          </view>
        </view>
        <text class="record__hint">详情补充、时间线和摘要将在下一开发阶段接入。</text>
      </view>
    </view>

    <view v-else class="empty surface-card">
      <view class="empty__mark">○</view>
      <text class="empty__title">还没有疼痛记录</text>
      <text class="empty__copy">这里会保存你的疼痛记录。需要时，从一次简单记录开始。</text>
      <AppButton @click="startRecord">记一次疼痛</AppButton>
    </view>
    </view>

    <AppTabBar value="history" />
  </view>
</template>

<script setup>
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import AppButton from '../../components/ui/AppButton.vue'
import AppNavbar from '../../components/ui/AppNavbar.vue'
import AppTabBar from '../../components/ui/AppTabBar.vue'
import { useAppStore } from '../../stores/app'
import { listRecords } from '../../services/recordRepository'
import { formatDateTime } from '../../utils/date'

const app = useAppStore()
const records = ref([])
const ranges = ['今天', '7天', '30天', '3个月']
const activeRange = ref('今天')
const labels = ['', '轻微', '能忍受', '影响做事', '很难受', '无法忍受']

onShow(() => {
  records.value = listRecords()
})

function levelText(location) {
  if (location?.intensity) return `${location.intensity}/10`
  return labels[location?.level] || '未填写'
}

function startRecord() {
  if (!app.state.authenticated) {
    uni.navigateTo({ url: `/pages/login/index?next=${encodeURIComponent('/packages/locate/pages/record/index')}` })
    return
  }
  uni.navigateTo({ url: '/packages/locate/pages/record/index' })
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
.history-header { display: flex; align-items: flex-start; justify-content: space-between; padding: 14rpx 4rpx 26rpx; }
.history-header__title { display: block; font-size: 44rpx; font-weight: 720; }
.history-header__copy { display: block; margin-top: 10rpx; color: var(--color-text-secondary); font-size: 25rpx; }
.trend-entry { padding: 15rpx 20rpx; border-radius: 999rpx; background: var(--color-primary-soft); color: var(--color-primary-pressed); font-size: 24rpx; font-weight: 650; }
.range-row { display: flex; gap: 12rpx; margin-bottom: 24rpx; }
.range-chip { flex: 1; padding: 15rpx 6rpx; border-radius: 999rpx; background: var(--color-bg-subtle); color: var(--color-text-secondary); font-size: 23rpx; text-align: center; }
.range-chip--active { background: var(--color-primary); color: var(--color-on-primary); }
.record { margin-bottom: 18rpx; padding: 26rpx; }
.record__top { display: flex; align-items: flex-start; justify-content: space-between; }
.record__time { display: block; color: var(--color-text-secondary); font-size: 23rpx; }
.record__parts { display: block; margin-top: 8rpx; font-size: 32rpx; font-weight: 680; }
.record__status { padding: 8rpx 14rpx; border-radius: 999rpx; background: var(--color-bg-subtle); color: var(--color-text-secondary); font-size: 21rpx; }
.record__status--ongoing { background: var(--color-primary-soft); color: var(--color-primary-pressed); }
.record__levels { margin-top: 20rpx; border-top: 1rpx solid var(--color-border); }
.record__level { display: flex; justify-content: space-between; padding-top: 16rpx; color: var(--color-text-primary); font-size: 25rpx; }
.record__hint { display: block; margin-top: 20rpx; color: var(--color-text-tertiary); font-size: 22rpx; }
.empty { margin-top: 60rpx; padding: 50rpx 32rpx; text-align: center; }
.empty__mark { color: var(--color-primary); font-size: 88rpx; }
.empty__title { display: block; margin-top: 12rpx; font-size: 32rpx; font-weight: 680; }
.empty__copy { display: block; margin: 12rpx 0 28rpx; color: var(--color-text-secondary); font-size: 25rpx; line-height: 1.6; }
</style>
