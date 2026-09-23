# Sonorynth QQ 歌词扩展版

Android 音乐播放器，支持网易云音乐在线内容、QQ 音乐歌词与逐字歌词显示。源码对应 Android 包名 `app.melodyflow.player`；它与仓库根目录的 Sonorynth 原版（网易云在线）并存。

## 功能

- 网易云音乐搜索、推荐、歌单、账号登录与播放。实际可播放内容取决于账号权益及用户配置的授权音源。
- 歌词支持 LRC、网易云 YRC、QQ 音乐 QRC 和 AMLL TTML DB；保留翻译、逐字高亮与时间校准。
- 歌词候选先显示来源，再显示歌手；可在“设置 → 歌词”或歌词搜索弹窗中调整来源顺序。开启逐字歌词时，逐字结果优先；排序设置保存在设备上。
- 本地保存播放队列、歌单、设置和听歌统计。

## 安装

从 [QQ 歌词扩展版 Release](https://github.com/CLCTY/Sonorynth/releases/tag/online-v1.10.12) 下载 ARM64 APK。它使用正式发行签名，与原版的包名不同，可以共存。此前直接安装到手机的 1.10.12 调试签名包使用相同包名，不能直接覆盖为正式签名包；如需改装正式版，先备份应用内数据并卸载旧包。

## 构建

在本目录运行 `flutter pub get` 和 `flutter run`。正式发行需要在仓库外配置私有签名文件，并将 `SONORYNTH_SIGNING_PROPERTIES` 指向它；格式及命令见 [Android 构建说明](../docs/BUILDING.md)。不要将密钥或密码提交到仓库。

## 服务与许可

网易云兼容服务地址可在“设置 → 音乐服务”中填写。QQ 歌词只提供文字和时间轴，不改变播放音源；QRC 解码器改编自 MIT 授权的 WXRIW/QQMusicDecoder，许可证见 [third_party_licenses/QQMusicDecoder.txt](third_party_licenses/QQMusicDecoder.txt)。请遵守所接入服务的使用条款与内容授权。
