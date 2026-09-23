# 播放地址接口

在设置中填写你有权使用的接口地址。应用通过 GET 请求传入 `id` 和 `quality`，接口需返回：

```json
{"url": "https://authorized.example.com/audio/song.mp3"}
```
