# Android 墨水屏适配方案（小米电纸书 Note）

日期：2026-11-05。状态：业务代码和测试用例已编写，已有环境下的浏览器检查通过；Flutter 编译/测试、APK 构建和真机验收待具备相应环境后进行。

## 1. 目标与当前工作区

- 用户需求：安卓墨水屏单独开关，只影响 Android，尽量新增独立链条，保护原有行为。
- 用户已选择通用 Android 适配，并补充实际设备为“小米电纸书 Note”；以该设备为真机验收目标，代码保持通用 Android 路径。具体硬件版本、系统版本和私有刷新接口尚未核实，不推测设备参数。
- 用户澄清：是在咨询动画如何适配，并未要求全量禁止。随后授权“按照你的经验来，最佳优化”。采用正文静态整页、关闭主要转场及循环动效、保留直接操作的推荐方案。
- 当前调查目录：`D:\Download\cse\LiteTale-main`。
- 已阅读 `AGENTS.md` 和 `docs/LUNA_HANDOFF_0.0.18.md`。其中指定的 `D:\Projects\LiteTale` 在本机不存在；当前目录没有 `.git`，无法提供 Git 差异或判断未提交修改。已向用户说明当前目录；继续其授权的本轮工作。
- 先更新本文再开始业务改动，业务改动完成后编写测试；完成项逐项勾选。

## 2. 已调查的完整链条

| 环节 | 当前代码与调查结果 |
| --- | --- |
| 开关入口 | `lib/settings/settings_page.dart` 是“显示”设置页；`settings_widgets.dart` 的 `SettingsSwitch` 调用现有跨平台开关控件。 |
| 持久化与启动 | `SettingsPreferencesCubit` 使用 Rust property 数据库；`lib/pages/init_page.dart` 在数据库初始化后载入偏好，`lib/main.dart` 提供全局 Cubit 并构建主题。独立偏好可以复用数据库 API，无需改 Rust 接口或生成桥接代码。 |
| 备份合同 | `lib/settings/data_snapshot.dart` 和 `rust/src/api/backup.rs` 都有设置白名单；现有 `litetale.settings_v1` JSON 还受到 Rust 字段校验。直接往旧设置塞字段会扩展旧备份合同。 |
| 阅读入口 | `lib/main.dart` 的 `/novel/reader` 按 `ReaderTypeCubit` 选择分页或连续滚动；`novel_download_info_page.dart` 另有直接打开 `ReaderPage` 的离线入口。 |
| 阅读数据 | `ReaderCubit` 负责章节、分页、预取、进度和跨章；`ReaderPaperView` 负责绘制单双页。它们继续复用。 |
| 翻页输入 | 普通分页的点击已通过 `ReaderPageController.jumpToPage` 立即换页，但 `PageView` 拖动仍连续绘制；仿真翻页另走 `PageCurlView`。点击、手势、音量键、双页映射和章边界必须统一进入新显示分支。 |
| 连续滚动 | `HtmlReaderPage` 实际是 Flutter 滚动阅读器，并使用 `FrameAutoScroller`。首版不改它的滚动算法，墨水屏模式打开新书时使用分页。 |
| 全局动效 | 主题揭幕、统一加载组件和底部导航部分动效已经响应 `MediaQuery.disableAnimations`；显式 `HorizontalCoverPageRoute`、发现页 `TabBarView`、弹窗仍需要独立分支。底部导航的模糊/半透明不能仅靠减少动画解决。 |
| 富文本 | `ReaderParagraphLayout` 会读取正文自带文字、背景及边框颜色，外层主题不足以保证正文对比度。 |
| EPUB | `ReaderCubit` 将纸色和文字颜色传给 `EpubCssReader`，再通过原生 WebView/JS 生成页面图片。`epub_page_engine.js` 目前只强制 body 文字颜色，子节点 CSS 仍可能覆盖。缓存键已包含完整 options。 |
| 图片 | 普通封面及阅读图片没有额外淡入，但 `CachedImageProvider` 使用 `MultiFrameImageStreamCompleter`，动图仍可能持续播放。开启时显示静态首帧，独立缓存身份；保留原图信息，不做全局二值化，不修改原文件。 |
| 原生刷新 | Android 当前没有 EPD 刷新通道；通用 Android 显示 API 不能可靠控制所有厂商墨水屏的全刷、局刷或波形。 |

## 3. 推荐的首版产品行为

1. 在“我的 → 显示”增加“墨水屏模式”独立开关，仅 Android 显示，默认关闭。
2. 开启时使用白底、深色文字、清晰边界；主要按钮和选中状态不只依靠颜色区分。暂停应用配色、深色模式和纸张背景在当前显示中的作用，原偏好值不被改写。
3. 使用静态整页翻页：点击立即换页，滑动结束且达到阈值后只换一页，不让纸面跟随手指移动。音量键沿用原开关和原输入规则。
4. 暂时使用分页阅读，仿真翻页及逐帧自动滚动不进入墨水屏路径。阅读设置同时显示实际生效模式和恢复说明。
5. 关闭页面切换、主题揭幕、导航、阅读翻页、主要弹窗过渡及循环加载动画。移除底部导航模糊、阅读渐变书脊和半透明菜单。原生按钮、开关及输入控件继续复用，不为极短的状态反馈或光标重写整套交互。
6. 普通文字、富文本和可重排 EPUB 使用高对比文字；封面、插图、SVG 图稿及固定版式艺术页保留内容信息。固定版式不承诺强制转换所有图内文字。
7. 关闭开关后继续使用原主题、背景、阅读模式及仿真翻页偏好，不需要迁移旧数据。
8. 主开关只放在显示设置页。阅读器内只说明当前生效策略，避免阅读过程中主动替换阅读引擎；重新打开阅读器后选择对应路径。
9. 列表保留手指拖动和现有惯性，方便浏览长目录；去掉装饰性的边缘效果。是否限制惯性待真机体验后决定。正文仍按第 3 条整页切换，不采用连续自动滚动。
10. 加载显示静态文字或图标；真实进度只随业务数据更新并立即显示，不伪造进度、不阻塞完成/失败/重试。GIF/WebP 等动图显示静态首帧。
11. 数据库初始化后加载墨水屏偏好；模式生效后的应用等待使用静态提示。保留原初始化链条，不为消除偏好读出前短暂的启动提示改造启动架构。

## 4. 隔离设计

数据流：

```text
Android 显示设置中的开关
  → 新 EInkPreferencesCubit
  → 独立 property：litetale.android_eink_v1
  → EInkPolicy（非 Web Android 且开关开启）
      ├─ 独立高对比主题 / 静态导航 / 静态加载及主要弹窗
      ├─ 阅读入口：有效模式为分页
      └─ EInkReaderView / 有效正文样式 / EPUB 渲染 options

未开启或其他平台 → 现有主题、阅读入口及组件
```

- 使用 `!kIsWeb && defaultTargetPlatform == TargetPlatform.android` 作为统一 UI 能力门；保留可注入的平台参数用于测试。任何原生调用仍必须满足真实 Android 条件。
- 独立 Cubit 使用现有 `loadProperty/saveProperty`；新键缺失、损坏时回到关闭，读写顺序串行化，保存成功再发布，读取旧值不能覆盖用户的新操作。
- 不增加旧 `SettingsPreferences` 字段，不改 `reader_type`、`reader_page_curl_v1`、`ReaderTheme` 或 `ReaderBackground` 的保存值。
- 新键不加入 LiteTale 数据快照：导出、合并导入、覆盖导入都不更改本机墨水屏选择。这是显示设备偏好，不随应用内书籍/设置快照迁移。
- 上述“不随快照迁移”仅指 LiteTale 快照。Android 系统自动备份可能复制整个属性数据库；若以后要求严格禁止系统迁移，需要另建 no-backup 存储，本版不扩展到此范围。
- 新模块缺席的独立 widget 测试默认视为关闭，避免强制所有旧页面 harness 增加 provider。
- 切换开关不更换根 Navigator 的 key，不重建整棵导航树。应用外观即时生效，阅读引擎按原约定在重新打开阅读器后选择，保留当前路由和既有阅读状态。
- 不使用全局 `TickerMode(false)` 冻结动画，不采用人为黑白闪屏冒充硬件全刷，不调整硬件加速或全局低帧率。
- `MediaQuery.disableAnimations` 仅为辅助信号；必须核验主要转场实际取消、循环加载实际静止。保留现有基础控件，不把全量重写控件作为首版要求。
- 开启时取消已有过渡并归位最终状态；路由、弹窗、提示继续正常完成 Future、焦点与遮罩清理，不能让业务依赖已停止的动画完成事件。
- 新分页只管理手势和显示，页码由原 `ReaderCubit` 持有：继续 `_onViewChanged → onPageChanged → 原进度存储`，跨章和横屏双页使用原映射。
- 新 EPUB 参数仅在 Android 开启时传入；关闭和其他平台不添加新 options 字段，保护旧缓存键及旧 JS 路径。开启缓存自然独立，不能复用普通配色的页面位图。
- 富文本只更改绘制配色，不改文字、字号、行高、缩进或排版宽度；若实现引入影响测量的参数，必须同时传入测量和绘制，禁止两者不一致。

## 5. 拟新增文件

| 文件 | 职责 |
| --- | --- |
| `lib/eink/eink_preferences.dart` | 独立持久化 Cubit、默认关闭、加载及保存错误处理。 |
| `lib/eink/eink_policy.dart` | 唯一平台门、有效阅读模式、纯色纸面和文字策略。 |
| `lib/eink/eink_scope.dart` | 向后代提供无动画策略及辅助标志；未启用保持旧参数。 |
| `lib/eink/eink_theme.dart` | 独立白底高对比主题、组件边界及无水波纹配置，保留现有字体与地区字形。 |
| `lib/eink/eink_setting.dart` | Android 专属主开关、保存状态与错误反馈。 |
| `lib/eink/eink_reader_view.dart` | 静态整页组件、滑动阈值及一次手势一次翻页；通过回调复用原翻页和章边界逻辑。 |
| `lib/eink/eink_navigation.dart` | 不模糊、不滑动的底部导航与发现页标签内容分支；沿用原目标页面及加载时机。 |
| `lib/eink/eink_overlays.dart` | 墨水屏静态弹窗入口；关闭时转调原自适应弹窗 API，保留参数语义。 |
| `lib/eink/eink_progress_indicator.dart` | 静态等待状态；关闭时显示传入的原加载控件，不伪造完成进度。 |
| `test/eink_preferences_test.dart` | 默认、持久化、并发、失败、平台限制。 |
| `test/eink_display_test.dart` | 设置入口、主题、静态导航及关闭恢复。 |
| `test/eink_navigation_test.dart` | 路由/弹窗立即完成、静态加载和发现标签懒加载。 |
| `test/eink_reader_test.dart` | 静态翻页、手势、音量键、跨章、横屏双页、进度。 |
| `test/eink_epub_test.dart` | EPUB 参数、颜色、缓存分离和旧路径兼容。 |
| `test/scripts/eink_epub_playwright_harness.cjs` | 本机已有浏览器上的实际 CSS/排版回归，不下载依赖。 |
| `integration_test/android_eink_test.dart` | 开关→存储重读→快照往返→阅读→退出流程，书籍为 fixture；包含生产启动链，未模拟真实进程冷启动。 |

## 6. 拟修改文件和边界

核心连接点：

| 文件 | 修改内容 |
| --- | --- |
| `lib/main.dart` | 提供新 Cubit；选择新主题/scope；阅读路由选择有效模式。未开启走原分支。 |
| `lib/pages/init_page.dart` | 数据库就绪后加载新偏好，模式生效后使用静态等待；不改账号、书源、字体等初始化语义。 |
| `lib/settings/settings_page.dart` | 增加独立 Android 开关。 |
| `lib/settings/reader_settings_page.dart` | 显示墨水屏的有效分页/无仿真状态，保留旧偏好。 |
| `lib/settings/theme_paper_page.dart` | 提示当前纸色、主题由墨水屏模式接管，避免用户修改后误以为失效；不覆盖原值。 |
| `lib/pages/novel/reader_page.dart` | 新静态分页分支、有效纸面颜色、纯色控制栏；点击/音量键/跨章/双页统一分发；阅读菜单状态。 |
| `lib/widgets/reader_curl_setting.dart` | 墨水屏启用时显示暂停效果，关闭恢复旧选择。 |
| `lib/widgets/reader_paper_view.dart` | 新模式隐藏书脊渐变、提高标题对比度、向富文本传有效绘制策略。 |
| `lib/widgets/reader_styled_paragraph.dart` | 可选高对比绘制参数，默认保持旧行为。 |
| `lib/services/reader_rich_typography.dart` | 仅启用时覆盖正文颜色、底色与边框；不改变排版度量。 |
| `lib/pages/novel/reader_cubit.dart` | 可选显示策略回调；EPUB 纸色/墨色及独立渲染参数；无参数时原行为。 |
| `lib/assets/epub_page_engine.js` | 新参数为真时对可重排文本注入独立高对比 CSS；保留图像、SVG 与固定版式资源，不改书籍源文件。 |
| `lib/theme/horizontal_page_transitions.dart` | 普通与显式路由的墨水屏静态分支；关闭时保留原 300ms 转场。 |
| `lib/pages/home_page.dart` | 墨水屏选择静态底部导航，其他平台保留原导航。 |
| `lib/pages/home/index_page.dart` | 墨水屏标签直接切换，避免 TabBarView 拖动及点击过渡；不改变书源及页面加载语义。 |
| `lib/widgets/platform_controls.dart` | 墨水屏底部弹窗取消进入/退出过渡及拖动变形；基础控件保留；原参数在关闭时原样传递。 |
| `lib/widgets/source_picker_sheet.dart` | 书源选择弹窗接入相同静态显示策略，保持选择和账号逻辑。 |
| `lib/widgets/app_loading_indicator.dart` | 启用时使用静态等待提示，关闭时原组件。 |
| `lib/settings/settings_widgets.dart` | 统一设置弹窗接入静态入口，检查高对比选中与禁用状态。 |
| `lib/widgets/cached_image.dart` | 墨水屏动图首帧显示，普通模式仍使用原多帧图片链条。 |
| `lib/widgets/reader_raster_readiness.dart` | 阅读图片接入静态首帧策略，同时保持就绪通知、失败提示与资源释放。 |

以下现有文件含直接调用加载/自适应弹窗的入口，需要小范围接入新 wrapper。只替换显示入口，保留业务参数、回调、错误处理和旧分支：

- `lib/pages/articlelist/articlelist_page.dart`
- `lib/pages/home/bookshelf_page.dart`
- `lib/pages/home/category_page.dart`
- `lib/pages/home/font_settings_page.dart`
- `lib/pages/home/history_page.dart`
- `lib/pages/home/recommend_page.dart`
- `lib/pages/light_novel_shelf_browser_page.dart`
- `lib/pages/login_page.dart`
- `lib/pages/local_epub_library_page.dart`
- `lib/pages/novel/novel_download_info_page.dart`
- `lib/pages/novel/novel_info_page.dart`
- `lib/pages/novel/reviews_page.dart`
- `lib/settings/source_settings_page.dart`
- `lib/settings/data_settings_page.dart`
- `lib/settings/rule_source_manager.dart`
- `lib/widgets/app_color_settings.dart`
- `lib/widgets/cf_action_loader.dart`
- `lib/widgets/wenku8_verification_page.dart`

以下是上轮“全量无动画”误解下扩展的候选清单，现撤回为后续真机观察项目，不作为首版必须修改范围。只有发现持续刷新或明显可读性问题时才评估：

- `lib/pages/home/about_page.dart`
- `lib/pages/search_page.dart`
- `lib/pages/shelf_catalog_page.dart`
- `lib/pages/recommend/recommend_page.dart`
- `lib/pages/shelf_login_page.dart`
- `lib/pages/novel/novel_downloading_page.dart`
- `lib/pages/novel/novel_download_page.dart`
- `lib/settings/reading_statistics_page.dart`
- `lib/widgets/bili_recovery_button.dart`
- `lib/widgets/huanmeng_recovery_button.dart`
- `lib/widgets/wenku8_recovery_button.dart`
- `lib/widgets/material_choice_controls.dart`
- `lib/widgets/launcher_icon_settings.dart`
- `lib/widgets/reader_volume_turn_setting.dart`
- `lib/widgets/source_settings.dart`
- `lib/widgets/source_website.dart`

现有 `ThemeRevealHost`、`ExpressiveLoadingIndicator` 的静态分支复用；主题揭幕另外处理开启时取消已有过渡。原 `FluidNavigationBar` 由新导航分支绕过，无需改造其内部动效。原 `HtmlReaderPage` 的正文滚动和 `FrameAutoScroller` 保留，只将其颜色选择弹窗连接到统一适配入口；新模式打开阅读器时选择分页。`AnimatedBuilder` 仅监听真实业务数据的用法不是动画，不应机械删除。列表的原生拖动/刷新反馈仍保留，避免首版为极短交互重写整套控件。

不修改书源协议、账号、网络请求、搜索、书架、历史格式、Rust 数据库接口、备份白名单和原生厂商接口。`EpubCssReader` 既有 options 缓存键可复用，须测试验证。

实际补充的旧测试是 `test/theme_reveal_host_test.dart` 和 `test/data_snapshot_test.dart`；其余覆盖集中在 5 个新增 `test/eink_*_test.dart` 文件。`test/app_motion_test.dart`、`test/settings_layout_test.dart`、`test/reader_volume_turn_test.dart`、`test/reader_document_integration_test.dart`、`test/epub_css_visual_test.dart` 保留原预期，列入具备 Flutter 环境后的回归清单。

## 7. 实施顺序及状态

- [x] 调查设置→存储→启动→导航→阅读→富文本/EPUB→缓存/备份链条。
- [x] 确认用户需要通用 Android 方案。
- [x] 记录实际设备“小米电纸书 Note”，并纠正“用户要求全量无动画”的误解。
- [x] 在 `CLAUDE.md` 记录询问与硬性要求的区别及当前推荐取舍。
- [x] 落地方案、列出新增/修改文件与验收边界。
- [x] 用户授权按专业经验优化，继续当前工程实施。
- [x] 完成独立偏好、策略、主题和开关；关键隔离边界写清代码注释。
- [x] 完成静态分页、富文本/EPUB 显示、设置状态和主要转场/循环动效接入。
- [x] 业务改动完成后，再新增或修改测试文件；若实施中发现现存 bug，先写复现测试再修复。
- [x] 完成可执行的静态/浏览器回归；Flutter/Dart 检查因本机缺少 SDK 未运行，并已记录。
- [x] 完成代码级复核：Android 开关、非 Android 门禁、关闭恢复、快照隔离、普通转场回归分支。
- [ ] 有设备条件时完成 Android 墨水屏真机验收；逐项标记通过、失败或未验证。
- [x] 完成一项后更新本方案对应状态，不提前标记完成。

## 8. 验收用例

1. 全新安装默认关闭；Android 能看到开关，iOS、桌面和 Web 不显示且策略恒为关闭；即使存储中有 true 也不影响非 Android。
2. 连续快速切换、读写重叠、保存失败、异常 JSON、重启均有稳定结果；失败不能显示已成功保存。
3. 启用前设置自定义主题、背景图、仿真翻页及连续滚动；启用后旧属性值不变，关闭后恢复原偏好。
4. 通过书籍详情、历史、离线下载入口阅读；文本/插图顺序、章节和阅读记录不受影响。
5. 左/中/右点击、短滑动取消、长滑动单次翻页、快速手势和音量键；首尾章、跨卷、横屏双页不丢页、不重复保存、不触发后台翻页。
6. 验证原 tapToTurn=false 的菜单行为和仍可用的滑动入口；音量键未启用时仍由系统处理。
7. 富文本中的浅色文字、深色背景、表格边框可辨认；开启前后分页度量一致；固定版式/插图保留可读信息。
8. 普通 EPUB→墨水屏 EPUB→普通 EPUB 来回打开时不串缓存；字体、缩放、旋转后的重排和阅读位置仍正确。
9. 普通分页与墨水屏相同版式保持当前位置；连续滚动目前只保存章节，切换后按已有章节进度定位，不能要求精确段落恢复。
10. 页面 push/pop、标签、底部导航、主要设置弹窗和加载呈现静态状态，不被显示策略卡住；返回、提示与控件反馈仍可操作，普通模式保持原动效。
11. LiteTale 快照导出不含新键；合并导入、覆盖导入、导入旧快照均保留当前墨水屏开关。
12. 在用户的小米电纸书 Note 上观察静止时是否有无意义连续刷新、翻页残影、灰阶图像、菜单可见性和操作延迟。记录实际型号/系统版本；模拟器结果不代表物理刷新已验收。
13. 正文翻页、路由、主要弹窗和主题直接呈现最终状态；推进 50/300/1000ms 验证没有过渡插值。控件正常反馈和异步数据变化不作为失败。
14. 列表直接拖动、惯性及长目录访问仍可用；加载持续等待时提示静止，完成、报错和重试仍有效；动图保持首帧。
15. 普通模式动画中开启墨水屏模式后不残留遮罩或不可点状态；关闭后原动画恢复。冷启动能恢复开关，不承诺偏好读出之前的原生/启动提示完全无动效。

## 9. 风险及明确边界

- 不承诺无回归；通过新模块、默认关闭、平台门、旧分支保留以及上述回归用例降低风险。
- 首版是软件显示适配，不承诺硬件全刷、局刷、A2/GC16 波形和残影彻底消除。目标设备已知为小米电纸书 Note，但其具体系统版本和可用厂商接口仍须核实；不直接套用其他厂商的刷新 API。
- 系统键盘、系统选择器、系统控制的启动画面和第三方验证网页不属于本轮应用动效范围；屏幕固件产生的物理刷新闪烁不能通过关闭应用动画保证消除。
- 无论关闭显示动效还是改静态换页，都不能把帧率直接等同于屏幕物理刷新频率。
- 原连续滚动不保存精确段落位置，跨阅读引擎只能承诺保留既有章节记录。
- 当前 `.fvm` 引用的是旧 macOS 路径文本，不是可用 Flutter SDK；PATH 未找到 Flutter/Dart/Java/ADB，交接中的工具链和 Android SDK 路径均不存在，也没有 `.dart_tool/package_config.json`。目前无法承诺本机能跑 Flutter 测试或构建。
- 遵守用户要求：不安装环境、不使用 Docker、不批量删除文件。实施时只利用已有可用环境；若仍不可用，交付需明确列出未运行检查，不能宣称测试或构建通过。

## 10. 本轮验证记录

- Node `--check`：`lib/assets/epub_page_engine.js`、`test/scripts/eink_epub_playwright_harness.cjs` 通过。
- 已有本机 Chrome 的 EPUB 浏览器回归通过：正文、首字伪元素、表格尺寸、inline `!important`、SVG 原色、图片尺寸、固定版式保护，以及重复应用样式幂等性。
- 本地导入/括号检查覆盖 54 个涉及墨水屏的 Dart 文件，未发现缺失本地包导入或词法分隔符错误；这不是 Dart 编译器检查。
- `flutter test`、`dart analyze`、Android APK 构建及小米电纸书 Note 真机验证未运行：本机 PATH 和交接路径均没有 Flutter/Dart/Java/ADB/Android SDK，且未安装新环境。
- 已尝试 `flutter test test/eink_preferences_test.dart test/eink_display_test.dart`，系统返回找不到 `flutter`；未执行任何 Flutter 测试用例。新增 Dart 测试不得描述为通过。
- 后续应先执行 `flutter analyze`，再运行 5 个 `test/eink_*_test.dart`、本节上方列出的旧测试以及 `test/theme_reveal_host_test.dart`、`test/data_snapshot_test.dart`。之后通过既有 `tools/build_android.ps1` 构建，并执行 Android 设备测试；本轮未安装 APK。
- 尚未声称小米电纸书 Note 的全刷、局刷、A2/GC16 波形或残影表现通过；需要有设备和系统版本后按第 8 节用例验收。
