/**
 * POST /api/auth
 * 接收 iOS StoreKit 2 JWS → 验证 Apple 签名 → 返回我们的 JWT
 */
const { app }           = require('@azure/functions')
const { verifyAppleJWS } = require('../utils/appleJws')
const jwt               = require('../utils/jwt')

app.http('auth', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'auth',

  handler: async (request, context) => {
    try {
      const body = await request.json()
      const { jws } = body ?? {}

      if (!jws || typeof jws !== 'string') {
        return { status: 400, body: 'Missing jws field' }
      }

      // 验证 Apple 签名 + bundle/product 校验
      const txPayload = await verifyAppleJWS(jws)
      context.log(`Auth OK: ${txPayload.originalTransactionId}`)

      // 颁发我们的 JWT（24小时有效）
      const token = jwt.sign(
        { sub: txPayload.originalTransactionId },
        process.env.JWT_SECRET,
        86400
      )

      return { status: 200, jsonBody: { token } }

    } catch (err) {
      context.error(`Auth error: ${err.message}`)
      return { status: 401, body: `Auth failed: ${err.message}` }
    }
  },
})
