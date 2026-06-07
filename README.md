# Lisn

Lisn 是一个逐步开发中的 Flutter 音乐 App。

当前版本先实现 Android 基础框架：

- Lumia 磁贴式首页布局
- 底部四等分导航块：主页、库、我的、搜索
- 主页、库、我的之间横向推拉切换
- 搜索从顶部推下，顶部搜索框贴边显示
- 迷你播放器固定在底部导航上方
- 点击迷你播放器打开组合式全屏播放器动画
- Android 原生通道递归读取 `Music` 文件夹及其子文件夹中的音频文件
- 原生 `MediaPlayer` 播放、暂停、上一曲、下一曲、进度拖动和音量控制
- 歌曲、艺术家、专辑、文件夹、最近、收藏等本地音乐分类
- 收藏、最近播放，并在 Android 上持久化
- 内嵌封面读取与展示，缺失时会尝试同目录同名图片或 `cover/folder/front/album` 图片
- LRC 歌词扫描、读取、解析和随播放进度高亮显示

## LRC 歌词

扫描音频时会在同目录查找 `.lrc` 文件：

- 精确同名：`Song.mp3` -> `Song.lrc`
- 同名前缀带后缀：`Song.mp3` -> `Song.zh.lrc`、`Song - lyrics.lrc`、`Song_翻译.lrc`

## 运行

```sh
flutter pub get
flutter run
```

首次运行时，Android 会请求读取音频文件权限。

## APK 签名

GitHub Actions 构建的 release APK 使用仓库内的固定内测证书
`android/app/signing/lisn-dev-release.p12` 签名，因此同包名的新 APK 可以
直接覆盖安装旧版本。

这个证书只用于开发和内测，不作为正式上架密钥。
