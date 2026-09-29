/** 微信小程序顶部/底部安全区与导航尺寸 */

function getWindowMetrics() {
  try {
    return typeof uni.getWindowInfo === 'function'
      ? uni.getWindowInfo()
      : uni.getSystemInfoSync()
  } catch (error) {
    return {}
  }
}

function getMenuRect() {
  try {
    // #ifdef MP-WEIXIN
    if (typeof uni.getMenuButtonBoundingClientRect === 'function') {
      return uni.getMenuButtonBoundingClientRect()
    }
    // #endif
  } catch (error) {
    // ignore
  }
  return null
}

export function getSafeAreaMetrics() {
  const windowInfo = getWindowMetrics()
  const menuRect = getMenuRect()

  const systemStatusBar =
    Number(windowInfo.statusBarHeight) ||
    Number(windowInfo.safeArea && windowInfo.safeArea.top) ||
    0

  let statusBarHeight = systemStatusBar || 44
  let navBarHeight = 44
  let capsuleRight = 95

  if (menuRect && typeof menuRect.top === 'number' && typeof menuRect.height === 'number') {
    statusBarHeight = systemStatusBar || Math.max(Math.floor(menuRect.top - 6), 20)
    navBarHeight = Math.max((menuRect.top - statusBarHeight) * 2 + menuRect.height, 32)
    if (typeof windowInfo.windowWidth === 'number' && typeof menuRect.left === 'number') {
      capsuleRight = Math.max(windowInfo.windowWidth - menuRect.left, 87)
    }
  }

  let safeAreaBottom = 0
  if (windowInfo.safeArea && typeof windowInfo.screenHeight === 'number') {
    safeAreaBottom = Math.max(0, windowInfo.screenHeight - windowInfo.safeArea.bottom)
  } else if (windowInfo.safeAreaInsets && typeof windowInfo.safeAreaInsets.bottom === 'number') {
    safeAreaBottom = Math.max(0, windowInfo.safeAreaInsets.bottom)
  }

  // 旧机型 safeArea 可能为 0；有刘海特征时给 home indicator 兜底
  if (!safeAreaBottom && menuRect && menuRect.top > 40) {
    safeAreaBottom = 34
  }

  return {
    statusBarHeight,
    navBarHeight,
    navbarTotalHeight: statusBarHeight + navBarHeight,
    capsuleRight,
    safeAreaBottom,
    tabBarContentHeight: 50,
    tabBarTotalHeight: 50 + safeAreaBottom
  }
}
