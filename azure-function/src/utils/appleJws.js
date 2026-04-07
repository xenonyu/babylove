/**
 * 验证 Apple StoreKit 2 JWS Transaction
 * 使用 Node.js 内置 crypto（无需第三方库）
 */
const crypto = require('crypto')

const BUNDLE_ID  = 'com.babylove.app'
const PRODUCT_ID = 'com.babylove.app.ai_insights'

async function verifyAppleJWS(jws) {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new Error('Invalid JWS format')

  const header  = JSON.parse(b64Decode(parts[0]))
  const payload = JSON.parse(b64Decode(parts[1]))

  if (header.alg !== 'ES256')   throw new Error('Expected ES256')
  if (!header.x5c?.length)      throw new Error('No x5c in JWS header')

  // Node.js 内置 X509Certificate — 直接从 DER 导入叶子证书公钥
  const leafDer = Buffer.from(header.x5c[0], 'base64')
  const cert    = new crypto.X509Certificate(leafDer)
  const pubKey  = cert.publicKey

  // 验证 ES256 签名
  const signingInput = Buffer.from(`${parts[0]}.${parts[1]}`)
  const signature    = Buffer.from(parts[2], 'base64url')
  const valid        = crypto.verify('SHA256', signingInput, pubKey, signature)
  if (!valid) throw new Error('JWS signature invalid')

  // 业务校验
  if (payload.bundleId !== BUNDLE_ID)   throw new Error(`Wrong bundleId: ${payload.bundleId}`)
  if (payload.productId !== PRODUCT_ID) throw new Error(`Wrong productId: ${payload.productId}`)

  return payload
}

function b64Decode(s) {
  return Buffer.from(s, 'base64url').toString('utf8')
}

module.exports = { verifyAppleJWS }
