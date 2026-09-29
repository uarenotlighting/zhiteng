<template>
  <view class="locator">
    <view class="locator__views">
      <view
        v-for="item in regions"
        :key="item.value"
        class="locator__chip"
        :class="{ 'locator__chip--active': activeRegion === item.value }"
        @click="setRegion(item.value)"
      >
        {{ item.label }}
      </view>
      <view class="locator__chip locator__chip--ghost" @click="resetView">复位</view>
    </view>

    <view class="locator__stage">
      <canvas
        :id="canvasId"
        class="locator__canvas"
        type="webgl"
        :style="{ width: canvasCssWidth + 'px', height: canvasCssHeight + 'px' }"
        @touchstart.prevent="onTouchStart"
        @touchmove.prevent="onTouchMove"
        @touchend.prevent="onTouchEnd"
      />

      <view v-if="loading" class="locator__status">加载 3D 人体模型…</view>
      <view v-else-if="errorText" class="locator__status locator__status--error">{{ errorText }}</view>

      <view class="crosshair" :style="crosshairStyle">
        <view class="crosshair__h" />
        <view class="crosshair__v" />
      </view>

      <view
        class="marker"
        :class="[`marker--${shape}`]"
        :style="markerStyle"
      >
        <view class="marker__core" />
        <view v-if="shape === 'area'" class="marker__area" />
        <view v-if="shape === 'line'" class="marker__line" />
        <view v-if="shape === 'radiate'" class="marker__rays">
          <view v-for="n in 6" :key="n" class="marker__ray" :style="{ transform: `rotate(${n * 60}deg)` }" />
        </view>
      </view>

      <text class="locator__hint">按住拖动定位 · 双指缩放 · 上方切换部位</text>
    </view>
  </view>
</template>

<script setup>
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { createBodyScene } from '../utils/createBodyScene.js'

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({
      x: 0.5,
      y: 0.35,
      view: 'front',
      layer: 'skin',
      shape: 'point',
      region: 'full'
    })
  },
  region: { type: String, default: 'full' },
  shape: { type: String, default: 'point' }
})

const emit = defineEmits(['update:modelValue', 'change'])

const canvasId = `pain-body-${Math.random().toString(36).slice(2, 9)}`
const regions = [
  { value: 'head', label: '头部' },
  { value: 'lower', label: '下部' },
  { value: 'full', label: '全身' }
]

const state = reactive({
  x: props.modelValue.x ?? 0.5,
  y: props.modelValue.y ?? 0.35,
  region: props.region || props.modelValue.region || 'full',
  dragging: false,
  rotating: false
})

const loading = ref(true)
const errorText = ref('')
const canvasCssWidth = ref(300)
const canvasCssHeight = ref(360)

let sceneApi = null
let instanceProxy = null
let touchMode = 'mark'

const activeRegion = computed(() => state.region || props.region || 'full')
const shape = computed(() => props.shape || 'point')

const markerStyle = computed(() => ({
  left: `${state.x * 100}%`,
  top: `${state.y * 100}%`
}))

const crosshairStyle = computed(() => ({
  left: `${state.x * 100}%`,
  top: `${state.y * 100}%`
}))

watch(
  () => props.modelValue,
  (value) => {
    if (!value || state.dragging) return
    state.x = value.x ?? state.x
    state.y = value.y ?? state.y
    if (sceneApi) sceneApi.setMarkerNormalized(state.x, state.y)
  },
  { deep: true }
)

watch(
  () => props.region,
  (value) => {
    if (!value || value === state.region) return
    state.region = value
    sceneApi?.setRegion(value)
  }
)

onMounted(async () => {
  instanceProxy = getCurrentInstance()?.proxy || null
  await nextTick()
  await initScene()
  publish()
})

onBeforeUnmount(() => {
  sceneApi?.dispose()
  sceneApi = null
})

async function initScene() {
  loading.value = true
  errorText.value = ''
  try {
    const rect = await measureStage()
    canvasCssWidth.value = Math.max(280, Math.floor(rect.width))
    canvasCssHeight.value = Math.max(320, Math.floor(rect.height))
    const dpr = Math.min(uni.getSystemInfoSync().pixelRatio || 2, 2)

    await nextTick()
    const canvas = await queryCanvas()
    if (!canvas) throw new Error('无法创建 WebGL 画布')

    canvas.width = Math.floor(canvasCssWidth.value * dpr)
    canvas.height = Math.floor(canvasCssHeight.value * dpr)

    sceneApi = createBodyScene(canvas, {
      width: canvas.width,
      height: canvas.height,
      region: activeRegion.value
    })
    await sceneApi.loadModel()
    sceneApi.setMarkerNormalized(state.x, state.y)
    loading.value = false
  } catch (error) {
    loading.value = false
    const msg = error?.message || error?.errMsg || String(error)
    errorText.value = '3D 模型加载失败'
    console.error('[PainBodyMap]', msg, error)
  }
}

function measureStage() {
  return new Promise((resolve) => {
    uni
      .createSelectorQuery()
      .in(instanceProxy)
      .select('.locator__stage')
      .boundingClientRect((rect) => {
        resolve(rect || { width: 300, height: 360 })
      })
      .exec()
  })
}

function queryCanvas() {
  return new Promise((resolve) => {
    uni
      .createSelectorQuery()
      .in(instanceProxy)
      .select(`#${canvasId}`)
      .fields({ node: true, size: true })
      .exec((res) => {
        const node = res?.[0]?.node
        resolve(node || null)
      })
  })
}

function publish(extra = {}) {
  const payload = {
    x: Number(state.x.toFixed(4)),
    y: Number(state.y.toFixed(4)),
    view: 'front',
    layer: 'skin',
    shape: shape.value,
    region: activeRegion.value,
    name: extra.name || guessPartName(state.x, state.y, activeRegion.value),
    depth: '表面'
  }
  emit('update:modelValue', payload)
  emit('change', payload)
}

function setRegion(value) {
  state.region = value
  sceneApi?.setRegion(value)
  publish()
}

function resetView() {
  sceneApi?.setRegion(activeRegion.value)
  if (activeRegion.value === 'head') {
    state.x = 0.52
    state.y = 0.22
  } else if (activeRegion.value === 'lower') {
    state.x = 0.55
    state.y = 0.62
  } else {
    state.x = 0.5
    state.y = 0.35
  }
  sceneApi?.setMarkerNormalized(state.x, state.y)
  publish()
}

function updateMarkerFromTouch(touch, rect) {
  if (!rect?.width || !sceneApi) return
  const nx = (touch.clientX - rect.left) / rect.width
  const ny = (touch.clientY - rect.top) / rect.height
  const hit = sceneApi.setMarkerFromNdc(nx, ny)
  if (!hit) {
    state.x = clamp(nx, 0.02, 0.98)
    state.y = clamp(ny, 0.02, 0.98)
    publish()
    return
  }
  state.x = hit.x
  state.y = hit.y
  publish({ name: hit.name })
}

function onTouchStart(event) {
  const touches = event.touches || []
  if (touches.length >= 2) {
    touchMode = 'orbit'
    state.rotating = true
    sceneApi?.dispatchTouch(event)
    return
  }
  touchMode = 'mark'
  state.dragging = true
  const touch = touches[0] || event.changedTouches?.[0]
  if (!touch) return
  uni
    .createSelectorQuery()
    .in(instanceProxy)
    .select('.locator__stage')
    .boundingClientRect((rect) => updateMarkerFromTouch(touch, rect))
    .exec()
}

function onTouchMove(event) {
  if (touchMode === 'orbit') {
    sceneApi?.dispatchTouch(event)
    return
  }
  if (!state.dragging) return
  const touch = event.touches?.[0] || event.changedTouches?.[0]
  if (!touch) return
  uni
    .createSelectorQuery()
    .in(instanceProxy)
    .select('.locator__stage')
    .boundingClientRect((rect) => updateMarkerFromTouch(touch, rect))
    .exec()
}

function onTouchEnd(event) {
  if (touchMode === 'orbit') {
    sceneApi?.dispatchTouch(event)
  }
  state.dragging = false
  state.rotating = false
  touchMode = 'mark'
  publish()
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

function guessPartName(x, y, region) {
  if (region === 'head') return y < 0.45 ? '头部' : '颈部'
  if (region === 'lower') {
    if (y < 0.35) return '骨盆区域'
    if (y < 0.65) return '大腿'
    return '膝部'
  }
  if (y < 0.16) return '头部'
  if (y < 0.24) return '颈部'
  if (y < 0.38) return x < 0.35 || x > 0.65 ? '肩部' : '胸部'
  if (y < 0.5) return '腹部'
  if (y < 0.62) return '骨盆区域'
  if (y < 0.78) return '大腿'
  return '膝部'
}
</script>

<style scoped>
.locator { width: 100%; }
.locator__views { display: flex; gap: 12rpx; justify-content: center; flex-wrap: wrap; margin-bottom: 16rpx; }
.locator__chip {
  min-width: 96rpx;
  padding: 12rpx 22rpx;
  border-radius: 999rpx;
  background: var(--color-bg-surface, #eeeeee);
  color: var(--color-text-secondary, #5e5e5e);
  font-size: 24rpx;
  text-align: center;
}
.locator__chip--active {
  background: var(--color-primary, #141414);
  color: var(--color-on-primary, #ffffff);
  font-weight: 650;
}
.locator__chip--ghost {
  background: transparent;
  border: 1rpx solid var(--color-border, #e4e4e4);
  color: var(--color-text-tertiary, #8e8e8e);
}
.locator__stage {
  position: relative;
  height: 680rpx;
  overflow: hidden;
  border-radius: 24rpx;
  background: var(--color-bg-elevated, #fcfcfc);
}
.locator__canvas {
  width: 100%;
  height: 100%;
  display: block;
}
.locator__status {
  position: absolute;
  left: 0;
  right: 0;
  top: 46%;
  text-align: center;
  color: var(--color-text-tertiary, #8e8e8e);
  font-size: 24rpx;
  pointer-events: none;
}
.locator__status--error { color: #e64340; }
.crosshair { position: absolute; width: 0; height: 0; z-index: 3; pointer-events: none; }
.crosshair__h, .crosshair__v { position: absolute; background: var(--color-crosshair, rgba(60, 60, 60, 0.42)); }
.crosshair__h { left: -48rpx; top: 0; width: 96rpx; height: 2rpx; }
.crosshair__v { left: 0; top: -48rpx; width: 2rpx; height: 96rpx; }
.marker { position: absolute; z-index: 4; width: 28rpx; height: 28rpx; transform: translate(-50%, -50%); pointer-events: none; }
.marker__core {
  position: absolute;
  inset: 0;
  border-radius: 50%;
  background: #e64340;
  box-shadow: 0 0 0 6rpx rgba(230, 67, 64, 0.18);
}
.marker__area {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 110rpx;
  height: 110rpx;
  border-radius: 50%;
  background: rgba(230, 67, 64, 0.22);
  transform: translate(-50%, -50%);
}
.marker__line {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 120rpx;
  height: 10rpx;
  border-radius: 999rpx;
  background: rgba(230, 67, 64, 0.75);
  transform: translate(-20%, -50%) rotate(28deg);
}
.marker__rays { position: absolute; left: 50%; top: 50%; width: 0; height: 0; }
.marker__ray {
  position: absolute;
  left: 0;
  top: -4rpx;
  width: 70rpx;
  height: 8rpx;
  border-radius: 999rpx;
  background: linear-gradient(90deg, rgba(230, 67, 64, 0.85), rgba(230, 67, 64, 0));
  transform-origin: left center;
}
.locator__hint {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 18rpx;
  color: var(--color-text-tertiary, #8e8e8e);
  font-size: 22rpx;
  text-align: center;
  pointer-events: none;
}
</style>
