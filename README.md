# Sonorynth

一款面向 Android 的 Flutter 音乐播放器，采用 Material 3 Expressive 设计风格，支持网易云音乐服务、账号登录、封面取色与逐字歌词。

## 已实现

- 三栏信息架构：首页、探索、我的。
- 首页欢迎语、今日/本周听歌统计、连续听歌、最近播放与音乐概览。
- 探索页推荐、情境入口、热歌列表和跨歌曲/歌手/专辑搜索。
- 我的页网易云账号入口、本地歌单、新建歌单、收藏、最近播放和详细设置。
- 播放器：队列、进度跳转、上一首/下一首、音质切换、定时关闭入口。
- 点击播放页封面进入全屏歌词。
- 歌词：LRC、内嵌逐字时间戳、网易云 YRC、翻译行、二分定位、平滑自动滚动、手势浏览后自动恢复、点击跳转、逐字颜色裁切高亮。
- 当前歌曲封面种子色驱动 Material 3 全局主题；支持固定主题和深色模式。
- 网易云兼容 API：搜索、每日推荐、新版歌词、音质 URL、二维码登录、账号资料。
- 本地持久化：歌单、最近播放、设置、登录 Cookie、听歌统计。
- 合法音源适配链：官方账号可用地址 → 用户配置且获授权的适配器。

## 运行

```bash
flutter pub get
flutter run
```

开发环境需安装支持 Dart >=3.10.0 的 Flutter SDK、Android SDK 和 JDK 17。Android 最低版本由所用 Flutter SDK 决定。

## 网易云音乐与登录

支持二维码、手机号验证码登录，以及搜索、推荐、收藏和账号资料。

## 授权音源适配器

设置页可选填写用户自己的授权音源解析端点。应用会以 `id` 和 `quality` 查询参数发起 GET，请返回：

```json
{"url": "https://authorized.example.com/audio/song.mp3"}
```

该机制只用于用户有权访问的本地音乐、公开内容或已授权服务。项目不提供也不实现付费墙、区域限制、版权保护或 DRM 绕过。

## 工程结构

- `lib/app_state.dart`：播放、队列、持久化、统计和业务状态。
- `lib/netease_api.dart`：网易云兼容 API 与授权来源适配链。
- `lib/lyrics_parser.dart`：LRC/YRC 解析、歌词定位和逐字进度。
- `lib/ui.dart`：Material 3 Expressive 页面与交互。
- `test/lyrics_parser_test.dart`：歌词解析关键路径测试。
