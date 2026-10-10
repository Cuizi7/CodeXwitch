# CodeXwitch 图标定稿

正六边形边长/外接圆半径 300，相切圆角半径 **160**，整体逆时针旋转 15°。
箭头从已批准的生成稿轮廓描摹并拟合成平滑曲线，保留原图的倾斜、交叉留白及头尾形状。
App 和运行态菜单图标共用同一箭头路径。

- `app-icon-final.svg`：App 图标矢量源；`../AppIcon.icns` 包含 16–1024 像素表示。
- `menu-*-final.svg`：运行中、未运行、处理中、异常四种单色状态。
- `menu-processing-frame.svg` / `menu-processing-spinner.svg`：处理态分层，内圈旋转而外框固定。
- `regular-rounded-hex-frame-r160.svg` / `switch-arrows-reference.svg`：独立几何及箭头基准。

菜单资源以透明矢量 PDF 保存到 `Sources/CodeXwitchKit/Resources/Icons`，由 AppKit
作为 20 pt 模板图像加载，颜色随系统外观变化。启用系统“减少动态效果”时使用静态处理态。
PNG/PDF/ICNS 均直接从 SVG 导出，运行和正常构建不需要外部图形工具。

如需重新生成资源，可使用 `rsvg-convert -f pdf` 转换菜单 SVG，使用 `rsvg-convert -w … -h …`
导出 Apple 标准 iconset 中的各尺寸 PNG，再运行 `iconutil -c icns`。
