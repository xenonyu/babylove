/**
 * POST /api/chat
 * 验证 JWT → 限流 → 转发到 Azure AI Foundry → 返回回复
 */
const { app }      = require('@azure/functions')
const jwt          = require('../utils/jwt')
const rateLimit    = require('../utils/rateLimit')

app.http('chat', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'chat',

  handler: async (request, context) => {
    try {
      // 1. 验证 JWT
      const auth = request.headers.get('authorization') ?? ''
      if (!auth.startsWith('Bearer ')) {
        return { status: 401, body: 'Missing Bearer token' }
      }

      const payload = jwt.verify(auth.slice(7), process.env.JWT_SECRET)

      // 2. 每日限流
      if (!rateLimit.check(payload.sub)) {
        return { status: 429, body: 'Daily limit reached (50 requests/day)' }
      }

      // 3. 读取请求体
      const body = await request.json()
      const { prompt, systemPrompt } = body ?? {}
      if (!prompt) return { status: 400, body: 'Missing prompt' }

      // 4. 调用 Azure AI Foundry（Key 在 Function App Settings 里，不在代码里）
      const endpoint   = process.env.AZURE_ENDPOINT       // https://xxx.openai.azure.com
      const deployment = process.env.AZURE_DEPLOYMENT     // gpt-4o
      const apiKey     = process.env.AZURE_API_KEY

      const azureUrl = `${endpoint}/openai/deployments/${deployment}/chat/completions?api-version=2024-12-01-preview`

      const messages = []
      if (systemPrompt) messages.push({ role: 'system', content: systemPrompt })
      messages.push({ role: 'user', content: prompt })

      const azureRes = await fetch(azureUrl, {
        method: 'POST',
        headers: {
          'api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ messages, max_completion_tokens: 600 }),
      })

      if (!azureRes.ok) {
        const errText = await azureRes.text()
        context.error(`Azure AI error ${azureRes.status}: ${errText}`)
        return { status: 502, body: 'AI service error' }
      }

      const data    = await azureRes.json()
      const content = data.choices?.[0]?.message?.content ?? ''

      return { status: 200, jsonBody: { content } }

    } catch (err) {
      context.error(`Chat error: ${err.message}`)
      const status = err.message.includes('JWT') ? 401 : 500
      return { status, body: err.message }
    }
  },
})
