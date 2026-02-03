# 0.2.3

* 添加了流速调节的功能。
* 修复了开启粉色星星时，Slide 路径也被绘制为粉色的问题。
* 修复了正解音无法正确播放的问题。
* 调整了 Approach Arc 的绘制。

## 0.2.2

* 修复了在 Android 平台上的崩溃问题。
* 完善了渲染机制以便绘制 Approach Arc。

## 0.2.1

* 修复了 Slide 星星在路径上移动时朝向错误的问题。
* 修复了进入全屏后无法正常退出的问题。

## 0.2.0

* **新功能**: 增加「锁屏」功能，全屏模式下支持锁定 UI 以防止误触。
* **UI 适配**: `SimaiPlayerPage` 现在全面支持 `SafeArea` 安全区域适配，包括横屏刘海屏及底部导航栏。
* **生命周期管理**: 为 `SimaiPlayerController` 和 `SimaiPlayerPage` 添加了完善的 `dispose` 资源销毁逻辑。
* **交互改进**: 将正解音开关移至设置抽屉并默认关闭，简化了主控制条的视觉显示。
* **稳定性**: 修复了页面销毁时计时器未正确清理的潜在内存泄漏问题。

## 0.1.0

* Initial release of `simai_flutter`.
* Support for parsing simai chart strings and `.txt` files.
* Built-in Flame-based chart renderer.
* Precise audio synchronization with `audioplayers`.
* Basic UI components for chart preview and control.
