# Google Play Console 上架资料 - Spotoolfy

本文件夹包含 Spotoolfy 在 Google Play Console 上架所需的所有文档和资料指南。

---

## 文档清单

| 文档 | 说明 | 状态 |
|------|------|------|
| [store_listing.md](store_listing.md) | 应用商店描述（中英日） | ✅ 已完成 |
| [privacy_policy.md](privacy_policy.md) | 隐私政策（中英文） | ✅ 已完成 |
| [content_rating_questionnaire.md](content_rating_questionnaire.md) | 内容分级问卷参考 | ✅ 已完成 |
| [assets_requirements.md](assets_requirements.md) | 截图和素材规格说明 | ✅ 已完成 |

---

## 上架前检查清单

### 1. 开发者账号
- [ ] 注册 Google Play 开发者账号（$25 一次性费用）
- [ ] 完成身份验证

### 2. 应用信息
- [ ] 填写应用名称：**Spotoolfy**
- [ ] 填写简短描述（80字符内）
- [ ] 填写完整描述（4000字符内）
- [ ] 选择应用类别：**音乐与音频**
- [ ] 添加标签/关键词

### 3. 隐私政策
- [ ] 将 privacy_policy.md 托管到可公开访问的 URL
- [ ] 建议使用 GitHub Pages 或 Notion 发布
- [ ] 在 Google Play Console 中填写隐私政策 URL

### 4. 内容分级
- [ ] 完成 IARC 内容分级问卷
- [ ] 参考 content_rating_questionnaire.md 填写答案

### 5. 图形资源
- [ ] 准备 512x512 应用图标
- [ ] 准备 1024x500 功能图
- [ ] 准备 2-8 张手机截图
- [ ] （可选）准备平板截图
- [ ] （可选）准备宣传视频

### 6. 应用版本
- [ ] 构建签名 APK/AAB
- [ ] 测试应用功能完整性
- [ ] 确认版本号正确

### 7. 定价与分发
- [ ] 设置应用定价（免费）
- [ ] 选择分发国家/地区
- [ ] 确认是否包含广告（否）
- [ ] 确认内购状态（无）

### 8. 数据安全声明
- [ ] 完成数据安全表单
- [ ] 声明数据收集情况（本应用不收集数据）
- [ ] 声明数据共享情况（本应用不共享数据）

---

## 快速发布步骤

### 步骤 1：创建应用
1. 登录 [Google Play Console](https://play.google.com/console)
2. 点击「创建应用」
3. 填写应用名称、语言、类型

### 步骤 2：设置商店信息
1. 进入「商店发布」>「主要商店详情」
2. 复制 store_listing.md 中的描述内容
3. 上传图形资源

### 步骤 3：完成内容分级
1. 进入「政策」>「应用内容」>「内容分级」
2. 开始问卷调查
3. 参考 content_rating_questionnaire.md 填写

### 步骤 4：设置隐私政策
1. 隐私政策已托管到：**https://spotoolfy-privacy.pages.dev/**
2. 在「政策」>「应用内容」>「隐私政策」填写上述 URL

### 步骤 5：上传应用
1. 进入「发布」>「生产」
2. 创建新版本
3. 上传 AAB 文件
4. 填写版本说明

### 步骤 6：提交审核
1. 检查所有必填项已完成
2. 提交审核
3. 等待 Google 审核（通常 1-7 天）

---

## 构建签名 APK/AAB

### 创建签名密钥
```bash
keytool -genkey -v -keystore spotoolfy-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias spotoolfy
```

### 配置签名（android/app/build.gradle）
```gradle
android {
    signingConfigs {
        release {
            storeFile file('spotoolfy-release-key.jks')
            storePassword 'your-store-password'
            keyAlias 'spotoolfy'
            keyPassword 'your-key-password'
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

### 构建 AAB（推荐）
```bash
flutter build appbundle --release
```

输出位置：`build/app/outputs/bundle/release/app-release.aab`

### 构建 APK
```bash
flutter build apk --release
```

输出位置：`build/app/outputs/flutter-apk/app-release.apk`

---

## 注意事项

### Spotify API 限制
- 当前应用使用 Spotify 开发者模式
- 开发者模式最多支持 25 个测试用户
- 若需公开发布，需申请 Spotify API 扩展配额
- 访问：https://developer.spotify.com/documentation/web-api/concepts/quota-modes

### 第三方内容免责
- 歌词来自第三方服务（QQ音乐、网易云音乐）
- 音乐内容通过 Spotify 流媒体提供
- 建议在描述中说明需要 Spotify Premium

---

## 资源链接

- [Google Play Console](https://play.google.com/console)
- [Google Play 政策中心](https://play.google.com/about/developer-content-policy/)
- [应用商店优化指南](https://developer.android.com/distribute/best-practices/launch/store-listing)
- [Spotify 开发者仪表板](https://developer.spotify.com/dashboard)
- [Spotify 配额申请](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)

---

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.2.0 | 2024-12 | 初始 Google Play 上架准备 |
