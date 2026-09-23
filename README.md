# Sonorynth

Sonorynth 是一款 Android 音乐播放器，支持网易云在线听歌、歌单管理和逐字歌词。

## 功能

- 搜索歌曲、歌手和专辑，查看推荐与热歌。
- 登录网易云账号，管理歌单、收藏和最近播放。
- 播放队列、音质切换、定时关闭和全屏歌词。
- 网易云、QQ 音乐与 AMLL 歌词，支持逐字高亮、翻译和来源排序。
- 随封面变化的主题色，以及深色模式。

## 下载

[前往 Releases 下载 Android 安装包](https://github.com/CLCTY/Sonorynth/releases)。

## 歌词

在播放页点击封面可打开全屏歌词。想换歌词时，可以搜索其他来源；来源顺序可在歌词设置中调整。开启逐字歌词后，优先显示逐字版本。

## 自行构建

需要 Flutter（Dart 3.10+）、Android SDK 和 JDK 17。

```bash
flutter pub get
flutter run
```

## 自定义音源

设置中可以填写你有权使用的音源接口。应用通过 GET 请求传入 `id` 和 `quality`，接口返回：

```json
{"url": "https://authorized.example.com/audio/song.mp3"}
```

## 致谢

QQ 音乐 QRC 解码基于 [QQMusicDecoder](https://github.com/WXRIW/QQMusicDecoder) 改编，按 MIT 许可使用。[查看许可文本](third_party_licenses/QQMusicDecoder.txt)。
