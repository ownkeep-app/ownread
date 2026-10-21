# OwnRead / 私人阅读

跨平台（**Android**、**macOS**）离线 TXT 小说阅读器。不联网、不使用数据库，全部数据保存在本地文件仓库。

## 功能概览

- 集中图库：本地图片 / 视频存入应用私有目录，离线查看；图片可缩放、导入和逐张导出；视频使用图标卡片，支持播放 / 暂停、拖动进度和静音
- TXT 导入并自动分章（UTF-8 / GBK / GB18030）；全文导出
- 设置中「导出所有 / 导入所有」：ZIP 备份整库（含进度与修改历史）；导入会先清空现有书籍
- 书架：排序、查找、删除（确认）、改名；显示章节数、总字数、阅读进度条、修改字数
- 点击进入阅读并跳转上次阅读位置
- 无限滚动阅读，预加载上一章 / 下一章
- 阅读时隐藏 TXT 中的空行（仅显示层处理，不改动文件；编辑器仍显示原文）
- 单击呼出侧栏（返回 / 查找替换 / 章节列表）；书架右上角「设置」可调淡色·暗色 / 主题颜色 / 阅读背景 / 字体 / 字号 / 行距（「主题」「排版」分组，默认折叠）/ 自动锁屏开关
- 双击进入就地编辑，右下角「保存」写回本地文件
- 查找替换与章节编辑均写入修改历史

详细产品说明见 [product.md](./product.md)。

## 环境要求

- Flutter **3.44+**（Dart **3.12+**，视频播放插件要求）
- Android SDK / Xcode（按需）
- 本机无需网络即可开发与运行（依赖已在 `pub get` 缓存中即可）

## 开发流程

```bash
cd ownread
flutter pub get

# 运行（优先 Android）
flutter devices
flutter run -d <android-device-id>

# macOS
flutter run -d macos
```

### 常用命令

| 命令 | 说明 |
|------|------|
| `flutter analyze` | 静态分析 |
| `flutter test` | 单元 / Widget 测试 |
| `flutter test --coverage` | 生成 `coverage/lcov.info` |
| `genhtml coverage/lcov.info -o coverage/html` |（可选）HTML 覆盖率报告 |

目标：**`lib/core/` 业务代码测试覆盖率 ≥ 95%**（当前用 `flutter test --coverage` 验证）。UI 页面以手动/集成验证为主。

### 目录结构

```
lib/
  main.dart
  core/
    models/          # 纯 Dart 模型
    services/        # 分章、替换、书架控制器、设置
    storage/         # 本地文件仓库（无 DB、无网络）
    theme/           # 暖橙色 Shadcn 主题
  features/
    library/         # 书架
    reader/          # 阅读 / 编辑 / 查找替换
assets/icon/         # 应用图标
test/                # 测试
```

### 本地数据布局

```
{ApplicationSupport}/ownread/
  library.json
  novels/{id}/
    meta.json
    chapters.index.json   # 章节标题 / 文件名 / 字数
    chapters/0000.txt …   # 每章一个小文件（编辑只写这一章）
    history.jsonl         # 追加写入的修改历史
```

阅读与保存均按章读写文件，避免整本上千万字重写。旧版单文件 `book.txt` 会在打开时自动迁移。

### 字体

全应用文字（书架、设置、侧栏、阅读正文、编辑器等）统一使用「设置 → 字体」所选字体（`ReadingFont`），字体文件内置于 `assets/fonts/`（来源与授权见 [assets/fonts/LICENSES.md](./assets/fonts/LICENSES.md)）：

| 选项 | 字体 |
|------|------|
| 思源黑体 | Noto Sans CJK SC |
| 鸿蒙黑体 | HarmonyOS Sans SC |
| 霞鹜975圆体 | LXGW 975 Yuan SC |
| 寒蝉全圆体（默认） | Chill Round F |
| 阿里妈妈方圆体 | Alimama FangYuanTi VF（可变字体，字重自动映射 `wght` 轴） |

缺字时回退：`Microsoft YaHei` / `PingFang SC` / `Noto Sans CJK SC` / `sans-serif`。

## 阅读背景

「设置 → 阅读背景」：纯色、宣纸（梅）、竹影、海波、星河、樱落（默认宣纸）。每种背景各有淡色 / 暗色两张 1024px 无缝平铺图（`assets/backgrounds/{name}_{light|dark}.jpg`，以 2 倍缩放显示），由脚本生成：

```bash
swift tool/gen_backgrounds.swift
```

## 图标

源图：`assets/icon/app_icon.png`。生成平台图标：

```bash
dart run flutter_launcher_icons
```

## 发布流程

### Android（APK / App Bundle）

1. 配置签名：在 `android/key.properties` 中写入 keystore（勿提交仓库）。
2. 构建：

```bash
flutter build apk --release
# 或上架 Play / 国内市场：
flutter build appbundle --release
```

产物：

- APK：`build/app/outputs/flutter-apk/app-release.apk`
- AAB：`build/app/outputs/bundle/release/app-release.aab`

应用名：**私人阅读**；applicationId：`com.ownread.ownread`。

### macOS

```bash
flutter build macos --release
```

产物在 `build/macos/Build/Products/Release/`。可用 Xcode Organizer 公证 / 打包 DMG（按需自行配置 Developer ID）。

## 隐私蒙版（`.env`）

项目根目录 `.env`（已加入 assets）：

```env
PRIVACY_IDLE_SECONDS=60
PRIVACY_UNLOCK_HOLD_SECONDS=3
```

- `PRIVACY_IDLE_SECONDS`：无操作多久后显示空白蒙版（秒）
- `PRIVACY_UNLOCK_HOLD_SECONDS`：长按蒙版中央的空盒图案多久解除蒙版（秒）；长按其他位置无效
- 「设置 → 自动锁屏」可关闭此功能（默认开启）；关闭后既不闲置锁屏，也不在切到后台时遮盖

修改后需**完全重启**应用（热重载不会重新加载 `.env`）。可参考 `.env.example`。

## 性能与稳定性约定

- 不联网；不引入数据库依赖
- 按章读写 `chapters/NNNN.txt`，编辑保存只写当前章
- 阅读窗口仅保留少量章节缓存，滚动时淘汰远处章节
- 全文替换优先处理当前阅读章节，其余章节后台逐章替换并让出事件循环
- 旧版 `book.txt` 在打开时自动切成章节文件后删除

## 测试

```bash
flutter test --coverage
```

主要覆盖：

- `ChapterSplitter` 分章与字节连续
- `TextReplace` 查找替换与 diff 采样
- `NovelRepository` 导入 / 导出 / 替换 / 章节编辑 / 历史 / 删除
- `LibraryController` 搜索排序
- Widget：书架空态与列表

## License

Private — part of styles.guide workspace.

## 图库

书架右上角的图库按钮进入集中图库。「导入图片」支持 JPG、PNG、GIF、WebP、BMP；「存入视频」支持 MP4、MOV、M4V、WebM（实际可播放编码取决于设备）。可一次选择多个文件，原始文件会复制到 `{ApplicationSupport}/ownread/gallery/{id}/{filename}`，无需网络或原文件继续存在。

右上角「更多」可将全部图片导出为 ZIP，或从 ZIP 追加图片 / 替换全部图片；ZIP 中的视频和其他文件不会导入，替换图片不影响已有视频。导入先解压并校验，再更新图库，失败时保留原图片。图片菜单也可逐张导出，视频仅在应用内保存与播放，不提供导出。点击图片可缩放；点击视频卡片进入播放器。切到后台或隐私蒙版锁定时暂停视频。删除前需确认。图库独立于小说 ZIP 备份，书籍的导入 / 导出不包含或清空图库。

图库查看器支持触屏左右滑动和 macOS 鼠标左右拖动，按当前筛选顺序切换图片 / 视频；图片放大后拖动用于平移，标题旁实时显示缩放百分比，点击百分比恢复 100% 并继续切换；单击 / 轻点图片返回图库列表。
