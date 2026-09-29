import { reactive } from 'vue'

const STORAGE_KEY = 'zhiteng_app_preferences_v1'

const state = reactive({
  ready: false,
  onboardingCompleted: false,
  theme: 'system',
  resolvedTheme: 'light',
  // 前端演示会话；接入后端后改为服务端 token / 会话校验
  authenticated: false
})

function readPreferences() {
  try {
    return uni.getStorageSync(STORAGE_KEY) || {}
  } catch (error) {
    return {}
  }
}

function savePreferences() {
  try {
    uni.setStorageSync(STORAGE_KEY, {
      onboardingCompleted: state.onboardingCompleted,
      theme: state.theme,
      authenticated: state.authenticated
    })
  } catch (error) {
    // 存储失败时不阻断主流程
  }
}

function getSystemTheme() {
  try {
    const info = uni.getSystemInfoSync()
    return info.theme === 'dark' ? 'dark' : 'light'
  } catch (error) {
    return 'light'
  }
}

function applyTheme() {
  state.resolvedTheme = state.theme === 'system' ? getSystemTheme() : state.theme
  const dark = state.resolvedTheme === 'dark'
  const pageBg = dark ? '#070707' : '#FCFCFC'

  // 自定义 Navbar 时仍用此 API 控制状态栏文字颜色，降低白闪
  uni.setNavigationBarColor({
    frontColor: dark ? '#ffffff' : '#000000',
    backgroundColor: pageBg
  })
  if (typeof uni.setBackgroundColor === 'function') {
    uni.setBackgroundColor({
      backgroundColor: pageBg,
      backgroundColorTop: pageBg,
      backgroundColorBottom: pageBg
    })
  }
}

let themeListenerBound = false

function bindSystemThemeListener() {
  if (themeListenerBound || typeof uni.onThemeChange !== 'function') return
  themeListenerBound = true
  uni.onThemeChange(() => {
    if (state.theme === 'system') {
      applyTheme()
    }
  })
}

export function bootstrapApp() {
  const preferences = readPreferences()
  state.onboardingCompleted = Boolean(preferences.onboardingCompleted)
  state.theme = preferences.theme || 'system'
  state.authenticated = Boolean(preferences.authenticated)
  applyTheme()
  bindSystemThemeListener()
  state.ready = true
}

export function completeOnboarding() {
  state.onboardingCompleted = true
  savePreferences()
}

export function setTheme(theme) {
  state.theme = theme
  savePreferences()
  applyTheme()
}

export function completeFrontendLogin() {
  // 前端演示会话写入本地，保证 Tab 切换与二次进入仍保持登录态。
  // 接入后端后必须替换为服务端会话，并清理此本地标记。
  state.authenticated = true
  savePreferences()
}

export function clearFrontendLogin() {
  state.authenticated = false
  savePreferences()
}

export function useAppStore() {
  return {
    state,
    completeOnboarding,
    setTheme,
    applyTheme,
    completeFrontendLogin,
    clearFrontendLogin
  }
}
