# Android 提交后自动发布

2026-11-05。用户授权设计、实施并推送 `https://github.com/hanxin1997/LiteTale`，并明确允许每次提交直接发布正式 Release。

## 已调查

- 远程默认分支为 `main`，基线提交 `7f2477a9a2d6c1f9924bf2e1050610d04e1f6ddf`；当前账户 `hanxin1997` 有仓库管理和推送权限，Actions 已启用。
- 本地源码目录无 `.git`；已在系统临时目录独立检出远程，确认现有 806 个路径均存在，本地差异为前一轮墨水屏修改。保留远程历史，仅叠加已核验改动，不强制推送。
- 旧 `.github/workflows/release.yml` 只支持手动触发，混合六个平台，Android SDK 设置和当前项目不完全一致，发布前也未运行当前回归用例。
- 当前无 Actions secrets，也无本机 debug.keystore。自动构建必须使用固定私有签名，不能每次重新生成临时 debug 证书。
- 项目采用 Flutter 3.29.3、JDK 17、Gradle 8.13、AGP 8.12.1、Rust/FRB 2.11.1、NDK 27.0.12077973；原生模块编译 SDK 35，Rust 插件编译 SDK 33。

## 实施设计

1. 新增独立 `.github/workflows/android-release.yml`：`main` 每次 push 和手动触发均运行，现有多平台手动流程不改动。
2. Ubuntu runner 自动配置构建依赖，固定 Flutter stable 3.29.3、Rust 1.90.0、Java 17、SDK 33/35、NDK 27.0.12077973、build-tools 35.0.0。只在云端安装依赖，不安装本机环境。
3. 使用锁文件解析依赖，先执行静态分析和 Flutter 测试，通过后才构建 ARM64 与 x86_64 两种 APK。失败不发布，保留诊断日志。
4. 为 fork 生成一次专用 PKCS#12 签名，存入 GitHub Actions encrypted secrets。私钥不进入源码、缓存、构建日志或下载产物；后续构建只复用该密钥。
5. 从 `pubspec.yaml` 读取版本名，构建号使用 `100000 + github.run_number`，tag 为 `v版本名+android.构建号`，指向本次提交。每次生成独立正式 Release（draft=false，prerelease=false），重跑同一任务时使用同一tag更新产物。
6. 重签构建产物后验证包名、版本、签名、ABI、ZIP、必要原生库和16KB对齐，发布两个 APK、SHA256SUMS 和校验 JSON；同时保留 Actions artifact。
7. 墨水屏改动随本次提交一起推送。推送后跟踪 Actions，出现可修复的编译/测试问题继续修复并推送，直到产物可用或确认外部阻断。

## 文件范围

- 新增 `.github/workflows/android-release.yml`：自动构建和正式发布流程。
- 修改 `tools/verify_android_apks.py`：同一校验逻辑支持 Windows 本地与 Linux CI，保留原校验项。
- 修改 `ANDROID.md`：说明推送触发、下载入口、固定签名与首次安装限制。
- 新增/更新本方案与必要验证测试；前一轮墨水屏业务和测试一并提交。
- 不修改旧多平台发布流程、iOS、应用更新检查源或仓库版本文件。应用内更新目前仍指向上游，本轮发布通过用户的 GitHub Releases 下载。

## 签名与版本边界

- fork 新签名与上游原包不同，首次不能覆盖安装原签名包；不能通过自动卸载解决，以免丢阅读数据。用户需要先备份，或将原签名提供给仓库维护者迁移。
- 后续 fork APK 在相同私有签名下按递增构建号覆盖升级。
- 验证成功只代表云端构建、测试和APK静态检查通过，仍需在小米电纸书 Note 上验证物理刷新、输入和阅读体验。

## 状态

- [x] 调查远端、权限、工具链、旧构建链和签名现状。
- [x] 实施前落地方案。
- [x] 完成workflow、校验工具与文档。
- [x] 配置固定私有签名：两项 GitHub encrypted secrets 已写入，本机 DPAPI 加密备份位于 `%LOCALAPPDATA%\LiteTale\signing\hanxin1997-LiteTale.dpapi`，未进入源码。
- [x] 本地APK校验工具 11 项合成测试通过；墨水屏改动与CI已叠加独立检出，Git差异检查无空白错误。
- [x] 提交并推送 main：初始提交 `f70841d`，Actions run `42037676603` 已由 push 自动触发。
- [ ] 跟踪云端测试、构建和Release结果。

首轮云端分析发现新图片测试使用旧版本 decoder callback 参数；改为 Flutter 3.29 的 `getTargetSize` 参数后重跑。同步加入 artifact overwrite，确保重跑相同任务不会因同名产物失败。
