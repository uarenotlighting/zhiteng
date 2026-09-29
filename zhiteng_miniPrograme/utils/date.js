export function formatDateTime(value) {
  if (!value) return '未填写'
  const date = new Date(value)
  const pad = (part) => String(part).padStart(2, '0')
  return `${date.getMonth() + 1}月${date.getDate()}日 ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function toDateInput(date = new Date()) {
  const pad = (part) => String(part).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

export function toTimeInput(date = new Date()) {
  const pad = (part) => String(part).padStart(2, '0')
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function combineDateTime(date, time) {
  return new Date(`${date}T${time}:00`).toISOString()
}
