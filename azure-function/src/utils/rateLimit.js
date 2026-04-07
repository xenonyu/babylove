/**
 * 简易内存限流（单实例适用）
 * 生产高并发场景可换 Azure Cache for Redis
 */
const DAILY_LIMIT = 50
const counts = new Map()

function check(userId) {
  const today = new Date().toISOString().slice(0, 10)
  const key   = `${userId}:${today}`
  const count = counts.get(key) ?? 0

  if (count >= DAILY_LIMIT) return false

  counts.set(key, count + 1)
  _cleanup(today)
  return true
}

// 清理过期 key，防止内存泄漏
function _cleanup(today) {
  for (const k of counts.keys()) {
    if (!k.endsWith(today)) counts.delete(k)
  }
}

module.exports = { check }
