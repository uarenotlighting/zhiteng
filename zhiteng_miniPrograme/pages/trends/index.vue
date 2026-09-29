<template>
  <view class="page-root" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar title="变化趋势" left-arrow />

    <view class="page-shell">
    <view class="trends-header">
      <text class="trends-header__title">变化趋势</text>
      <text class="trends-header__copy">这是你记录下来的变化，不代表医学诊断。</text>
    </view>

    <view class="range-row">
      <view v-for="range in ranges" :key="range" class="range-chip" :class="{ 'range-chip--active': activeRange === range }" @click="activeRange = range">{{ range }}</view>
    </view>

    <view v-if="records.length" class="metrics">
      <view class="metric surface-card">
        <text class="metric__label">记录次数</text>
        <text class="metric__value">{{ records.length }}</text>
        <text class="metric__caption">当前前端演示数据</text>
      </view>
      <view class="metric surface-card">
        <text class="metric__label">最高强度</text>
        <text class="metric__value">{{ maxLevelValue }}/10</text>
        <text class="metric__caption">按每次事件最高值</text>
      </view>

      <view class="chart-card surface-card">
        <text class="section-title">每次事件的强度</text>
        <text class="section-caption">深色柱为最高值，浅色柱为当前已记录位置的平均值。</text>
        <view class="chart">
          <view v-for="record in records.slice(0, 8).reverse()" :key="record.id" class="chart__group">
            <view class="chart__bars">
              <view class="chart__bar chart__bar--average" :style="{ height: `${averageValue(record) * 16}rpx` }" />
              <view class="chart__bar chart__bar--max" :style="{ height: `${maxValue(record) * 16}rpx` }" />
            </view>
            <text class="chart__label">{{ shortDate(record.startAt) }}</text>
          </view>
        </view>
      </view>

      <view class="chart-card surface-card">
        <text class="section-title">常见位置</text>
        <view v-for="item in commonParts" :key="item.name" class="part-row">
          <text>{{ item.name }}</text>
          <view class="part-row__track"><view class="part-row__fill" :style="{ width: `${item.percent}%` }" /></view>
          <text>{{ item.count }} 次</text>
        </view>
      </view>
    </view>

    <view v-else class="empty surface-card">
      <text class="empty__title">完成第一次记录后，这里会开始呈现变化。</text>
      <text class="empty__copy">只有一条或两条记录时，也会如实显示对应的数据点。</text>
    </view>
    </view>
  </view>
</template>

<script setup>
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import AppNavbar from '../../components/ui/AppNavbar.vue'
import { useAppStore } from '../../stores/app'
import { listRecords } from '../../services/recordRepository'

const app = useAppStore()
const records = ref([])
const ranges = ['今天', '7天', '30天', '3个月']
const activeRange = ref('今天')
const mappedValues = [0, 1, 3, 5, 7, 9]

onShow(() => {
  if (!app.state.authenticated) {
    uni.navigateTo({ url: '/pages/login/index?next=%2Fpages%2Ftrends%2Findex' })
    return
  }
  records.value = listRecords()
})

function maxValue(record) {
  return Math.max(...record.locations.map((item) => mappedValues[item.level] || 0))
}

function averageValue(record) {
  const values = record.locations.map((item) => mappedValues[item.level] || 0)
  return values.reduce((sum, value) => sum + value, 0) / Math.max(values.length, 1)
}

function shortDate(value) {
  const date = new Date(value)
  return `${date.getMonth() + 1}/${date.getDate()}`
}

const maxLevelValue = computed(() => Math.max(...records.value.map(maxValue), 0))

const commonParts = computed(() => {
  const counts = {}
  records.value.forEach((record) => {
    const unique = new Set(record.locations.map((item) => item.name))
    unique.forEach((name) => { counts[name] = (counts[name] || 0) + 1 })
  })
  const max = Math.max(...Object.values(counts), 1)
  return Object.entries(counts)
    .map(([name, count]) => ({ name, count, percent: Math.round((count / max) * 100) }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)
})
</script>

<style scoped>
.trends-header { padding: 14rpx 4rpx 26rpx; }
.trends-header__title { display: block; font-size: 44rpx; font-weight: 720; }
.trends-header__copy { display: block; margin-top: 10rpx; color: var(--color-text-secondary); font-size: 25rpx; }
.range-row { display: flex; gap: 12rpx; margin-bottom: 24rpx; }
.range-chip { flex: 1; padding: 15rpx 6rpx; border-radius: 999rpx; background: var(--color-bg-subtle); color: var(--color-text-secondary); font-size: 23rpx; text-align: center; }
.range-chip--active { background: var(--color-primary); color: var(--color-on-primary); }
.metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 18rpx; }
.metric { padding: 24rpx; }
.metric__label { display: block; color: var(--color-text-secondary); font-size: 23rpx; }
.metric__value { display: block; margin-top: 8rpx; font-size: 46rpx; font-weight: 720; }
.metric__caption { display: block; margin-top: 8rpx; color: var(--color-text-tertiary); font-size: 21rpx; }
.chart-card { grid-column: 1 / -1; padding: 28rpx; }
.chart { display: flex; height: 240rpx; align-items: flex-end; gap: 14rpx; margin-top: 28rpx; padding-top: 16rpx; border-bottom: 1rpx solid var(--color-border); }
.chart__group { display: flex; flex: 1; min-width: 0; flex-direction: column; align-items: center; }
.chart__bars { display: flex; height: 180rpx; align-items: flex-end; gap: 5rpx; }
.chart__bar { width: 16rpx; min-height: 8rpx; border-radius: 8rpx 8rpx 0 0; }
.chart__bar--average { background: var(--color-primary-soft); }
.chart__bar--max { background: var(--color-primary); }
.chart__label { margin-top: 10rpx; color: var(--color-text-tertiary); font-size: 19rpx; }
.part-row { display: grid; grid-template-columns: 100rpx 1fr 70rpx; gap: 12rpx; align-items: center; margin-top: 22rpx; color: var(--color-text-secondary); font-size: 23rpx; }
.part-row__track { height: 14rpx; overflow: hidden; border-radius: 999rpx; background: var(--color-bg-subtle); }
.part-row__fill { height: 100%; border-radius: 999rpx; background: var(--color-primary); }
.empty { margin-top: 50rpx; padding: 44rpx 30rpx; text-align: center; }
.empty__title { display: block; font-size: 30rpx; font-weight: 650; }
.empty__copy { display: block; margin-top: 12rpx; color: var(--color-text-secondary); font-size: 24rpx; line-height: 1.6; }
</style>
