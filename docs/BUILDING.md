# Android 构建

仓库根目录为 Sonorynth 本地版，`online/` 为在线版。两者使用不同 Android 包名，但正式发行使用同一私有签名配置。请进入对应目录运行构建命令。

开发调试使用 `flutter run`。正式构建不再回退到 debug 签名；未配置私有签名时，release 产物为未签名包，不能作为可安装发行包发布。

在仓库外创建私有 properties 文件，包含 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。将环境变量 `SONORYNTH_SIGNING_PROPERTIES` 指向该文件，再运行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

不要提交签名文件或密码。请为密钥及其密码制作安全的离线备份；后续更新必须使用同一发行密钥。
