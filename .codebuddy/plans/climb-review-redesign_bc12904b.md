---
name: climb-review-redesign
overview: 全面重构攀岩复盘应用的 UI：实现覆盖层视频库、鼠标悬停自动显示播放器控制项，并采用精致简约的“高山风”视觉设计。
design:
  styleKeywords:
    - Minimalist
    - Warm Tones
    - Floating UI
    - Hover Interaction
  fontSystem:
    fontFamily: SF Pro
    heading:
      size: 18px
      weight: 600
    subheading:
      size: 14px
      weight: 500
    body:
      size: 13px
      weight: 400
  colorSystem:
    primary:
      - "#4A7C59"
      - "#3A6247"
    background:
      - "#F2EDE6"
      - "#FFFFFF"
    text:
      - "#2A2420"
      - "#7A7268"
    functional:
      - "#C85A1A"
todos:
  - id: setup-theme
    content: 创建 Theme.swift 定义 Alpine Minimal 配色与通用样式扩展
    status: completed
  - id: refactor-navigation
    content: 使用 [skill:frontend-design] 在 ContentView 实现 ZStack 覆盖层视频库导航
    status: completed
    dependencies:
      - setup-theme
  - id: hover-logic-panel
    content: 在 VideoPlayerPanel 实现鼠标进入显示标题栏的交互与动画逻辑
    status: completed
    dependencies:
      - setup-theme
  - id: iconize-buttons
    content: 将应用内所有文字按钮替换为 SF Symbols 图标并优化布局
    status: completed
    dependencies:
      - hover-logic-panel
  - id: beautify-library
    content: 重构 LibraryView 卡片样式，应用暖色调背景与阴影效果
    status: completed
    dependencies:
      - refactor-navigation
  - id: polish-controls
    content: 精修进度条、滑块等控制组件的视觉细节，确保风格统一
    status: completed
    dependencies:
      - iconize-buttons
---

## 产品概述

重构攀岩复盘应用的 UI 架构与视觉表现，提升操作专注度与现代美感。

## 核心功能需求

- **导航重构**：将视频库从全屏切换模式改为“覆盖层（Overlay）”弹出模式，背景保持播放器可见，实现无缝切换。
- **纯净播放态**：默认隐藏视频面板的标题栏（包含视频名、打开/打点按钮），仅在鼠标悬停在视频区域时动态显示，以减少视觉干扰。
- **视觉去字化**：全面减少文字按钮，改用直观的 SF Symbols 图标。
- **Alpine Minimal 风格**：采用暖米白背景、鼠尾草绿强调色、圆角矩形与精致阴影的简约美学设计。

## 技术方案

- **导航层级**：在 `ContentView` 中使用 `ZStack` 实现。底层为双视频播放器，顶层为带模糊背景（Material）的视频库抽屉。
- **悬停交互**：在 `VideoPlayerPanel` 中通过 `@State private var isHovering` 配合 `.onHover` 闭包监听鼠标状态，使用 `withAnimation` 控制标题栏的 `opacity` 和 `offset`。
- **图标化更新**：使用 SwiftUI 原生 `Image(systemName:)` 替换 `Button` 中的 `Text`。
- **配色系统**：定义全局 `Color` 扩展，适配“Alpine Minimal”浅色系。

## 目录结构

```
ClimbReview/
├── ClimbReview/
│   ├── ContentView.swift        # [MODIFY] 修改导航逻辑，实现 ZStack 覆盖层效果
│   ├── VideoPlayerPanel.swift   # [MODIFY] 实现 Hover 隐藏/显示逻辑，更新为图标按钮
│   ├── LibraryView.swift        # [MODIFY] 更新视觉样式，应用浅色系与圆角卡片
│   └── Theme.swift              # [NEW] 定义 Alpine Minimal 配色与统一圆角样式
```

## 设计风格：Alpine Minimal (高山简约)

致力于营造一种宁静、专业且专注于内容分析的氛围。

### 关键设计细节

1. **容器**：使用 `#F2EDE6` (暖米白) 作为主背景，面板使用白色背景配合微弱的投影 (`radius: 12, y: 4`)。
2. **强调色**：使用 `#4A7C59` (鼠尾草绿) 用于主操作和进度条。
3. **交互**：标题栏在 Hover 时从顶部轻微滑入，透明度从 0 渐变到 1。
4. **字体**：标题使用 Semibold 字重，时间戳使用 Monospaced 字体以防抖动。

## 代理扩展

### Skill

- **frontend-design**
- 目的：辅助生成高质量的 SwiftUI 视图修饰符与动画参数，确保“Alpine Minimal”视觉风格的精致度。
- 预期结果：获得具有现代美感的圆角、阴影与过渡动画代码。