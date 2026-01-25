# WeatherWhisper

一款温暖的天气关怀 App，根据天气为你生成贴心的问候文案。

## 功能特性

- 🌦️ **智能天气感知**: 使用 WeatherKit 获取实时天气
- 💬 **AI 关怀文案**: 基于 Gemini 2.5 生成个性化关怀文案
- 🎨 **天气主题**: 7 种天气类型对应不同视觉主题
- ❤️ **收藏功能**: 保存喜欢的文案
- 📤 **一键分享**: 复制或分享给关心的人
- 📸 **卡片保存**: 将精美卡片保存到相册

## 技术栈

### iOS 客户端
- SwiftUI + SwiftData
- WeatherKit
- Supabase Swift SDK
- iOS 17+

### 后端服务
- Supabase Edge Functions
- Supabase Auth (Anonymous)
- Google Gemini 2.5 API

## 开始使用

### 1. 环境要求

- Xcode 15+
- iOS 17+ 设备或模拟器
- Apple Developer Program 账号（WeatherKit 需要）
- Supabase 账号
- Google AI Studio 账号（Gemini API）

### 2. 配置 Supabase

1. 创建 Supabase 项目
2. 启用 Anonymous Auth
3. 部署 Edge Function
4. 配置 Secrets

详见 [supabase/README.md](supabase/README.md)

### 3. 配置 iOS 项目

1. 打开 `WeatherWhisper.xcodeproj`
2. 编辑 `WeatherWhisper/App/Secrets.swift`:

```swift
enum Secrets {
    static let supabaseURL = "https://your-project.supabase.co"
    static let supabaseAnonKey = "your-anon-key"
    static let useRealAPI = true
}
```

3. 在 Xcode 中配置 Team 和 Signing
4. 运行项目

### 4. 开发模式

默认开启 Mock 模式，无需配置即可开发测试：

```swift
// AppConfig.swift
static let useMockData = true  // Mock 模式
```

## 项目结构

```
WeatherWhisper/
├── App/                    # 应用入口和配置
├── Models/                 # 数据模型 (SwiftData)
├── Services/               # 服务层
│   ├── NetworkMonitor      # 网络监控
│   ├── WeatherProvider     # 天气数据
│   ├── CardsAPIClient      # API 客户端
│   └── SupabaseSessionManager  # 会话管理
├── ViewModels/             # 视图模型
├── Views/                  # UI 视图
│   ├── Home/               # 首页
│   ├── Detail/             # 详情页
│   ├── Favorites/          # 收藏页
│   └── Settings/           # 设置页
├── Theme/                  # 主题配色
└── Utils/                  # 工具类

supabase/
├── functions/
│   └── cards-generate/     # Edge Function
├── config.toml             # 本地配置
└── README.md               # 配置指南
```

## 状态机

Home 页面实现 7 状态状态机：

1. `bootstrappingSession` - 初始化会话
2. `emptyRecipient` - 无关怀对象
3. `loadingWeather` - 加载天气
4. `noNetwork` - 无网络
5. `loadingCards` - 生成卡片
6. `ready` - 就绪
7. `llmError` - 生成失败

## API 接口

### POST /functions/v1/cards-generate

生成关怀文案。

**请求头:**
- `Authorization: Bearer {access_token}`
- `X-Device-Id: {uuid}`
- `X-Request-Id: {uuid}`

**请求体:**
```json
{
  "requestId": "uuid",
  "locale": "zh-CN",
  "cardsCount": 5,
  "recipient": { "nickname": "小明", "relationType": "friend" },
  "tone": "gentle",
  "city": { "name": "北京", "lat": 39.9, "lon": 116.4 },
  "weather": { "triggerType": "rain", ... },
  "constraints": { "maxCharsPerCard": 80, ... }
}
```

**响应:**
```json
{
  "groupId": "uuid",
  "triggerType": "rain",
  "cards": [{ "cardId": "uuid", "text": "...", "tone": "gentle", "triggerType": "rain", "source": "llm" }],
  "meta": { "model": "gemini-2.5", "latencyMs": 1234, "cached": false }
}
```

## 开发指南

### 添加新的天气主题

1. 在 `TriggerType` 枚举中添加新类型
2. 在 `TriggerTheme` 中添加对应颜色
3. 在 `TriggerResolver` 中添加映射规则

### 添加新的关系类型

1. 在 `RelationType` 枚举中添加新类型
2. 更新 Edge Function 中的 Prompt

## 支持

如需帮助或反馈问题，请查看 [SUPPORT.md](SUPPORT.md)。

## 许可证

MIT License
