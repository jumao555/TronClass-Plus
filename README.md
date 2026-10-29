# TronClass Plus · 重庆邮电大学适配版

基于原作者 [wilinz](https://github.com/wilinz) 的
[tronclass_plus](https://github.com/wilinz/tronclass_plus) 项目修改的非官方 Flutter 客户端。
本分支主要适配重庆邮电大学的统一身份认证和 TronClass 门户，并修复登录页面生命周期问题，增加手机端扫码错误诊断。

## 项目来源

- 原作者：**[wilinz](https://github.com/wilinz)**
- 原始仓库：**[wilinz/tronclass_plus](https://github.com/wilinz/tronclass_plus)**
- 当前仓库：**[jumao555/TronClass-Plus](https://github.com/jumao555/TronClass-Plus)**

原项目面向桂林电子科技大学，提供了客户端界面、二维码签到、数字签到、雷达点名、多账号管理和 WebView 门户等基础功能。
这些基础能力及原始工程来自原作者，本仓库是在原项目基础上的学校适配与问题修复，感谢原作者的工作。

## 本分支的改动

| 范围 | 改动说明 |
| --- | --- |
| 学校配置 | 新增 `lib/data/school_config.dart`，集中配置学校名称、统一认证、身份代理、LMS 和门户地址，替换原工程中的桂电地址。 |
| 重邮登录适配 | 使用学校实际的 CAS 登录跳转和门户 Cookie 会话；支持已有会话直接返回门户，修正缺少 `service` 时的处理和备用 CAS 入口。 |
| 登录页兼容 | 扩展登录页面中 AES 加密参数的读取方式，兼容不同输入框、元信息及脚本中的盐值字段。 |
| 登录红屏修复 | 为每个登录页隔离控制器及表单 Key；验证码输入框随弹窗销毁，避免提前释放；页面退出后停止相关界面更新和路由操作，取消短信倒计时。 |
| 登录流程 | 将认证重试与登录成功后的保存、界面操作分开，避免界面或本地保存异常再次触发密码提交；取消验证码输入时结束本次流程。 |
| 扫码错误处理 | 正确区分 JSON、文本及登录网页响应，避免将字符串直接转换成 JSON 对象；区分登录失效、请求被拒绝、网络超时和二维码过期等情况。 |
| 手机端诊断 | 失败页提供“查看错误详情”和“复制诊断信息”；扫码页右上角可查看当前账号最近一次失败记录，无需连接 Android Studio。 |
| 诊断脱敏 | 不记录密码、Cookie、二维码正文或 URL 查询参数值；隐藏点名 ID 和不在白名单中的服务端消息，并移除原来的二维码原文日志。 |
| 登录页文案 | 账号输入框统一显示“统一认证码”，删除原来的桂电初始密码提示。 |
| Android 构建 | 调整为 Gradle 8.13，配置 Maven 镜像，将 Gradle 堆内存上限设为 3 GB、并发任务数设为 2，降低本地构建的内存压力。 |
| 回归测试 | 新增登录页状态隔离、验证码弹窗关闭、延迟响应、错误响应解析、诊断脱敏和详情复制等测试；当前相关回归测试共 27 项。 |

## 功能与验证范围

- 统一认证登录、账号保存及切换。
- 扫描课堂二维码并提交签到结果。
- 保留原项目的数字签到、雷达点名和 Web 门户入口。
- 手机端查看、复制和回看最近一次扫码错误详情。

当前分支的构建与设备调试主要在 **Android** 上完成。原项目的 iOS、macOS、Windows、Linux 和 Web 工程仍保留，
但本分支尚未逐个平台验证重邮适配效果。

## 开发环境

项目声明的 Dart SDK 要求为 `^3.9.0`。本地已验证的 Android 调试环境为：

- Flutter 3.44.2 / Dart 3.12.2
- JDK 21
- Gradle 8.13
- Android Gradle Plugin 8.9.1 / Kotlin Gradle Plugin 2.1.0
- Android SDK、Android Studio，以及已开启 USB 调试的 Android 手机

Android SDK 和 Flutter SDK 的本机路径由工具生成到 `android/local.properties`，该文件不提交到仓库。

## 本地运行

```bash
git clone https://github.com/jumao555/TronClass-Plus.git
cd TronClass-Plus
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

将 `DEVICE_ID` 替换为 `flutter devices` 列出的 Android 手机设备 ID。
也可以在 Android Studio 中打开项目根目录，选择 Android 手机后运行 `lib/main.dart`。

生成 ARM64 Android 调试安装包：

```bash
flutter build apk --debug --target-platform android-arm64
```

安装包输出到 `build/app/outputs/flutter-apk/app-debug.apk`。
构建目录和 APK 不随源码提交；本仓库的发布入口为 [Releases](https://github.com/jumao555/TronClass-Plus/releases)。

## 登录与扫码诊断

使用学校的统一认证码和统一认证密码登录。学校要求图形验证码或短信验证时，按弹窗提示完成验证。

扫码失败时：

1. 在结果页点击 **查看错误详情**。
2. 点击 **复制诊断信息**，保留或反馈诊断文本。
3. 离开结果页后，可在扫码页右上角的历史图标中查看该账号最近一次失败记录。

诊断文本包括错误时间、HTTP 状态码、脱敏后的请求及最终地址、返回内容类型，以及已识别的错误原因。
二维码过期或签到结束是正常的失败结果；验证完整签到流程仍需要课堂上当前有效的二维码。

## 学校配置

主要入口集中在 `lib/data/school_config.dart`：

| 配置 | 用途 |
| --- | --- |
| `schoolName` | 界面上的学校名称 |
| `casBaseUrl` | 学校统一身份认证服务 |
| `identityBaseUrl` / `identityCasLoginUrl` | 身份代理与 CAS 入口 |
| `lmsBaseUrl` / `portalUrl` | TronClass API 和门户页面 |
| `centerBaseUrl` | 配套中心服务 |
| `useCookieLogin` | 当前学校采用的 Cookie 登录模式 |

适配其他学校时，需要根据该校的实际认证协议、跳转链和接口验证配置，不能只替换学校名称或复用历史票据。
原项目的 OIDC 登录路径仍保留在代码中，但当前重邮配置采用 CAS 门户 Cookie 登录。

## 回归测试

运行本次适配与修复相关的 27 项测试：

```bash
flutter test test/portal_login_test.dart test/login_lifecycle_test.dart test/login_dialogs_test.dart test/qr_sign_diagnostics_test.dart test/qr_sign_diagnostics_dialog_test.dart
```

测试使用模拟请求和界面环境，不需要真实账号，也不会向学校提交签到或发送短信。

## 目录结构

```text
lib/auth/          登录页面、验证码弹窗、账号管理
lib/data/          学校配置、HTTP 客户端、认证和接口服务
lib/tronclass/     首页、二维码、数字签到和雷达点名页面
lib/webview/       Web 门户与 Cookie 同步
lib/common/        通用提示等组件
test/             登录生命周期和扫码诊断等回归测试
tool/             登录诊断工具
```

## 发布说明

仓库保留了原项目的 Android Release 工作流。使用前需要在 GitHub Actions 中配置自己的
`ANDROID_KEY_BASE64`、`ANDROID_KS_PASS` 和 `ANDROID_KEY_ALIAS`，并检查工作流中的 Flutter 版本与签名设置。
该自动发布流程尚未在本分支验证；本地调试构建不需要这些发布密钥。

## 致谢

感谢 [wilinz](https://github.com/wilinz) 提供原始项目。
了解原版实现、历史与说明，请访问 **[原作者仓库](https://github.com/wilinz/tronclass_plus)**。
