# OwnRead / 私人阅读

跨平台（**Android**、**macOS**）离线 TXT 小说阅读器。不联网、不使用数据库，全部数据保存在本地文件仓库。

## 功能概览

- TXT 导入并自动分章（UTF-8 / GBK / GB18030）；全文导出
- 设置中「导出所有 / 导入所有」：ZIP 备份整库（含进度与修改历史）；导入会先清空现有书籍
- 书架：排序、查找、删除（确认）、改名；显示章节数、总字数、阅读进度条、修改字数
- 点击进入阅读并跳转上次阅读位置
- 无限滚动阅读，预加载上一章 / 下一章
- 单击呼出侧栏（返回 / 查找替换 / 章节列表）；书架右上角「设置」可调淡色·暗色 / 字号 / 行距
- 双击进入就地编辑，右下角「保存」写回本地文件
- 查找替换与章节编辑均写入修改历史

详细产品说明见 [product.md](./product.md)。

## 环境要求

- Flutter **3.41+**（Dart **3.11+**）
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

阅读正文字体固定为 **微软雅黑**（`Microsoft YaHei`），并设置平台回退：`PingFang SC` / `Noto Sans CJK SC` / `sans-serif`。未安装雅黑的系统会使用回退字体。

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
- `PRIVACY_UNLOCK_HOLD_SECONDS`：长按多久解除蒙版（秒）

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
