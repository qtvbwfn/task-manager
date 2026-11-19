# TaskManager · macOS 任务管理器

原生 Swift + AppKit 的 macOS 任务管理器，零第三方依赖：系统概要 / 性能 / 进程 / 系统信息 / 登录项 / 用户 / 服务，深浅双主题，资源占用低。

## 构建

需要 macOS 15+ 与 Xcode Command Line Tools：

```bash
./make_app.sh   # swift build -c release + 组装 任务管理器.app（含图标、ad-hoc 签名）
```

或仅编译：`swift build -c release`。

## 目录结构

```
Sources/App/       应用外壳：窗口、侧边栏、设置、菜单栏
Sources/Panels/    功能面板（系统概要 / 性能 / 进程 / …）
Sources/Panels/Views/  自绘图表组件
Sources/Models/    快照数据模型
Sources/Sampler/   系统采样（sysctl / proc / SMC / IOKit）
Resources/         图标等资源
```
