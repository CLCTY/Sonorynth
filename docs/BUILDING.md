# Android 构建

Sonorynth 正式应用的 Android 包名为 `app.sonorynth.player`。

开发调试使用 `flutter run`。正式构建不再回退到 debug 签名；未配置私有签名时，release 产物为未签名包，不能作为可安装发行包发布。

在仓库外创建私有 properties 文件，包含 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。将环境变量 `SONORYNTH_SIGNING_PROPERTIES` 指向该文件，再运行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

不要提交签名文件或密码。请为密钥及其密码制作安全的离线备份；后续更新必须使用同一发行密钥。

## 验证用预览版（不发布 Release）

预览版使用独立包名 `app.sonorynth.player.preview`，显示为「Sonorynth 预览版」，可与正式版共存，数据互不影响。它使用 Release 编译优化和 debug 测试签名，无需正式签名文件。只有显式设置 `SONORYNTH_PREVIEW_BUILD=true` 才会启用，普通正式构建仍要求私有签名。

```sh
flutter pub get
SONORYNTH_PREVIEW_BUILD=true flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

`.github/workflows/android-preview.yml` 会先执行静态分析和测试，再构建 ARM64 / ARM 两种 APK，上传为 GitHub Actions 的 Artifacts，不创建 Release。Flutter 固定为本项目使用的 3.41.7，JDK 为 17，依赖按已提交的 `pubspec.lock` 安装。

上传这些改动至测试分支后，可通过以下方式构建与下载：

1. 推送 `preview/**` 或 `codex/**` 分支会自动构建；创建或更新 PR 也会构建，无需合并主分支。
2. 在 GitHub 的 **Actions → Android preview APK** 中打开成功的运行。
3. 在 **Artifacts** 下载 `sonorynth-preview-arm64-v8a`（多数较新手机）或 `sonorynth-preview-armeabi-v7a`（旧款 32 位手机）。解压 ZIP 后安装 APK；文件中也附有 SHA-256 校验值。

工作流进入默认分支后，也可使用 **Run workflow** 选择测试分支手动触发。下载通常需要登录有仓库访问权限的 GitHub 账号，产物保留 14 天。

不同 CI 运行可能生成不同测试证书，跨次更新若提示签名冲突，需卸载旧预览版再安装，此操作会清除预览版数据；正式版数据不受影响。不要将测试签名包作为正式更新发行。
