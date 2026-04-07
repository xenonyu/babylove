/**
 * 轻量 JWT 工具（HMAC-SHA256）
 * 使用 Node.js 内置 crypto，无第三方依赖
 */
const crypto = require('crypto')

function sign(payload, secret, ttlSec = 3600) {
  const now  = Math.floor(Date.now() / 1000)
  const body = { ...payload, iat: now, exp: now + ttlSec }

  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')
  const pld    = Buffer.from(JSON.stringify(body)).toString('base64url')
  const sig    = crypto.createHmac('sha256', secret).update(`${header}.${pld}`).digest('base64url')

  return `${header}.${pld}.${sig}`
}

function verify(token, secret) {
  const parts = token.split('.')
  if (parts.length !== 3) throw new Error('Invalid JWT format')

  const [header, pld, sig] = parts
  const expected = crypto.createHmac('sha256', secret).update(`${header}.${pld}`).digest('base64url')

  // timing-safe 比较，防止时序攻击（长度不等时直接拒绝）
  const sigBuf = Buffer.from(sig)
  const expBuf = Buffer.from(expected)
  if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
    throw new Error('Invalid JWT signature')
  }

  const payload = JSON.parse(Buffer.from(pld, 'base64url').toString())
  if (payload.exp < Math.floor(Date.now() / 1000)) throw new Error('JWT expired')

  return payload
}

module.exports = { sign, verify }
