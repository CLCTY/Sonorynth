# 第三方来源与许可说明

本文件记录在 `main` 提交 `4ec7661943be5eb4d8c49e4e718e1258bde19651` 中识别到的来源，非完整法律审查，也不是对所有文件原创性的证明。

## QQMusicDecoder

- 上游：[WXRIW/QQMusicDecoder](https://github.com/WXRIW/QQMusicDecoder)。
- 使用位置：`lib/qq_qrc_decoder.dart`；文件头标明改编自上游 `DESHelper.cs`，用于 QRC 解码兼容。
- 上游版权：Copyright (c) 2023 WXRIW。
- 上游许可：MIT；完整文本保存在 [third_party_licenses/QQMusicDecoder.txt](third_party_licenses/QQMusicDecoder.txt)。
- Android 资源另保留 `android/app/src/main/assets/QQMusicDecoder-LICENSE.txt`。后续修改应同步保留两个许可副本，分发时保留适用版权及许可声明。

## Flutter 与 Dart 依赖

`pubspec.yaml` 和 `pubspec.lock` 记录直接及解析后的依赖。各依赖适用自己的许可证；本项目的任何许可都不替代其声明。发布者需依据实际构建包含的依赖保留所需通知；本文件未逐项核验全部传递依赖。

## 渲染参考与待确认来源

`lib/m3e_beat_stage.dart` 的注释提到 AMLL / SPlayer 的封面预处理参数。当前检查无法仅凭注释判定是否存在受许可约束的源码改编；发布项目自身许可证前，应由维护者确认实际参考范围。如复制或改编了代码，需补充准确上游、对应文件和适用许可证。

## 进一步核查结果（2026-10-21）

- 初始公开提交 `317fbf0` 的 README 明确记载 AI 辅助开发及 SPlayer、AMLL、LrcView、OuterTune、Rhythm、PixelPlayer、BoomingMusic 和 Echo Music 等研究来源，并注明许可核查未完成。后续简化 README 不等于该核查已经完成。
- 现有 `lib/qqmusic_lyrics.dart` 与曾查阅的 SPlayer-Next `electron/main/apis/qqmusic/modules/lyric.ts` 存在相同参数集合及“先请求 QRC、按返回标志分类、必要时再请求 LRC”的流程对应。相关字段可能由协议决定，不能据此单独断言发生受版权保护的代码复制；但应核清生成和改编来源后，再确定项目许可。
- [SPlayer-Next](https://github.com/SPlayer-Dev/SPlayer-Next) 的本地参考快照附带 AGPL-3.0 许可证；[AMLL](https://github.com/amll-dev/applemusic-like-lyrics) 的当前仓库许可证也为 AGPL-3.0。若实际包含受这些许可约束的改编代码，不能仅通过新增 MIT 文件消除其义务。
- `assets/effects/oneui_soft_glow_mask.png` 在本地历史操作中存在 AI 生成后经 FFmpeg 提取透明度、缩放和模糊处理的记录。当前文件与旧项目中的该遮罩 SHA-256 一致：`2e85896e2075ec4da8ab85bc6980ec1995ee9518b5f97a4e61bbf32a8ce90a60`。该记录说明创作流程，不构成对生成图像权利的独立保证。
- 维护者于 2026-10-21 确认项目图标由 AI 辅助生成。`assets/branding/melody_flow_icon_master.png` 与旧项目文件哈希一致；不再将其列为来源待确认项。该来源说明不代表授予第三方商标权。

维护者已选择 MIT 作为希望采用的项目许可。在上述来源问题解决前，本次文档变更不添加全仓库 MIT 声明；第三方原有授权保持原样。Git 提交者信息本身不证明著作权归属。

## 内容与服务

运行时获取的音乐、歌词、封面以及第三方服务适用各自权利和使用条件，不因本仓库的代码许可而获得授权。不要向仓库提交个人凭据或未经授权的内容。
