const STORAGE_KEY = 'zhiteng_frontend_records_v1'

function createId() {
  return `pain_${Date.now()}_${Math.random().toString(16).slice(2)}`
}

export function listRecords() {
  try {
    return uni.getStorageSync(STORAGE_KEY) || []
  } catch (error) {
    return []
  }
}

export function saveRecord(input) {
  const records = listRecords()
  const record = {
    ...input,
    id: createId(),
    createdAt: new Date().toISOString(),
    status: input.timeStatus === 'ended' ? 'ended' : 'ongoing'
  }
  records.unshift(record)
  // 前端阶段的可交互演示缓存。接入后端后必须由服务端作为唯一事实源。
  uni.setStorageSync(STORAGE_KEY, records)
  return record
}

export function deleteAllLocalDemoRecords() {
  uni.removeStorageSync(STORAGE_KEY)
}
