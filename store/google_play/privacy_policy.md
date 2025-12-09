# Privacy Policy for Spotoolfy

**Last Updated: December 2024**

## Introduction

Spotoolfy ("we", "our", or "the app") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our mobile application.

## Information We Collect

### Information You Provide

1. **Spotify Account Information**
   - When you connect your Spotify account, we receive your Spotify username and access tokens
   - This information is used solely to enable playback features and access your Spotify library
   - Access tokens are stored securely on your device using encrypted storage

2. **API Keys (Optional)**
   - Google Gemini API key for AI translation features
   - Spotify API credentials (Client ID and Secret)
   - These are stored locally on your device and never transmitted to our servers

3. **User-Generated Content**
   - Notes and ratings you add to tracks
   - All user notes are stored locally on your device only
   - This data is never uploaded to any external server

### Information Collected Automatically

1. **Local Cache Data**
   - Lyrics retrieved from third-party services (QQ Music, NetEase Cloud Music)
   - AI-generated translations
   - Album artwork cache
   - This data is stored locally to improve performance and reduce network requests

### Information We Do NOT Collect

- Personal identification information
- Location data
- Contact information
- Device identifiers for advertising
- Usage analytics or crash reports
- Browsing history

## How We Use Your Information

Your information is used exclusively to:

1. **Enable Core Features**
   - Connect to and control Spotify playback
   - Display synchronized lyrics
   - Generate AI translations using your provided API key
   - Save and display your personal notes

2. **Improve User Experience**
   - Cache data locally to reduce loading times
   - Remember your preferences and settings

## Third-Party Services

Spotoolfy integrates with the following third-party services:

### Spotify
- We use Spotify's Web API and SDK to enable playback control
- Your Spotify credentials are handled according to Spotify's terms of service
- Privacy Policy: https://www.spotify.com/legal/privacy-policy/

### Google Gemini (Optional)
- If you provide a Gemini API key, lyrics are sent to Google's servers for translation
- This is subject to Google's privacy policy: https://policies.google.com/privacy

### Lyrics Providers
- Lyrics are fetched from QQ Music and NetEase Cloud Music APIs
- Song metadata (title, artist) is sent to these services to retrieve lyrics
- No personal data is shared with these services

## Data Storage and Security

### Local Storage
- All user data (notes, settings, cached content) is stored locally on your device
- API keys are stored using Flutter Secure Storage with platform encryption
- Database files are stored in the app's private directory

### Data Transmission
- All network communications use HTTPS encryption
- No user data is transmitted to our servers (we don't operate any servers)
- Third-party API calls are made directly from your device

## Your Rights and Choices

### Data Control
- **Export**: You can export all your data (notes, ratings) as a JSON file
- **Delete**: You can clear all cached data from the Settings page
- **Disconnect**: You can log out of Spotify at any time, removing stored tokens

### Opt-Out
- AI features are optional and require you to provide your own API key
- You can use the app without AI features for basic playback and lyrics

## Children's Privacy

Spotoolfy is not directed at children under 13. We do not knowingly collect information from children under 13. If you are a parent and believe your child has provided us with personal information, please contact us.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by updating the "Last Updated" date at the top of this policy. You are advised to review this Privacy Policy periodically for any changes.

## Open Source

Spotoolfy is open source software. You can review our source code to verify our privacy practices at:
https://github.com/[your-repo]/spotoolfy_flutter

## Contact Us

If you have any questions about this Privacy Policy, please contact us at:

**Email:** [your-email@example.com]

**GitHub Issues:** https://github.com/[your-repo]/spotoolfy_flutter/issues

---

## Data Safety Section (Google Play Console)

### Data collected

| Data type | Collected | Shared | Purpose |
|-----------|-----------|--------|---------|
| Personal info | No | No | - |
| Financial info | No | No | - |
| Health info | No | No | - |
| Messages | No | No | - |
| Photos/Videos | No | No | - |
| Audio files | No | No | - |
| Files/Docs | No | No | - |
| Calendar | No | No | - |
| Contacts | No | No | - |
| App activity | No | No | - |
| Web browsing | No | No | - |
| App info | No | No | - |
| Device/IDs | No | No | - |
| Location | No | No | - |

### Security practices
- Data is encrypted in transit (HTTPS)
- Data stored locally is encrypted (Flutter Secure Storage)
- You can request data deletion (via app settings)

---

# 隐私政策 - Spotoolfy

**最后更新：2024年12月**

## 简介

Spotoolfy（以下简称"我们"或"本应用"）致力于保护您的隐私。本隐私政策说明了当您使用我们的移动应用程序时，我们如何收集、使用和保护您的信息。

## 我们收集的信息

### 您提供的信息

1. **Spotify 账户信息**
   - 当您连接 Spotify 账户时，我们会接收您的 Spotify 用户名和访问令牌
   - 这些信息仅用于启用播放功能和访问您的 Spotify 音乐库
   - 访问令牌使用加密存储安全地保存在您的设备上

2. **API 密钥（可选）**
   - 用于 AI 翻译功能的 Google Gemini API 密钥
   - Spotify API 凭据（Client ID 和 Secret）
   - 这些信息仅存储在您的设备本地，绝不会传输到我们的服务器

3. **用户生成的内容**
   - 您添加到歌曲的笔记和评分
   - 所有用户笔记仅存储在您设备的本地
   - 这些数据绝不会上传到任何外部服务器

### 自动收集的信息

1. **本地缓存数据**
   - 从第三方服务获取的歌词（QQ音乐、网易云音乐）
   - AI 生成的翻译
   - 专辑封面缓存
   - 这些数据存储在本地以提高性能并减少网络请求

### 我们不收集的信息

- 个人身份信息
- 位置数据
- 联系信息
- 用于广告的设备标识符
- 使用分析或崩溃报告
- 浏览历史

## 我们如何使用您的信息

您的信息仅用于：

1. **启用核心功能**
   - 连接和控制 Spotify 播放
   - 显示同步歌词
   - 使用您提供的 API 密钥生成 AI 翻译
   - 保存和显示您的个人笔记

2. **改善用户体验**
   - 在本地缓存数据以减少加载时间
   - 记住您的偏好和设置

## 数据存储和安全

### 本地存储
- 所有用户数据（笔记、设置、缓存内容）都存储在您设备的本地
- API 密钥使用 Flutter Secure Storage 进行平台加密存储
- 数据库文件存储在应用程序的私有目录中

### 数据传输
- 所有网络通信使用 HTTPS 加密
- 没有用户数据传输到我们的服务器（我们不运营任何服务器）
- 第三方 API 调用直接从您的设备发起

## 您的权利和选择

### 数据控制
- **导出**：您可以将所有数据（笔记、评分）导出为 JSON 文件
- **删除**：您可以从设置页面清除所有缓存数据
- **断开连接**：您可以随时退出 Spotify，移除存储的令牌

## 联系我们

如果您对本隐私政策有任何疑问，请通过以下方式联系我们：

**电子邮件：** [your-email@example.com]

**GitHub Issues：** https://github.com/[your-repo]/spotoolfy_flutter/issues
