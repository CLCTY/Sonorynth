# Sonorynth

Android 音乐播放器，使用 Flutter 构建，支持在线播放、歌单和逐字歌词。

简体中文 · [English](README.en.md)

[下载安装包](https://github.com/CLCTY/Sonorynth/releases) · [报告问题](https://github.com/CLCTY/Sonorynth/issues) · [参与贡献](CONTRIBUTING.md)

## 功能

- 在线搜索和推荐，支持账号登录、歌单及收藏。
- 播放队列、音质切换、定时关闭和全屏歌词。
- LRC / QRC / YRC / TTML 歌词，支持逐字高亮、翻译和来源排序。
- 封面取色主题和深色模式。

在播放页点击封面可打开全屏歌词；可以搜索其他歌词来源，并在设置中调整来源顺序。开启逐字歌词后，优先显示逐字版本。

## 下载与版本

从 [Releases](https://github.com/CLCTY/Sonorynth/releases) 选择所需版本与设备架构。标记为 Pre-release 的安装包用于预览体验。发布页如附有 SHA-256 校验文件，可用它核对下载完整性；校验值不能代替对发布来源的确认。

`main` 分支、预览分支和已发布 APK 可能存在功能差异；报告问题时请注明版本和来源。当前公开发布记录见 [维护说明](docs/MAINTENANCE.md)。

## 使用说明

在线服务的可用功能和音质取决于服务状态、接口以及账号权益。需要自定义播放地址时，请配置你有权使用的接口，格式见 [播放地址接口](docs/CUSTOM_AUDIO.md)。项目的代码许可不授予音乐、歌词、封面或第三方服务的使用权。

## 开发与检查

需要 Flutter、Dart 3.10 或更高版本、Android SDK 和 JDK 17。使用满足 `pubspec.yaml` 约束的 Flutter SDK。

```sh
git clone https://github.com/CLCTY/Sonorynth.git
cd Sonorynth
flutter pub get
flutter analyze
flutter test
flutter run
```

现有测试涵盖歌词解析、缓存模型、请求加密、来源解析及部分界面行为。测试不代表线上服务、所有设备或所有发布 APK 已通过验证。

正式签名和分架构构建见 [Android 构建说明](docs/BUILDING.md)。签名密钥、密码、账号 Cookie 和个人数据不要提交到仓库或 Issue。

## 贡献与反馈

欢迎提供可复现的问题、测试用例、文档修正和小范围补丁。请先阅读 [贡献指南](CONTRIBUTING.md)。问题报告请附设备型号、Android 版本、应用版本、复现步骤及预期结果，分享日志前删除凭据和个人信息。

## 许可与第三方来源

项目自身许可证尚待维护者明确，不能把公开源码视为已获得再分发授权。已识别的第三方代码、许可文件及核查范围见 [第三方来源说明](THIRD_PARTY_NOTICES.md)。QRC 解码器的 MIT 版权声明继续保留。
