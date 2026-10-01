# Sonorynth

Android 音乐播放器，支持在线播放、歌单和逐字歌词。

## 功能

- 在线搜索和推荐，支持账号登录、歌单及收藏。
- 播放队列、音质切换、定时关闭和全屏歌词。
- LRC / QRC / YRC / TTML 歌词，支持逐字高亮、翻译和来源排序。
- 封面取色主题和深色模式。

## 下载

[前往 Releases 下载 Android 安装包](https://github.com/CLCTY/Sonorynth/releases)。

验证中的改动通过 GitHub Actions 的 **Android preview APK → Artifacts** 下载预览版，不发布 Release。预览版可与正式版共存；[构建与下载步骤](docs/BUILDING.md#验证用预览版不发布-release)。

## 歌词

在播放页点击封面可打开全屏歌词。想换歌词时，可以搜索其他来源；来源顺序可在歌词设置中调整。开启逐字歌词后，优先显示逐字版本。

## 首次使用与主页

首次启动会显示功能介绍与快速设置，可选择深浅色主题、字重、音质，以及歌词背景、逐字显示、翻译和换行动效；也可跳过，稍后在「设置 → 欢迎与快速设置」重新打开。旧版本升级会保留原有偏好并直接进入应用。

「设置 → 主页布局」可逐项关闭问候语、应用名称、继续聆听、音乐概览卡片、本周统计与主页迷你播放器，也提供全部显示、精简主页和全部关闭预设。隐藏内容不会删除音乐或记录，导航和设置入口始终保留。新增引导支持系统减少动画，动态专辑背景也会随该选项停止流动。

## 开发

需要 Flutter（Dart 3.10+）、Android SDK 和 JDK 17。

```bash
flutter pub get
flutter run
```

[Android 构建说明](docs/BUILDING.md) · [播放地址接口](docs/CUSTOM_AUDIO.md) · [第三方许可](third_party_licenses/QQMusicDecoder.txt)
