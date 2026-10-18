# EQ Keyboard 高情商聊天键盘

帮用户读懂对话、用自己的语气回出得体消息的键盘。产品方案见项目里的《高情商聊天输入法：竞品调研与产品技术方案》。

## 目录

| 目录 | 内容 |
| --- | --- |
| `backend/` | Node + TypeScript 后端：校验请求、每日额度、组装提示词、经可配置的中转 API 调用 Claude，返回 3 条回复和解释 |
| `ios/` | iOS 主 App（开启引导、截图导入与端侧识别、对方档案）和键盘扩展（拼音输入、帮我回、帮我改、语气开关） |
| `ios/PinyinKit/` | 全拼输入引擎与约 13 万条简体词库（Swift Package，可单独 `swift test`） |
| `tools/` | 词库生成脚本 |

Android 输入法在第二阶段加入。

## 后端

```bash
cd backend
npm install
cp .env.example .env   # 填入中转地址、密钥和模型名
npm run dev            # 默认监听 8787
npm test
```

接口：`POST /v1/replies`，请求头带 `X-Device-Id`。

```json
{
  "mode": "reply",
  "uiLanguage": "zh-Hans",
  "conversation": [{ "speaker": "them", "text": "Just got back from Kyoto!" }],
  "profile": { "name": "Emma", "stage": "flirting", "interests": ["hiking"] },
  "tone": { "humor": true }
}
```

回复语言跟随对方最后一条消息，解释文字使用 `uiLanguage`。`mode` 为 `polish` 时需带 `draft`。

配置说明：

- `ANTHROPIC_BASE_URL` 指向你的中转 API，大陆和海外线路只需改这一项和密钥。
- `ENABLE_SERVER_FALLBACK` 默认开启服务端拒答 fallback；如果中转不支持 `fallbacks` 参数导致 400，改为 `false`。
- 提示词缓存已开启，但系统提示词较短，可能低于模型的最小缓存长度，届时缓存不会生效，不影响结果。
- 日志只记录方法、路径、状态码和耗时，不记录聊天内容。

## iOS

没有 Mac 也可以：每次提交 PR，GitHub Actions 会在云端 macOS 上自动编译 iOS 工程（见 `.github/workflows/ci.yml`）。

本地开发需要 macOS、Xcode 15 以上和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd ios
brew install xcodegen
xcodegen generate
open EQKeyboard.xcodeproj
```

在 `project.yml` 中填写 `DEVELOPMENT_TEAM`、把 `bundleIdPrefix` 和 App Group（`group.com.example.eqkeyboard`，在 `project.yml` 与 `Shared/SharedStore.swift` 中）改成你自己的，并把 `EQ_API_BASE_URL` 指向后端。

## 拼音词库

`ios/PinyinKit/Sources/PinyinKit/Resources/pinyin_dict.tsv` 由 `tools/build_pinyin_dict.py` 生成，词语和词频来自 [jieba](https://github.com/fxsjy/jieba) 0.42.1，读音来自 [pypinyin](https://github.com/mozillazg/python-pinyin) 0.55.0，两者均为 MIT 许可。只收 GB2312 范围内的简体字，多字词按词频取前 12 万条。

## 登录与订阅

- App 的“会员”页用 Sign in with Apple 登录，后端校验 Apple 的 identityToken 后发自己的会话令牌，键盘通过 App Group 共用它。
- 订阅用 StoreKit 2。购买时把后端用户 ID 作为 appAccountToken，App 把交易 JWS 发到 `/v1/subscription/verify`，后端用 Apple 根证书验签后提高每日额度。
- 续费、退款等由 App Store Server Notifications V2 推到 `/v1/appstore/notifications`，在 App Store Connect 里把通知地址设成这个接口。
- 上线前需要：在 App Store Connect 创建订阅商品（默认 `eqkeyboard.pro.monthly`、`eqkeyboard.pro.yearly`），为 App ID 打开 Sign in with Apple，后端配置 `SESSION_SECRET`、`APPLE_ROOT_CERT_PATHS`、`APP_APPLE_ID`（见 `.env.example`）。

## 尚未完成

- 拼音输入的进阶能力：简拼（如 nh → 你好）、整句联想、模糊音、用户词频学习。
- 存储：用户、订阅和额度目前存在内存里，重启会丢，上线前换成数据库和 Redis。
- Android 输入法、语气学习、分寸引擎、发送前检查（第二阶段）。
