# Iris 调色盘 · iOS

这是把你给的 `调色盘照片编辑器 (2).html` 装进 iPhone 的工程。

页面本身就一份，`Resources/index.html` 与你的原文件 **sha256 完全一致**（`a24d794c8e2c7194…`，602,050 字节），一个字节没改。所有 iOS 需要的东西都补在外壳上。

---

## 一、先说清楚一件事

**这台构建机是 Linux，没有 Xcode、没有 iOS SDK、没有 macOS。**
iOS 的可执行文件是 arm64 的 Mach-O，必须由 Apple 的编译器 + iPhoneOS SDK 链接出来，Linux 上没有任何办法生成。

所以交付的是 **一份能在 Mac 上一条命令出 ipa 的完整工程**，不是一个能直接装进手机的成品 ipa。任何声称在 Linux 上产出的 iOS 二进制都跑不起来。

拿到 ipa 有三条路，按省事程度排：

### 路 A：你有一台 Mac（最快，1 分钟）
```bash
cd iris-ios
bash build_ipa.sh          # 出未签名 ipa
bash build_ipa.sh --adhoc  # 顺带 ad-hoc 签名（越狱/TrollStore 用）
```
只需要 Xcode 或 Command Line Tools（`xcode-select --install`）。不用开发者账号，不用新建 Xcode 工程，不用配签名。

### 路 B：没有 Mac，用 GitHub Actions（免费，5 分钟）
1. 把这个目录推到任意 GitHub 私有仓库
2. 仓库 → Actions → `build-ios-ipa` → Run workflow
3. 跑完在 Artifact 里下载 `Iris-Palette-iOS-ipa`

工作流已经写好（`.github/workflows/ios.yml`），用的是 GitHub 的 macOS 跑机，不消耗你的设备。

### 路 C：借一台 Mac 或云 Mac（MacinCloud / MacStadium 按小时计费）
同上，跑 `bash build_ipa.sh`。

---

## 二、ipa 里装了什么：页面以外补的接缝

页面是移动优先的（100dvh、520px 断点、WebGL 实时渲染、HEIC+MOV 实况、319 滤镜 / 78 模板 / GIF / 视频导出），本来就不需要重做界面，缺的是**容器与系统之间的那几条缝**：

1. **导出保存**（最关键）
   页面导出走的是「造一个 `<a download>` + 点击」。这条路在 WKWebView 里 **静默失败** —— 文件凭空消失，用户以为保存了。
   `Resources/iris-ios-shim.js` 在原型层拦 `HTMLAnchorElement.prototype.click`，并且同时拦捕获阶段的真实点击，把 Blob 切成 32KB 一块，走 `webkit.messageHandlers.iris` 传给原生存成文件（`Sources/SaveSession.swift` 顺序写盘，不整块进内存）。
   - 图片 / 视频：落到 `Documents/Iris/`，同时写进「照片」App
   - ZIP、JSON、cube：留在 `Documents/Iris/`，可经「文件」App 取走
   - 落盘后自动弹出系统分享面板，可直接存相册 / 存文件 / 发微信

2. **防止乱存**（同一个坑在安卓上出现过）
   三道闸：启动后 2.5 秒内不接管；必须有 1.5 秒内的真实手势（页面自派发的 `isTrusted === false` 不算）；扩展名 + MIME + 体积白名单。实测启动阶段 0 次写盘。

3. **安全区**
   页面写了 `viewport-fit=cover` 但全文没用过 `env(safe-area-inset-*)`（0 处）。直接装进 iPhone，顶栏会被灵动岛/刘海压住，底部五个工具按钮会被 home 指示条压住。
   外壳在 `DOMContentLoaded` 时注入两条规则：顶栏 `padding-top` 加 `env(safe-area-inset-top)`，底部 dock 加 `env(safe-area-inset-bottom)`。同时把 `WKWebView.scrollView.contentInsetAdjustmentBehavior` 设为 `.never`，避免系统再扣一次安全区导致双重留白。

4. **系统选择器放宽**
   iOS 的 `input[accept]` 过滤比桌面严，`.cube`、`.heic` 这类扩展名系统不认识，会在选择器里把文件灰掉。shim 把 `#file` 改成 `image/*,video/*`、`#cubeFile` 改成 `*/*`、`#jsonFile` 加上 `text/plain,*/*`，文件才能选得出来。

5. **持久化**
   `WKWebViewConfiguration.websiteDataStore = .default()`，localStorage 落盘（页面 28 处用到，存的是预设与偏好）。页面没用 IndexedDB，所以不需要额外处理。

6. **外壳一致**
   窗口与 WebView 底色都是 `#08080A`，`isOpaque = false`，状态栏 `lightContent`、`UIUserInterfaceStyle = Dark`、启动屏是纯 `#08080A` 图片 —— 从点击图标到页面出画，不闪白。

另外：`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 打开，你可以在「文件」App 里直接看到 `Iris` 目录；外链（页面里指向 http/https 的链接）走系统 Safari，不在 WebView 里开。

---

## 三、已验证 / 未验证

**在真实页面里跑过（Chromium 无头 + 注入同样的 shim + 假原生桥）：**

- 启动 6 秒：**0 条消息**（不会像安卓那样开机乱存）
- 无手势触发保存：**0 条**（被手势闸拦下）
- 手勢内导出 512KB：16 块、**524,288 字节逐字节一致**，sha256 相同，文件名与 MIME 正确送达
- 样式补丁生效、页面无 JS 报错、WebGL canvas 正常出画

**没能验证（这台机器做不到，如实说明）：**

- Swift 代码未编译过（没有 Swift 工具链，更没有 iOS SDK）。工程量很小（4 个文件、约 260 行），但第一次在 Mac 上编译有可能碰到签名或 API 版本的小问题，`build_ipa.sh` 会直接报出来。
- 未在真机 iPhone 上跑过，未测过相册写入的实际体验、HEIC 实况照片的配对、视频导出的耗时。
- 图标只在本地校验过尺寸与无 alpha；未通过 `Assets.car` 编译（用的是 `CFBundleIconFiles` 传统方式，iOS 会自动取 @2x/@3x）。

---

## 四、装到手机上

未签名 ipa 不能直接装。三条路：

| 方式 | 需要 | 有效期 |
| --- | --- | --- |
| 爱思助手 / Sideloadly / AltStore 自签 | 你自己的 Apple ID（免费账号即可） | 7 天，到期重签，桌面图标不丢数据 |
| TrollStore / AppSync（越狱） | 越狱设备，且系统版本在支持范围 | 长期 |
| TestFlight / App Store | Apple Developer 账号（￥688/年）+ 正式签名 | 90 天 / 永久 |

自签最省事：电脑装爱思助手 → 连手机 → 「IPA 签名」→ 选 ipa 和你的 Apple ID → 装。

---

## 五、已知限制

- **视频导出**：iOS 的 MediaRecorder 只出 `video/mp4`（H.264），不出 WebM。页面本身已经有 mp4 回退（先试 `video/mp4;codecs=avc1.42E01E`，不支持才退 webm），所以在 iPhone 上导出的是 mp4 —— 反而比桌面导出的 WebM 更适合直接进相册。
- **GIF**：页面 GIFF89a 编码是纯 JS 实现，上限 400 帧 / 256 色，导出大动图在手机上会慢，属页面本身设定。
- **WebGL 性能**：8K 级大图 + 319 滤镜叠实时预览，在旧机型上会掉帧，与容器无关。
- **相册写入**：只在第一次弹权限，之后静默。被系统拒绝时文件仍在 `Documents/Iris/`，可用「文件」App 取。
- 只支持 iPhone（`UIDeviceFamily = [1]`），最低 iOS 16.0（页面用了 `100dvh`，iOS 15 不支持，会塌高度）。

---

## 六、目录

```
iris-ios/
├── Sources/
│   ├── AppDelegate.swift          窗口、深色底
│   ├── ShellViewController.swift  WKWebView + JS 桥 + 相册/分享
│   └── SaveSession.swift          分块顺序写盘
├── Resources/
│   ├── index.html                 你的页面，逐字节未改
│   ├── iris-ios-shim.js           适配层（保存拦截 / 安全区 / 选择器）
│   ├── Info.plist                 1.0.1 (2)，com.iris.palette.ios
│   ├── LaunchImage.png            纯 #08080A 启动图
│   └── Icons/                     AppIcon 全尺寸（无 alpha）
├── build_ipa.sh                   一条命令出 ipa
└── .github/workflows/ios.yml      GitHub Actions 出 ipa
```
