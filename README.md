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
