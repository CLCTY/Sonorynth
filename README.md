# Sonorynth

Android 音乐播放器，支持在线播放、歌单和逐字歌词。

## 功能

- 在线搜索和推荐，支持账号登录、歌单及收藏。
- 播放队列、音质切换、定时关闭和全屏歌词。
- LRC / QRC / YRC / TTML 歌词，支持逐字高亮、翻译和来源排序。
- 封面取色主题和深色模式。

## 下载

[前往 Releases 下载 Android 安装包](https://github.com/CLCTY/Sonorynth/releases)。

## 歌词

在播放页点击封面可打开全屏歌词。想换歌词时，可以搜索其他来源；来源顺序可在歌词设置中调整。开启逐字歌词后，优先显示逐字版本。

## 开发

需要 Flutter（Dart 3.10+）、Android SDK 和 JDK 17。

```bash
flutter pub get
flutter run
```

[Android 构建说明](docs/BUILDING.md) · [播放地址接口](docs/CUSTOM_AUDIO.md) · [第三方许可](third_party_licenses/QQMusicDecoder.txt)

## 来源与许可

QRC 解码器改编自 [WXRIW/QQMusicDecoder](https://github.com/WXRIW/QQMusicDecoder)，采用 MIT 许可，版权与许可原文保存在 [third_party_licenses/QQMusicDecoder.txt](third_party_licenses/QQMusicDecoder.txt)。项目图标由 AI 辅助生成。

维护者选择 MIT 作为项目的目标许可；在历史参考代码的适用许可核清前，尚未正式添加项目级 LICENSE。第三方组件仍适用各自原有许可。
