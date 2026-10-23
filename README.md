# EQ Keyboard 高情商聊天键盘

帮用户读懂对话、用自己的语气回出得体消息的键盘。产品方案见项目里的《高情商聊天输入法：竞品调研与产品技术方案》。

## 目录

| 目录 | 内容 |
| --- | --- |
| `backend/` | Node + TypeScript 后端：校验请求、每日额度、组装提示词、经可配置的中转 API 调用 Claude，返回 3 条回复和解释 |
| `ios/` | iOS 主 App（开启引导、截图导入与端侧识别、对方档案）和键盘扩展（拼音输入、帮我回、帮我改、发前看看、语气开关） |
| `ios/PinyinKit/` | 拼音输入引擎（全拼、九键、输入联想）与约 13 万条简体词库（Swift Package，可单独 `swift test`） |
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

回复语言跟随对方最后一条消息，解释文字使用 `uiLanguage`。`mode` 为 `polish`（帮我改）或 `check`（发前看看）时需带 `draft`。`check` 模式额外返回 `check: { verdict: "good" | "adjust" | "risky", note }`，verdict 为 good 时 `replies` 为空，否则给 1 到 2 个改法。

配置说明：

- `ANTHROPIC_BASE_URL` 指向你的中转 API，大陆和海外线路只需改这一项和密钥。
- `ENABLE_SERVER_FALLBACK` 默认开启服务端拒答 fallback；如果中转不支持 `fallbacks` 参数导致 400，改为 `false`。
- 提示词缓存已开启，但系统提示词较短，可能低于模型的最小缓存长度，届时缓存不会生效，不影响结果。
- 日志只记录方法、路径、状态码和耗时，不记录聊天内容。
- `DATABASE_URL` 指向 Postgres 后，用户、订阅和每日额度都存进数据库，启动时自动建表；留空时存在内存里，只适合本地试用。数据库里不存任何聊天内容。

## iOS

没有 Mac 也可以：每次提交 PR，GitHub Actions 会在云端 macOS 上自动编译 iOS 工程（见 `.github/workflows/ci.yml`）。

本地开发需要 macOS、Xcode 15 以上和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd ios
brew install xcodegen
xcodegen generate
open EQKeyboard.xcodeproj
```

Team ID（`2U62224FHB`）和 Bundle ID（`com.yonghuizhang.eqkeyboard`，键盘是 `.keyboard`，两者通过钥匙串共享组 `2U62224FHB.com.yonghuizhang.eqkeyboard.shared` 共享数据，不需要在开发者网站上手动注册 App Group）都在 `project.yml` 里，`EQ_API_BASE_URL` 指向后端。

## 用 TestFlight 在手机上安装

不需要 Mac：`.github/workflows/testflight.yml` 在云端签名、打包并上传到 TestFlight，每次 main 上的 iOS 代码有改动都会自动出新版本，也可以在 GitHub 的 Actions 页面手动运行。

一次性准备（都能在手机浏览器里完成）：

1. 在 App Store Connect 的“用户和访问 > 集成 > App Store Connect API”里生成一个“App 管理”权限的团队密钥，记下 Issuer ID、密钥 ID，并下载 .p8 文件（只能下载一次）。
2. 在 GitHub 仓库 Settings > Secrets and variables > Actions 里添加 Secrets：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY`（.p8 文件的全部文字）。后端部署好后再加 Variable `EQ_API_BASE_URL`。
3. 在 Actions 页面手动运行一次 TestFlight。这一次会自动注册 Bundle ID，但因为还没有 App，上传会失败，属于正常。
4. 在 App Store Connect 新建 App，Bundle ID 选 `com.yonghuizhang.eqkeyboard`，然后再运行一次，就会出现在 TestFlight 里。

后端的 `APPLE_BUNDLE_ID` 要和 `EQ_BUNDLE_ID` 相同。

## 拼音词库

支持全拼和简拼（nh → 你好，zhd → 知道，也可以混着打，如 nhao）。常用聊天词放在 `tools/chat_words.txt`，生成词库时会把它们的词频抬高，避免新闻语料把“南海”排在“你好”前面。

`ios/PinyinKit/Sources/PinyinKit/Resources/pinyin_dict.tsv` 由 `tools/build_pinyin_dict.py` 生成，词语和词频来自 [jieba](https://github.com/fxsjy/jieba) 0.42.1，读音来自 [pypinyin](https://github.com/mozillazg/python-pinyin) 0.55.0，两者均为 MIT 许可。只收 GB2312 范围内的简体字，多字词按词频取前 12 万条。

## 登录与订阅

- App 的“会员”页用 Sign in with Apple 登录，后端校验 Apple 的 identityToken 后发自己的会话令牌，键盘通过共享钥匙串共用它。
- 订阅用 StoreKit 2。购买时把后端用户 ID 作为 appAccountToken，App 把交易 JWS 发到 `/v1/subscription/verify`，后端用 Apple 根证书验签后提高每日额度。
- 续费、退款等由 App Store Server Notifications V2 推到 `/v1/appstore/notifications`，在 App Store Connect 里把通知地址设成这个接口。
- 上线前需要：在 App Store Connect 创建订阅商品（默认 `eqkeyboard.pro.monthly`、`eqkeyboard.pro.yearly`），为 App ID 打开 Sign in with Apple，后端配置 `SESSION_SECRET`、`APPLE_ROOT_CERT_PATHS`、`APP_APPLE_ID`（见 `.env.example`）。

## 尚未完成

- 拼音输入的进阶能力：整句联想、模糊音、用户词频学习。
- Android 输入法、语气学习、分寸引擎（第二阶段）。
