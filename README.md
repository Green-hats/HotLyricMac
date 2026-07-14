# 热词 Mac（HotLyricMac）

这是 [cnbluefire/HotLyric](https://github.com/cnbluefire/HotLyric) 的原生 macOS 实验移植版。Windows 原版依赖 WinUI 3、SMTC 和 Win32 API，因此 Mac 版使用 Swift、SwiftUI 和 AppKit 重写系统集成层。

> 本项目使用 [OpenAI Codex](https://openai.com/codex/) 辅助完成。

## 当前功能

- 自动读取 Apple Music 与 Spotify 当前曲目、播放状态和进度
- 与原版一致，按配置优先使用网易云、失败后回退 QQ 音乐
- 基于歌名/歌手相似度匹配，以版本化单文件原子缓存歌词、翻译和真实匹配信息
- 缓存按最近访问时间维护：默认保留 90 天，最多 2,000 首或 100 MB，并在设置页显示占用与提供手动清理
- 纯音乐标记过滤，以及“翻译优先/下一行/隐藏”第二行策略
- 始终置顶、跨桌面与全屏空间显示的透明歌词窗口
- 原版八组主题、逐行卡拉 OK 进度、字号和时间偏移设置
- 自定义原文、高亮、描边、背景和边框颜色
- 使用任意已安装字体，并选择常规到粗体四档字重
- 使用 Core Animation 图层遮罩推进歌词进度；优先使用网易云 YRC 逐字时间轴，并兼容解析 QRC，普通 LRC 自动回退逐行动画
- 歌词窗口拖动、锁定和鼠标穿透
- 当前播放器会话粘性选择；暂停后不会跳回优先播放器
- 自动或手动锁定 Apple Music/Spotify，并显示自动化权限错误
- Spotify/Apple Music 时间单位归一化，seek、暂停和恢复时重建动画时钟
- 歌词窗口高度与字号双向联动，窗口宽度独立控制可用行宽
- 网易云与 QQ 音乐手动搜索、选择结果并缓存歌曲映射
- 为当前歌曲导入本地 LRC，并保留歌词真实来源
- 超长歌词保持字号并随播放进度横向滚动
- 使用 SMAppService 管理登录时启动
- 显示器拔插、分辨率变化和睡眠唤醒时自动修复窗口位置
- 播放、暂停、无播放器及低电量模式下自适应调整轮询频率；当前播放器高频刷新，另一个播放器每 5 秒低频探测
- Carbon 系统级快捷键：播放控制、锁定及歌词窗口显隐
- 菜单栏手动显隐歌词，或在无播放器时自动隐藏
- 无有效歌词行时显示歌名、歌手、专辑、播放器和加载状态
- 设置页将当前歌曲统一显示为“歌名 - 歌手”，歌词来源按“匹配歌名 / 匹配歌手 · 平台”展示
- 菜单栏展示播放进度、播放状态及歌词来源
- 菜单栏播放/暂停、上一首、下一首、重新匹配和解锁
- Apple Silicon 与 Intel 通用构建；最低支持 macOS 13

## 构建

需要 Xcode Command Line Tools 和 Swift 6：

```bash
git clone https://github.com/Green-hats/HotLyricMac.git
cd HotLyricMac
swift test
./scripts/build-app.sh
open dist/HotLyric.app
```

首次读取播放器时，macOS 会请求“自动化”权限，请允许热词控制 Music 或 Spotify。若误拒绝，可在“系统设置 → 隐私与安全性 → 自动化”中重新启用。

## 已知限制

- HyPlayer、LyricEase 和 Windows SMTC 播放器没有 macOS 版本或等价接口，因此未移植。
- 当前安装包为本地 ad-hoc 签名，尚未使用 Apple Developer ID 公证；分发前需用开发者证书重新签名并 notarize。
- 歌词匹配依赖网易云音乐、QQ 音乐接口和网络可用性。

原项目与本移植代码均遵循仓库根目录的 MIT License。
