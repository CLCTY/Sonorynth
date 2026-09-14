# Sonorynth

> 独立的公开源码副本，原项目未修改。本副本不包含解锁音源实现、受限音源回退和酷我搜索入口。全部代码与资源的许可核查尚未完成，待办见文末。
>
> Android 应用 ID 为 `app.sonorynth.player`，与原安装版数据隔离。当前仍为开发用 debug 签名，正式发行前须配置私有签名。

一款面向 Android 的 Flutter 音乐播放器原型与可扩展实现，使用 Material 3 Expressive 设计语言。当前版本已覆盖完整主流程，并提供可运行的演示数据以及真实服务接入层。

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

## 网易云服务配置

应用不内置第三方账号密钥。进入：

`我的 → 设置 → 音乐服务`

填写你自己部署或明确获准使用的 NetEaseCloudMusicApi 兼容服务根地址，例如 `https://music-api.example.com`。随后可在 `我的 → 登录网易云音乐` 使用二维码登录。

支持的兼容端点：

- `/cloudsearch`
- `/personalized/newsong`
- `/song/url/v1`
- `/lyric/new`
- `/login/qr/key`
- `/login/qr/create`
- `/login/qr/check`
- `/user/account`

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

## 参考与边界

本项目由 AI 辅助开发，历史研究涉及 SPlayer、AMLL、LrcView、OuterTune、Rhythm、PixelPlayer、BoomingMusic 和 Echo Music。此列表不是完整的来源审计；不声明所有代码均为独立原创。公开前须核实具体实现、依赖、图标和测试素材的来源与许可，并补齐适用 LICENSE 和版权声明。移除解锁功能并不自动完成这些义务。

项目不是网易云官方客户端，服务和内容访问须符合相应条款及授权。用户自备音源端点会收到歌曲 ID、音质、标题、歌手和专辑信息，仅应配置可信且获准使用的服务。

## 发布前待办

- 核清上游版本及许可证，补齐第三方声明，保留构建生成的许可通知。
- 核实图标、图片和测试歌词的分发权。
- 扫描实际待上传文件和 Git 历史中的凭据；不要提交 Cookie、签名或设备截图。
- 使用私有发行签名，并进行真机回归；更名不代表名称或商标已核查。
