<template>
  <view class="page-root locate-theme" :class="`theme-${app.state.resolvedTheme}`">
    <AppNavbar :title="navTitle" :left-arrow="true" fallback-url="/pages/index/index" />

    <view class="locate-page">
      <PainBodyMap
        :model-value="marker"
        :region="region"
        :shape="shape"
        @update:model-value="onMarkerUpdate"
        @change="onMarkerChange"
      />

      <view class="shape-row">
        <view
          v-for="item in shapes"
          :key="item.value"
          class="shape-card"
          :class="{ 'shape-card--active': shape === item.value }"
          @click="shape = item.value"
        >
          <view class="shape-card__icon" :class="`shape-card__icon--${item.value}`" />
          <text class="shape-card__label">{{ item.label }}</text>
        </view>
      </view>

      <view class="panel">
        <view class="intensity">
          <view class="intensity__top">
            <text class="intensity__title">强度</text>
            <text class="intensity__value">{{ intensity }}/10</text>
          </view>
          <slider
            class="intensity__slider"
            :value="intensity"
            :min="1"
            :max="10"
            :step="1"
            :activeColor="sliderActiveColor"
            :backgroundColor="sliderTrackColor"
            block-size="20"
            @changing="onIntensityChanging"
            @change="onIntensityChange"
          />
          <text class="intensity__caption">{{ intensityLabel }}</text>
        </view>

        <view class="field">
          <text class="field__label">发生时间</text>
          <picker mode="multiSelector" :range="timeRange" :value="timePickerIndex" @change="onTimePicked">
            <view class="field__value">{{ timeDisplay }}</view>
          </picker>
        </view>

        <view class="field field--notes">
          <text class="field__label">想说点什么</text>
          <textarea
            v-model="note"
            class="field__textarea"
            maxlength="200"
            placeholder="可选。例如：跳痛、压着会好一点……"
            placeholder-class="field__placeholder"
          />
        </view>
      </view>

      <view class="save-area">
        <text v-if="validationMessage" class="validation">{{ validationMessage }}</text>
        <AppButton
          theme="default"
          :custom-style="saveButtonStyle"
          :disabled="!canSave"
          @click="submit"
        >
          保存本次记录
        </AppButton>
      </view>
    </view>
  </view>
</template>

<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import AppButton from '../../../../components/ui/AppButton.vue'
import AppNavbar from '../../../../components/ui/AppNavbar.vue'
import PainBodyMap from '../../components/PainBodyMap.vue'
import { useAppStore } from '../../../../stores/app'
import { saveRecord } from '../../../../services/recordRepository'

const app = useAppStore()
const region = ref('full')
const shape = ref('point')
const intensity = ref(3)
const note = ref('')
const validationMessage = ref('')
const occurredAt = ref(new Date())

const marker = reactive({
  x: 0.5,
  y: 0.35,
  view: 'front',
  layer: 'skin',
  shape: 'point',
  region: 'full',
  name: '身体',
  depth: '表面'
})

const regionLabels = {
  head: '头部',
  lower: '下部',
  full: '全身'
}

const shapes = [
  { value: 'point', label: '点状' },
  { value: 'area', label: '片状' },
  { value: 'line', label: '线状' },
  { value: 'radiate', label: '放射' }
]

const intensityLabels = {
  1: '几乎感觉不到',
  2: '轻微不适',
  3: '微痛与不适',
  4: '能忍受',
  5: '明显影响做事',
  6: '比较难受',
  7: '很难受',
  8: '非常痛',
  9: '几乎无法忍受',
  10: '无法忍受'
}

const saveButtonStyle =
  'border-radius: 16px; min-height: 52px; font-weight: 650;'
const sliderActiveColor = computed(() =>
  app.state.resolvedTheme === 'dark' ? '#E8E8E8' : '#141414'
)
const sliderTrackColor = computed(() =>
  app.state.resolvedTheme === 'dark' ? '#313131' : '#E1E1E1'
)

const navTitle = computed(() => `疼痛记录 · ${regionLabels[region.value] || '全身'}`)
const intensityLabel = computed(() => intensityLabels[intensity.value] || '')
const canSave = computed(() => Boolean(marker.name) && intensity.value >= 1)

const timeDisplay = computed(() => {
  const date = occurredAt.value
  const y = date.getFullYear()
  const m = date.getMonth() + 1
  const d = date.getDate()
  const hh = String(date.getHours()).padStart(2, '0')
  const mm = String(date.getMinutes()).padStart(2, '0')
  const ap = date.getHours() < 12 ? '上午' : '下午'
  return `${y}年${m}月${d}日 ${ap}${hh}:${mm}`
})

const timeRange = computed(() => {
  const now = new Date()
  const dates = []
  for (let i = 0; i < 14; i += 1) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
    dates.push(`${day.getMonth() + 1}月${day.getDate()}日`)
  }
  const hours = Array.from({ length: 24 }, (_, index) => `${String(index).padStart(2, '0')}时`)
  const minutes = Array.from({ length: 60 }, (_, index) => `${String(index).padStart(2, '0')}分`)
  return [dates, hours, minutes]
})

const timePickerIndex = computed(() => {
  const now = new Date()
  const dayDiff = Math.min(
    13,
    Math.round(
      (new Date(now.getFullYear(), now.getMonth(), now.getDate()) -
        new Date(occurredAt.value.getFullYear(), occurredAt.value.getMonth(), occurredAt.value.getDate())) /
        86400000
    )
  )
  return [Math.max(0, dayDiff), occurredAt.value.getHours(), occurredAt.value.getMinutes()]
})

watch(shape, (value) => {
  marker.shape = value
})

onLoad((query) => {
  if (!app.state.authenticated) {
    const next = encodeURIComponent('/packages/locate/pages/record/index')
    uni.redirectTo({ url: `/pages/login/index?next=${next}` })
    return
  }
  if (query?.part) {
    const part = decodeURIComponent(query.part)
    marker.name = part
    if (part.includes('头') || part.includes('颈')) region.value = 'head'
    else if (part.includes('膝') || part.includes('腿') || part.includes('髋') || part.includes('臀')) region.value = 'lower'
    else region.value = 'full'
    marker.region = region.value
  }
})

function onMarkerUpdate(value) {
  if (!value || typeof value !== 'object') return
  Object.assign(marker, value)
}

function onMarkerChange(value) {
  if (value?.region) region.value = value.region
}

function onIntensityChanging(event) {
  intensity.value = Number(event.detail.value)
}

function onIntensityChange(event) {
  intensity.value = Number(event.detail.value)
}

function onTimePicked(event) {
  const [dayIndex, hour, minute] = event.detail.value
  const base = new Date()
  base.setHours(0, 0, 0, 0)
  base.setDate(base.getDate() - dayIndex)
  base.setHours(hour, minute, 0, 0)
  if (base.getTime() > Date.now()) {
    validationMessage.value = '发生时间不能晚于现在。'
    return
  }
  validationMessage.value = ''
  occurredAt.value = base
}

function mapIntensityToLevel(value) {
  if (value <= 2) return 1
  if (value <= 4) return 2
  if (value <= 6) return 3
  if (value <= 8) return 4
  return 5
}

function submit() {
  validationMessage.value = ''
  if (!canSave.value) {
    validationMessage.value = '请先在身体上定位，并选择强度。'
    return
  }

  const startAt = occurredAt.value.toISOString()
  saveRecord({
    locations: [
      {
        key: `locate_${Date.now()}`,
        id: `coord_${marker.region}_${marker.view}`,
        name: marker.name,
        viewSide: marker.view,
        level: mapIntensityToLevel(intensity.value),
        intensity: intensity.value,
        shape: shape.value,
        x: marker.x,
        y: marker.y,
        region: marker.region,
        depth: marker.depth
      }
    ],
    sensation: {
      intensity: intensity.value,
      note: note.value.trim()
    },
    timing: {
      startAt,
      uncertain: false
    },
    source: 'locate_3d'
  })

  uni.showToast({ title: '已保存', icon: 'success' })
  setTimeout(() => {
    uni.navigateBack({
      fail: () => uni.redirectTo({ url: '/pages/history/index' })
    })
  }, 400)
}
</script>

<style lang="scss" scoped>
.locate-theme {
  min-height: 100vh;
  background: var(--color-bg-page);
  color: var(--color-text-primary);
}
.locate-page {
  padding: 12rpx 28rpx calc(40rpx + env(safe-area-inset-bottom));
}
.shape-row {
  display: flex;
  gap: 16rpx;
  margin: 24rpx 0 8rpx;
}
.shape-card {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10rpx;
  padding: 18rpx 8rpx;
  border-radius: 16rpx;
  background: transparent;
}
.shape-card--active {
  background: var(--color-bg-surface);
  box-shadow: 0 0 0 2rpx var(--color-primary);
}
.shape-card__icon {
  width: 36rpx;
  height: 36rpx;
  border-radius: 50%;
  background: var(--color-primary);
}
.shape-card__icon--area {
  width: 44rpx;
  height: 32rpx;
  border-radius: 40%;
  background: var(--color-primary);
  opacity: 0.35;
}
.shape-card__icon--line {
  width: 48rpx;
  height: 8rpx;
  border-radius: 999rpx;
  transform: rotate(-20deg);
}
.shape-card__icon--radiate {
  background: radial-gradient(circle, var(--color-primary) 0 28%, transparent 29%),
    conic-gradient(from 0deg, var(--color-primary) 0 8%, transparent 8% 25%, var(--color-primary) 25% 33%, transparent 33% 50%, var(--color-primary) 50% 58%, transparent 58% 75%, var(--color-primary) 75% 83%, transparent 83% 100%);
}
.shape-card__label {
  font-size: 24rpx;
  color: var(--color-text-secondary);
}
.shape-card--active .shape-card__label {
  color: var(--color-text-primary);
  font-weight: 650;
}
.panel {
  margin-top: 12rpx;
  padding: 8rpx 4rpx 0;
}
.intensity__top {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 8rpx;
}
.intensity__title {
  font-size: 28rpx;
  color: var(--color-text-primary);
  font-weight: 650;
}
.intensity__value {
  font-size: 40rpx;
  font-weight: 700;
  color: var(--color-text-primary);
}
.intensity__caption {
  display: block;
  margin-top: 8rpx;
  color: var(--color-text-tertiary);
  font-size: 22rpx;
}
.field {
  margin-top: 28rpx;
}
.field__label {
  display: block;
  margin-bottom: 10rpx;
  font-size: 26rpx;
  color: var(--color-text-secondary);
}
.field__value {
  padding: 22rpx 24rpx;
  border-radius: 16rpx;
  border: 1rpx solid var(--color-border);
  background: var(--color-bg-elevated);
  color: var(--color-text-primary);
  font-size: 28rpx;
}
.field__textarea {
  width: 100%;
  min-height: 140rpx;
  padding: 20rpx 24rpx;
  border-radius: 16rpx;
  border: 1rpx solid var(--color-border);
  background: var(--color-bg-elevated);
  color: var(--color-text-primary);
  font-size: 28rpx;
  box-sizing: border-box;
}
.field__placeholder {
  color: var(--color-text-tertiary);
}
.save-area {
  margin-top: 36rpx;
}
.validation {
  display: block;
  margin-bottom: 12rpx;
  color: #e64340;
  font-size: 24rpx;
}
</style>
