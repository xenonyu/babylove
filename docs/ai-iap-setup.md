# BabyLove AI In-App Purchase 配置指南

完成本指南后，用户可通过 App Store 购买 AI Insights 功能，
付款验证由 Azure Functions 代理完成，Azure AI Foundry API Key 不会暴露在客户端。

## 架构回顾

```
iOS App (StoreKit 2)
  │ 购买 → Apple 签名 JWS Token
  ▼
Azure Function (babylove-ai-proxy)
  │ 验证 JWS → 颁发 JWT → 限流 → 转发
  ▼
Azure AI Foundry (gpt-5.2-chat)
```

已部署资源：

| 资源 | 名称 |
|------|------|
| Function App | `babylove-ai-proxy.azurewebsites.net` |
| Resource Group | `Foundry` (eastus2) |
| AI 部署 | `agentapp-resource` / `gpt-5.2-chat` |
| Storage | `babyloveaistorage` |

---

## Step 1：App Store Connect — 创建 App

> 如果 App 已存在可跳过此步。

1. 打开 [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. **My Apps** → 左上角 **+** → **New App**
3. 填写以下信息：

   | 字段 | 值 |
   |------|----|
   | Platform | iOS |
   | Bundle ID | `com.babylove.app` |
   | SKU | `babylove` |

---

## Step 2：App Store Connect — 创建内购产品

1. 进入 App → 左侧 **Monetization** → **In-App Purchases** → 右上角 **+**
2. 选择类型：

   | 类型 | 说明 |
   |------|------|
   | ✅ Non-Consumable | 一次性买断，适合功能解锁 |
   | ❌ Consumable | 消耗型，适合虚拟货币 |
   | ❌ Subscription | 订阅型，适合持续服务 |

3. 填写基本信息：

   | 字段 | 值 |
   |------|----|
   | Reference Name | `AI Insights` |
   | Product ID | `com.babylove.app.ai_insights` |

4. 点击 **Create**

---

## Step 3：填写产品详情

### Availability
勾选需要上架的国家/地区（建议全选）。

### Price
选择价格档位：

| 档位 | 美元 | 人民币参考 |
|------|------|-----------|
| Tier 1 | $0.99 | ¥6 |
| Tier 3 | $2.99 | ¥18 |
| Tier 5 | $4.99 | ¥30 |

### Localization
点击 **+** 依次添加以下语言：

| 语言 | Display Name | Description |
|------|-------------|-------------|
| English | AI Insights | Smart analysis of baby feeding, sleep, and diaper patterns |
| Chinese Simplified | AI 智能分析 | 智能分析宝宝喂奶、睡眠、换尿布规律，提供个性化育儿建议 |
| Japanese | AI インサイト | 赤ちゃんの授乳・睡眠・おむつのパターンをスマートに分析 |
| Korean | AI 인사이트 | 아기의 수유, 수면, 기저귀 패턴을 스마트하게 분석 |

### Review Information（审核材料）
- **Screenshot**：App 内 AI 功能截图（1242×2688 px）
- **Review Notes**：
  ```
  This feature analyzes locally stored baby care records (feeding, sleep, diaper)
  to provide pattern insights and predictions. No data is sent to third parties.
  The AI processing is handled via the developer's Azure Functions proxy.
  ```

点击右上角 **Save**。

---

## Step 4：Xcode — StoreKit 本地测试配置

用于在 Simulator 中测试购买流程，无需真机或审核通过。

### 4.1 创建配置文件

1. Xcode → **File** → **New** → **File**
2. 搜索 **StoreKit Configuration File** → **Next**
3. 保存为 `BabyLove.storekit`（放在项目根目录）

### 4.2 添加产品

1. 打开 `BabyLove.storekit`
2. 左下角 **+** → **Add Non-Consumable In-App Purchase**
3. 填写：

   | 字段 | 值 |
   |------|----|
   | Reference Name | AI Insights |
   | Product ID | `com.babylove.app.ai_insights` |
   | Price | 2.99 |
   | Locale | 添加 en_US，Display Name: `AI Insights` |

### 4.3 绑定到 Scheme

1. Xcode 顶部 Scheme → **Edit Scheme**
2. **Run** → **Options** → **StoreKit Configuration**
3. 选择 `BabyLove.storekit`

完成后在 Simulator 里调用 `PurchaseManager.shared.purchase()` 会弹出测试购买弹窗。

---

## Step 5：真机测试 — 沙盒账号

沙盒账号购买不会真实扣款。

1. **App Store Connect** → **Users and Access** → **Sandbox** → **Testers** → **+**
2. 填写测试邮箱（如 `sandbox-test@babylove.dev`），记住密码
3. 在真机 **Settings** → **App Store** → **Sandbox Account** 登录此账号
4. 运行 App，购买时使用沙盒账号，不会产生真实费用

---

## Step 6：上线前检查清单

- [ ] App Store Connect 产品状态为 **Ready to Submit**
- [ ] 所有语言的 Display Name / Description 已填写
- [ ] Review Screenshot 已上传
- [ ] Simulator 测试购买流程正常
- [ ] 真机沙盒账号测试通过
- [ ] Azure Function `/api/auth` 能正常验证 JWS
- [ ] Azure Function `/api/chat` 能正常返回 AI 回复

---

## 相关代码文件

| 文件 | 说明 |
|------|------|
| `BabyLove/Services/PurchaseManager.swift` | StoreKit 2 购买逻辑 |
| `BabyLove/Services/AIService.swift` | JWS→JWT 换取 + AI 调用 |
| `azure-function/src/functions/auth.js` | 验证 Apple JWS，颁发 JWT |
| `azure-function/src/functions/chat.js` | 验证 JWT，转发 Azure AI |
| `azure-function/src/utils/appleJws.js` | Apple JWS 签名验证 |
| `azure-function/src/utils/jwt.js` | HMAC-SHA256 JWT 工具 |
