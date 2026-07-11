# LeftIO macOS 输入法踩坑复盘

> 这是按时间记录的调试复盘，早期章节可能包含已废弃的路径或实验命令。
> 当前操作流程以 `docs/leftio-input-method-lifecycle.md` 为准。

记录范围：从安装生命周期被理顺为“用户级安装 + TIS 注册 + 手动添加 + relogin”开始，一直到 `R` 键删除问题被追到 IMK 分发不稳定、并临时加上只拦 `R` 的事件 tap 为止。

这份文档不是设计宣传稿，而是给后续维护用的事故记录：哪些路走错了、为什么错、证据是什么、以后应该怎么判断。

## 1. 安装生命周期先回到成熟输入法路线

一开始的问题不是键位，而是安装流本身不健康。成熟 macOS 输入法基本不应该反复直接改 `com.apple.HIToolbox`、`com.apple.inputsources`，也不应该安装后强行切当前输入法。

后续安装生命周期被理顺为：

- 开发阶段默认安装到 `~/Library/Input Methods/LeftIO.app`。
- 安装脚本只做 copy、去 quarantine/provenance、LaunchServices 注册、TIS 注册/启用。
- 不写 `com.apple.HIToolbox`。
- 不写 `com.apple.inputsources`。
- 不调用 `TISSelectInputSource` 强切当前输入法。
- 首次安装或输入源列表异常时，明确要求 logout/login。
- 系统级 `/Library/Input Methods` 保留为显式 release-style 路径。

对应文件：

- `scripts/install_input_method_app.sh`
- `scripts/install_input_method_app_system.sh`
- `scripts/uninstall_input_method_app.sh`
- `scripts/verify_input_method_install.sh`
- `Sources/LeftIOInputMethod/LeftIOInputMethodApp.swift`
- `Sources/LeftIOLauncher/LeftIOLauncher.swift`
- `docs/leftio-input-method-lifecycle.md`

关键教训：

- 不要把“让当前会话立刻变成可用”作为安装脚本目标。
- macOS 输入法缓存非常重，relogin 是正常生命周期的一部分，不是失败。
- 验证安装时可以报告当前输入源，但不应要求当前输入源必须已经是 LeftIO。

## 2. 微信输入法重复条目问题

用户的系统设置和菜单栏曾出现大量重复的微信输入法条目。这个问题的背景是之前有脚本或 AI 直接污染了系统输入源偏好。

踩坑：

- 不能继续通过写 Apple 输入源 plist 来“修复”输入法状态。
- 直接改 `AppleEnabledInputSources` 很容易制造重复、半残留、设置面板和菜单栏不同步。
- `TISCopyCurrentKeyboardInputSource` 在某些时刻不能作为唯一证据否定用户菜单栏截图，因为系统 UI 和 TIS 查询可能存在缓存/会话差异。

后续规则：

- 清残留时只做可控的 TIS disable、删除 LeftIO 自己的 bundle 和日志/注册残留。
- 不误伤其他输入法，尤其不主动删除微信输入法。
- 遇到输入源列表异常，优先让用户 relogin，而不是继续在脏会话中硬改偏好。

## 3. LeftIO 残留清理和安装边界

清理 LeftIO 残留时的边界是：

- 用户级默认只处理 `~/Library/Input Methods/LeftIO.app`。
- 只有显式 `LEFTIO_UNINSTALL_SYSTEM=1` 才处理 `/Library/Input Methods/LeftIO.app`。
- 只 kill LeftIO 相关进程，不杀其他输入法。
- 日志和注册 helper 只作为诊断辅助，不作为系统偏好写入工具。

踩坑：

- 早期验证脚本把 `HIToolbox`/当前输入法状态当验收依据，这是错误方向。
- 后来改为：检查 bundle、Info.plist、签名、xattr、TIS 可见性。

## 4. Space 层和初始数字层混乱

用户测试时出现“没按住 Space 也变数字”的现象。这里的核心不是安装，而是 Space chord 状态泄漏。

修复方向：

- 如果物理 Space 已经没有按下，但内部仍以为 Space pending，就清掉 pending Space。
- 后续普通键按正常拼音/T9 层处理，不再被错误当成数字层。

教训：

- Space 这种长按层必须依赖真实按键状态校正，不能只信内部状态机。
- 对 chord 层要有边界测试，尤其是 Space down/up 丢事件或切应用后的状态。

## 5. 候选窗方向、数量和候选质量

用户要求候选窗应该是横向 4 个，正好用 `1 2 3 4` 选词。

踩坑：

- 不能用“假补齐”凑满 4 个候选。候选不够说明词库/编码/Rime 数据接入有问题，不应该展示假候选。
- 单列候选窗和用户设计目标不一致。
- 候选消失要区分是 UI 没刷新、Rime 没候选、还是输入被错误提交。

后续改动方向：

- 使用 `kIMKSingleRowSteppingCandidatePanel`。
- 设置 selection keys 为 `1/2/3/4` 对应的 keyCode。
- Rime 词库接入后，`大家好` 这类常用短语应通过真实词库排序出现。
- 词典生成脚本接入 `essay.txt` 权重，避免“联想能力太差”。

验证过的关键目标：

- `32'542'426` 应优先出现 `大家好`。
- 候选不是靠 UI 假补齐，而是来自真实 Rime/词库数据。

## 6. Shift 中英文切换

用户要求像微信输入法一样，单击 Shift 切换中/EN，并在光标处显示当前状态。

踩坑：

- 不能简单把 Rime 的 `ascii_mode` 打开后就认为是英文模式，因为这会破坏 LeftIO 自己的九宫格主区逻辑。
- “EN 能显示，但不能真正切回中”说明 UI indicator 和内部输入状态可能不同步。

当前实现方向：

- LeftIO 维护本地 `localAsciiMode`。
- 单击 Shift 通过 `flagsChanged` 检测 down/up 完成切换。
- 切到 EN 时，主区按普通字符输出；`F/G/R` 保留 LeftIO 特殊逻辑。
- 切回中时，Rime `ascii_mode` 保持 false，让中文引擎继续接管。
- 用 `ModeIndicatorController` 在光标附近短暂显示 `EN` 或 `中`。

教训：

- UI 显示、Rime 状态、LeftIO 本地模式必须分开看。
- 不能只看一个 indicator 就断言模式正确。

## 7. F/G 在无候选时的符号回退

用户要求：

- 有候选窗时，`F/G` 是上一页/下一页。
- 没候选窗时，`F/G` 应承担传统键位符号。
- `F` 普通是 `-`，Shift+F 中文下是 `——`，英文下是 `_`。
- `G` 普通是 `=`，Shift+G 是 `+`，中英文一致。

踩坑：

- 一开始只看 `NSEvent.modifierFlags`，导致普通 `f/g` 也被误判成 Shift。
- 需要同时比较 `characters` 和 `charactersIgnoringModifiers`，否则输入法/键盘布局层可能让 modifier flags 看起来像 Shift，但字符本身没有变化。

后续规则：

- `F/G` 的 Shift 判断不能只信 flags。
- 普通 `f/g` 必须能输出普通符号。
- 有候选时才翻页，无候选时不应该吞键后无输出。

## 8. R 键删除问题：第一层误判

用户反复指出：没有候选窗时，按 `R` 应该删除，而不是输出字母 `r`。

早期错误判断：

- 曾经根据 `TISCopyCurrentKeyboardInputSource` 或日志缺失，判断用户可能没切到 LeftIO。
- 用户截图显示菜单栏就是 LeftIO，这个判断不可靠。

教训：

- 不能用单一 TIS 查询否定用户截图。
- 输入法问题必须同时看：菜单栏状态、LeftIO 进程路径、LeftIO 日志、实际按键事件。

## 9. R 键删除问题：IMK 分发路径不稳定

后来日志出现几种不同状态：

### 9.1 R 完全没有进入 LeftIO

某些轮次中，`W/S/A/Space/1` 都进入了 LeftIO 日志，但一长串 `r` 没有任何 `key=R` 记录。

说明：

- LeftIO 进程确实在跑。
- 其他键确实能进 controller。
- 空闲文本态的 `r` 可能被 macOS/IMK 直接当普通文本提交，没有送进现有 handler。

尝试过：

- 增加 `inputText(_:client:)`。
- 增加 `inputText(_:key:modifiers:client:)`。
- 增加 `didCommand(by:client:)`。
- 对照 InputMethodKit 头文件确认三种输入路径。

结果：

- 某些键进入了 `inputTextKey`。
- 但 `r` 仍然有时完全不进。

教训：

- IMK 的 key 分发不是“实现一个 handler 就万事大吉”。
- 空闲态普通拉丁字母可能走系统直接提交路径。

### 9.2 R 进入了 LeftIO，但删除没落到客户端

后面某一轮日志显示：

```text
inputTextKey keyCode=15 chars=r charsIgnoring=r key=R ... actions=[deleteBackward] consumed=true
```

但没有：

```text
sendCommand selector=deleteBackward:
```

说明：

- 状态机已经把 `R` 判成 `.deleteBackward`。
- 但动作进入 Rime/session 后被消费，没有真正发到当前文本客户端。

修复方向：

- 当没有 marked text、没有组成态时，`R` 不再交给 Rime/session。
- 在 `LeftIOInputController` 层直接执行客户端 `deleteBackward`。
- 日志标记为 `directClientDelete`。

教训：

- “状态机 actions 对了”不等于用户可见行为对了。
- 客户端动作必须在 controller 层确认已经发出。

### 9.3 去掉 inputText 后仍然收不到 R

为了逼近 Squirrel 的 raw key event 模式，曾去掉 `inputText` / `didCommand` 覆写，只保留：

```swift
override func handle(_ event: NSEvent!, client sender: Any!) -> Bool
```

并确认 Swift 里的 `handle(_:client:)` 对应 ObjC `handleEvent:client:`。

结果：

- 回车等事件能进 `handle`。
- 空闲态大量 `r` 仍然不进。

教训：

- raw `handle` 路线也不能保证空闲态普通字母一定进 IMK controller。
- 不能再假设这是状态机或 Rime 的单点 bug。

## 10. Info.plist 和成熟输入法对照

对照 Squirrel/Rime 后发现 LeftIO 的 mode 声明曾不够标准。

调整过：

- mode 级增加 `tsInputModeCharacterRepertoireKey = Hans/Hant`。
- `tsInputModeScriptKey` 改为 `smUnicodeScript`。
- 顶层 `tsInputMethodCharacterRepertoireKey` 去掉 `Latn`。

原因：

- `Latn` 对中文输入法可能让系统更倾向于把普通拉丁字母直接提交。
- Squirrel 的 mode 级声明更接近成熟 IMK 输入法实践。

结果：

- 这一步改善了部分事件进入情况，但没有彻底解决空闲态 `r` 绕过 IMK 的问题。

教训：

- Info.plist 不是展示信息而已，它影响 Text Input Source 的分发和系统理解。
- 但 plist 修正不能替代运行时事件验证。

## 11. overrideKeyboard 的作用和局限

对照 Squirrel 后，LeftIO 在 `activateServer` 中增加：

```swift
client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
```

目的：

- 输入法激活时强制使用 ABC 键盘布局。
- 避免当前系统键盘布局先解释普通字母。

结果：

- 日志能看到 `activate overrideKeyboard=com.apple.keylayout.ABC`。
- 但空闲态 `r` 仍然有时绕过 LeftIO。

教训：

- `overrideKeyboard` 是成熟输入法应做的基础动作。
- 但它不是事件捕获保证。

## 12. 当前最后一层补丁：只拦 R 的事件 tap

截至当前最后一次安装，加入了 `RKeyEventTap`。

设计边界：

- 只在 LeftIO 激活时启用。
- 只监听 `keyDown`。
- 只拦物理 `kVK_ANSI_R`。
- 不拦 `Command/Option/Control + R`。
- 拦到后吞掉原始 `r`，然后回主线程执行 LeftIO 的删除逻辑。
- deactive/close 时关闭 tap。

日志预期：

```text
eventTapR enabled
eventTapR directClientDelete
```

如果 macOS 拒绝：

```text
eventTapR create failed
```

可能原因：

- 需要辅助功能权限。
- 需要输入监控权限。
- hardened runtime/signing 对 session event tap 有额外限制。

当前状态：

- 已编译通过。
- `swift test --disable-swift-testing` 通过，69 tests, 0 failures。
- 已安装到 `~/Library/Input Methods/LeftIO.app`。
- 但截至写本文档时，事件 tap 版本还没有完成用户侧复测确认。

教训：

- 事件 tap 是补 IMK 分发洞的硬手段，不应该一开始就用。
- 如果使用，必须严格限域，避免变成全局键盘劫持。
- 需要清楚记录权限失败路径。

## 13. 日志判断规则

以后排查输入问题，先看日志而不是猜。

逐键日志可能包含输入内容，当前版本默认关闭。只有在明确的短期调试窗口内才启用，并在重启 LeftIO 后复现：

```sh
defaults write io.github.cstcat.inputmethod.leftio LeftIOEnableInputEventLogging -bool true
```

调试完成后立即关闭并重新启动 LeftIO：

```sh
defaults delete io.github.cstcat.inputmethod.leftio LeftIOEnableInputEventLogging
```

日志路径：

```text
~/Library/Application Support/LeftIO/LeftIO.input.log
~/Library/Application Support/LeftIO/LeftIO.server.log
~/Library/Application Support/LeftIO/LeftIO.launch.log
```

常见判断：

```text
activate overrideKeyboard=com.apple.keylayout.ABC
```

说明 LeftIO 被激活，且尝试 override keyboard。

```text
handle ... key=R ...
```

说明 raw event 进了 `handle`。

```text
inputTextKey ... key=R ...
```

说明走了 IMK unpacked text path。

```text
directClientDelete
sendCommand selector=deleteBackward:
```

说明 controller 层直接向客户端发删除。

```text
eventTapR enabled
eventTapR directClientDelete
```

说明事件 tap 拦到了物理 R，并走了硬删除路径。

如果用户实际输出了 `r`，但日志没有任何 `R` 记录：

- 不要再说用户没切输入法。
- 先确认 LeftIO 进程路径和 activate 日志。
- 然后判断是 IMK 没派发，还是 event tap 没启用/权限失败。

## 14. 验证命令

常用命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-swift-testing
make install-input-method
pgrep -alf 'LeftIO|LeftIOInputMethod|LeftIOLauncher'
tail -n 300 "$HOME/Library/Application Support/LeftIO/LeftIO.input.log"
stat -f '%Sm %z %N' "$HOME/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO"
codesign -dv "$HOME/Library/Input Methods/LeftIO.app" 2>&1 | sed -n '1,40p'
```

安装后测试前应清日志：

```sh
mkdir -p "$HOME/Library/Application Support/LeftIO"
: > "$HOME/Library/Application Support/LeftIO/LeftIO.input.log"
```

但清日志不是修复手段，只是避免旧日志误导。

## 15. 之后不要再犯的判断错误

- 不要把“用户输出了 r”直接解释成“用户没切到 LeftIO”。
- 不要只看当前 TIS 查询结果否定菜单栏截图。
- 不要说状态机测过就等于客户端行为正确。
- 不要用假候选补满 UI。
- 不要继续写 `HIToolbox` 或 Apple 输入源偏好。
- 不要在当前脏输入法会话里无限重装后期待系统缓存自然变干净。
- 不要把候选窗、Rime 状态、marked text、客户端文本框行为混成一个问题。
- 不要忽略 macOS 输入法的多路径分发：`handle`、`inputTextKey`、direct commit、event tap 可能同时存在。

## 16. 当前未完全收口的点

截至本文：

- 生命周期已经收口到成熟输入法安装路线。
- 候选窗方向、4 个候选、Rime 词库增强、Shift indicator、F/G 符号逻辑都已有实现方向和测试基础。
- `R` 的问题已经拆成两个独立层面：
  - 进 controller 但删除没落客户端：用 controller 级 `directClientDelete` 修。
  - 空闲态不进 controller：用激活期 `RKeyEventTap` 补洞。

仍需用户侧最终验证：

- `eventTapR enabled` 是否出现。
- 按 `R` 是否出现 `eventTapR directClientDelete`。
- 实际文本框里是否不再追加 `r`，而是删除前一个字符。
- 如果 tap 创建失败，需要进入系统设置给 LeftIO 辅助功能/输入监控权限，或重新设计非 tap 的输入法分发路径。

## 17. 辅助功能权限后的新增踩坑

用户后来明确给了 LeftIO 辅助功能权限，但 `R` 仍然没有触发删除。最新日志显示了一个新的分层问题：

```text
eventTapR create failed
eventTapR enabled
```

这说明：

- 权限之前，CGEvent tap 创建失败。
- 权限之后，tap 确实可以创建成功。
- 但创建成功不等于一定能在后续输入时生效。

关键新坑：

- 给权限后，macOS 可能重启 LeftIO 输入法进程。
- 旧进程里已经启用的 tap 会随进程退出消失。
- 新进程如果没有重新走 `activateServer`，基于 controller activation 的 tap 不会重新绑定。
- 所以 tap 不能只依赖 `activateServer`；输入法进程启动后也必须启用 process-wide tap。

后续修正方向：

- 将 `RKeyEventTap` 从 private 改为可由 input method app 启动路径调用。
- 在 `LeftIOInputMethodApp.startInputMethodServer()` 创建 `IMKServer` 后调用 `RKeyEventTap.activateProcessWide()`。
- controller activate 时仍然调用 `RKeyEventTap.activate(controller:)`，用于绑定 active controller。
- 如果 tap 回调时没有 active controller，但当前 TIS 输入源确实是 LeftIO，则把物理 `R` 改写成 Delete key event，至少避免继续输出字母 `r`。

这个版本的预期日志：

```text
eventTapR enabled
eventTapR remapToDelete activeController=false
```

或在 controller 已激活时：

```text
eventTapR directClientDelete
```

重要判断：

- 如果看到 `eventTapR create failed`，还是权限/签名/系统策略问题。
- 如果看到 `eventTapR enabled` 但没有任何 `eventTapR remapToDelete`，说明 tap 没收到 `R`，需要继续查 event tap 类型、位置、当前输入源判断。
- 如果看到 `eventTapR remapToDelete` 但文本仍输出 `r`，说明改写 event keycode 不足，需要改成吞掉 `R` 并主动 post Delete。
- 如果看到 `eventTapR directClientDelete` 但文本仍输出 `r`，说明 `sendCommand/deleteBackward` 对当前 client 不生效，需要 fallback 到 synthetic delete key event。

截至本次记录，最新安装包：

```text
/Users/cat/Library/Input Methods/LeftIO.app
Signed Time=Jul 4, 2026 at 12:20:57
```

测试状态：

```text
swift test --disable-swift-testing
69 tests, 0 failures
```

最后动作：

- 已杀掉旧 LeftIO 进程。
- 已清空 `~/Library/Application Support/LeftIO/LeftIO.input.log`。
- 等待用户切回 LeftIO 后复测。

## 18. R 键双路径、组合态删除、Shift 指示器新坑

用户后续验证确认：空闲态 `R` 删除开始生效，但又暴露了三个更细的 IMK/CGEvent tap 边界问题。

### 18.1 `R` 有时先输出 `r` 再触发删除

这不是 Rime 词库问题，而是输入事件走了两条路径：

- 物理 `R` 偶尔漏进 IMK `handle`，按普通字母/状态机路径处理。
- 随后 `RKeyEventTap` 或 fallback 又补了一次 Delete。
- 结果肉眼看到像“先打出 r，再删一下”，行为非常不可信。

修正原则：

- `R` 必须只有一条消费路径。
- 只要当前输入源是 LeftIO，物理 `R` 不能作为普通字母提交。
- 空闲态：直接对 client 发 `deleteBackward`。
- 组合态/有 marked text：必须交给 OneHand/Rime 删除组合串，不能发系统 Delete，否则会隐藏候选窗或打散 marked text。

代码侧修正：

- `shouldForceClientDelete` 增加 `!session.context.isComposing`，避免组合态误走 client delete。
- `RKeyEventTap` 的 active controller 从 weak 改成强引用绑定，避免 controller 还在处理键盘事件但 tap 回调里已经变 nil。
- controller 每次 `handle` / `flagsChanged` 都重新 bind 当前 controller。
- `deactivateServer` 不再销毁 process-wide event tap，只清 active controller；销毁 tap 会制造切换间隙，导致 `R` 漏进普通输入路径。
- tap 已确认当前输入源是 LeftIO 后，不再把 `R` keycode 改写成 Delete 后继续放行；改成吞掉 `R`。有 active controller 时走 controller，没 active controller 时主动 post synthetic Delete，避免出现“先输出 r 再删除”的双发。

### 18.2 组合态按 `R` 隐藏候选窗

用户观察：候选窗里已有拼音/候选时，按 `R` 不是删掉一个编码，而是候选窗直接消失。

原因：

- 组合态如果被 event tap fallback 改成物理 Delete，客户端会把它当系统退格处理。
- 对 IMK marked text 来说，这可能触发取消/清空候选窗，而不是更新 Rime raw input。

正确路径：

- `eventTapR routeToController`
- `handleEventTapRKeyDown`
- `oneHandController.handle(.r down)`
- Rime session `deleteBackward`
- `synchronizeClientState`
- 重新 `setMarkedText` 和更新候选窗。

日志判断：

```text
eventTapR routeToController
eventTapR routed key=R ... actions=[deleteBackward] consumed=true
```

如果看到：

```text
eventTapR syntheticDelete activeController=false
```

说明 controller 绑定又丢了，组合态仍有风险。

### 18.3 Shift 中/EN 指示器不能用 IMKCandidates

之前为了快速显示 `中` / `EN`，复用了 `IMKCandidates`。这会天然带候选编号，所以出现了荒谬的：

```text
1 EN
1 中
```

这是设计错误，不是样式问题。微信输入法式的中英文提示不是候选项，不能放进候选窗。

修正原则：

- 真候选窗继续使用 `IMKCandidates`，保留 1/2/3/4 选词。
- 模式提示必须是独立 overlay。
- 模式提示只显示 `中` 或 `EN`，不能有候选编号，不能占用候选选择逻辑。

代码侧修正：

- `ModeIndicatorController` 改成自绘 `NSPanel`。
- 不再调用 `IMKCandidates.setCandidateData([label])`。
- 显示时长缩短，避免快速切换时堆积。
- Shift toggle 加入轻量 debounce，减少快速点按时重复 flagsChanged 造成的卡顿/假状态。

### 18.4 当前验证状态

本次修正后已执行：

```text
swift test --disable-swift-testing
69 tests, 0 failures

make install-input-method
/Users/cat/Library/Input Methods/LeftIO.app

make verify-input-method
bundle=true
mode=true
selected=false
```

注意：

- `selected=false` 只说明验证时当前输入源不是 LeftIO，不代表安装失败。
- 切回 LeftIO 后会重新启动新进程；当前没有旧 LeftIO 进程。
- 如果复测仍有 `r` 输出，下一步要看新日志里是否出现 `eventTapR routeToController` 或 `eventTapR syntheticDelete activeController=false`。

### 18.5 `sendCommand(deleteBackward:)` 会杀掉 LeftIO

用户继续验证发现：`R` 仍会触发字母 `r`，甚至交替出现 `r` 和删除。

这次不能再猜键盘路径，必须看 crash report。`~/Library/Logs/DiagnosticReports/LeftIO-2026-07-04-2243*.ips` 明确显示 LeftIO 在 `R` 路径上崩溃：

```text
NSInvalidArgumentException
-[_IPMDServerClientWrapperLegacy deleteBackward:]: unrecognized selector sent to instance
LeftIOInputController.sendCommand(_:client:)
LeftIOInputController.handleEventTapRKeyDown()
```

真实原因：

- `handleEventTapRKeyDown` 空闲态会调用 `perform(.deleteBackward, client:)`。
- `sendCommand` 里如果 client 不是 `NSTextInputClient`，之前直接 `(sender as AnyObject).perform(deleteBackward:)`。
- 当前 macOS 给到的是 `_IPMDServerClientWrapperLegacy`，它不响应该 selector。
- 于是每按一次 `R`，LeftIO 可能直接崩溃。
- 输入法进程崩溃重启期间，系统会出现短暂未接管窗口，原始 `r` 就漏进文本框，于是看起来像“有时 r，有时删除，甚至交替”。

修正原则：

- 对 ObjC selector fallback 必须先 `responds(to:)`。
- 对不支持 `deleteBackward:` 的 wrapper，不要 `perform`，改用 synthetic Delete。
- 输入法进程不能因为一个删除 fallback 崩溃；崩溃比漏键更糟，因为会造成系统重启窗口和状态丢失。

修正后预期日志：

```text
sendCommand selector=deleteBackward: via=syntheticDelete
```

不应再出现新的 `LeftIO-*.ips` crash report。

### 18.6 不要把“选中 LeftIO 但没反应”归因给用户没切输入法

用户后续明确指出：已经从菜单栏切到 `LeftIO 单手九宫格` 后仍然没有反应，只是因为 LeftIO 没反应才切回微信输入法。

这类问题不能再用 `make verify-input-method` 里最后的：

```text
current com.tencent.inputmethod.wetype.pinyin 微信输入法
selected=false
```

去反推“用户没切到 LeftIO”。这个判断是错的，因为验证命令看到的是执行验证那一刻的当前输入源，不是用户刚才复现 bug 时的输入源。

真实证据链：

- `LeftIO` 进程存在。
- `LeftIO.input.log` 出现过：

```text
eventTapR syntheticDelete activeController=false
```

- 这说明 process-wide event tap 收到了 `R`，并且当时 `currentInputSourceIsLeftIO()` 判断为 true。
- 但同一时间没有：

```text
activateServer
controller init
handle keyCode=...
```

- 所以不是用户没切，而是系统菜单/TIS 层可能已经选中 LeftIO，但 `IMKInputController` 没有被创建或没有被激活。

这是一类独立的 IMK 生命周期故障：

- 输入源可见、已启用、selectCapable。
- 输入法 app 可启动，`IMKServer initialized=true`。
- 但文本输入 client 没接到 controller。
- process-wide tap 还能工作，反而会制造误导，让人以为 LeftIO 已经完整接管。

修正/诊断原则：

- 不要再用 `selected=false` 事后否定用户的复现过程。
- 不要再说“你没切输入法”；必须以日志判断 `activateServer` 和 `handle` 是否出现。
- 在没有 active controller 时，`RKeyEventTap` 不应继续吞键或 synthetic delete；否则会掩盖真正的 IMK controller 未连接问题。
- 已将无 active controller 的 `R` fallback 改为 pass-through，并写日志：

```text
eventTapR passThrough activeController=false
```

- 已增加 controller 生命周期日志：

```text
controller init
activateServer
deactivateServer
inputControllerWillClose
controller deinit
```

下一步排查口径：

- 如果切到 LeftIO 后有 `controller init` 但没有 `activateServer`：查 IMK server/controller 注册和 client 连接。
- 如果有 `activateServer` 但普通键没有 `handle`：查 `recognizedEvents`、client focus、keyboard override。
- 如果连 `controller init` 都没有，但 `IMKServer initialized=true`：查 Info.plist controller class、connection name、系统输入法会话缓存，必要时 relogin。
- 如果只有 `eventTapR passThrough activeController=false`：说明 tap 收到了系统级键，但 IMK controller 仍没接上，不能把它当成功能路径。

当前安装版本状态：

```text
swift test --disable-swift-testing
69 tests, 0 failures

/Users/cat/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO
mtime: Jul 5 00:07:32 2026
```

### 18.7 `selected=true` 仍然可能完全没反应

后续继续复现“切到 LeftIO 但按键没反应”时，出现了更明确的证据：

```text
TISSelectInputSource(...) -> 0
current io.github.cstcat.inputmethod.leftio.onehandt9 LeftIO 单手九宫格 ... selected=1
```

同时 `LeftIO.input.log` 只有：

```text
eventTap passThrough activeController=false keyCode=...
```

没有任何：

```text
controller init
activateServer
handle keyCode=...
```

结论：

- 菜单栏/TIS 的 `selected=1` 只能证明输入源选择层认为 LeftIO 是当前源。
- 它不能证明 `imklaunchagent` 已经拿到 endpoint。
- 它不能证明 `IMKServer` 已经给当前文本 client 创建了 `LeftIOInputController`。
- 它不能证明 `activateServer` 触发。
- 以后验收输入法“能用”必须看 controller 生命周期日志，而不是只看 TIS selected。

这也是为什么用户看到菜单栏已经是 LeftIO，但输入仍无反应：用户状态是真的，坏的是 IMK controller 没接管。

### 18.8 `TISDisableInputSource` 会制造更脏的 parent-disabled 状态

为了验证 parent source 是否影响启动，曾经对 LeftIO 的两个 source 都执行过：

```text
TISDisableInputSource(source) -> 0
TISEnableInputSource(source) -> 0
```

但结果不是恢复，而是进入更坏状态：

```text
io.github.cstcat.inputmethod.leftio | ... | TISTypeKeyboardInputMethodModeEnabled | LeftIO | enabled=0 | selectCapable=0 | selected=0
io.github.cstcat.inputmethod.leftio.onehandt9 | ... | TISTypeKeyboardInputMode | LeftIO 单手九宫格 | enabled=1 | selectCapable=1 | selected=0
```

随后：

```text
TISSelectInputSource(LeftIO mode) -> -50
```

重点：

- `TISEnableInputSource` 返回 `0` 不代表 source 的 `kTISPropertyInputSourceIsEnabled` 真的变成 `1`。
- parent `TISTypeKeyboardInputMethodModeEnabled` 如果是 `enabled=0`，即使 mode 是 `enabled=1/selectCapable=1`，也可能无法选择或无法启动 IMK。
- 卸载/重装、`TISRegisterInputSource`、`TISEnableInputSource` 都可能仍保留 parent disabled 的会话缓存。
- 这种状态下继续测输入逻辑没有意义，必须先恢复输入源生命周期。

因此 `scripts/verify_input_method_install.sh` 已改为同时检查：

```text
bundle=true
mode=true
bundleEnabled=true
modeEnabled=true
modeSelectCapable=true
```

只看到 `bundle=true/mode=true` 不再算通过。

### 18.9 `InputMethodConnectionName` 不要随便起短名

之前 LeftIO 使用：

```text
InputMethodConnectionName = LeftIO_Connection
```

这看起来能让 `IMKServer initialized=true`，但 macOS 的 IMK launch/endpoint 逻辑很可能更偏向 bundle-id 派生的连接名。成熟输入法常见模式是：

```text
$(CFBundleIdentifier)_Connection
```

因此构建脚本已改为：

```sh
CONNECTION_NAME="${APP_BUNDLE_ID}_Connection"
```

当前生成结果：

```text
InputMethodConnectionName = io.github.cstcat.inputmethod.leftio_Connection
```

注意：连接名修正后，如果系统里已经有 parent-disabled 或旧 endpoint 缓存，仍可能 `TISSelectInputSource -> -50`。这时不能把 `-50` 误判为连接名改坏了，必须先看 parent source 是否 `enabled=0`。

### 18.10 当前最小恢复口径

如果又进入“看得到 LeftIO，但无响应/无法选择”的状态，按下面顺序判断：

1. 运行 `make verify-input-method`。
2. 如果 `bundleEnabled=false`，不要继续测按键逻辑。
3. 先注销/重新登录，让 TIS/IMK 重建会话缓存。
4. 登录后在系统设置里移除 LeftIO，再重新添加 `LeftIO 单手九宫格`。
5. 再跑 `make verify-input-method`，必须看到 `bundleEnabled=true`、`modeEnabled=true`、`modeSelectCapable=true`。
6. 切到 LeftIO 后，再看 `LeftIO.input.log` 是否出现 `controller init` 和 `activateServer`。

禁止再做的事：

- 不要反复 `TISDisableInputSource`/`TISEnableInputSource` 当成“刷新”。
- 不要把 `TISSelectInputSource -> 0` 当成输入法可用证明。
- 不要在 parent disabled 时继续修 `R/F/G` 这类输入逻辑，那个层级根本没接上。

### 18.11 2026-07-05 parent-disabled 的实际恢复记录

用户注销/重新登录后再次运行：

```text
make verify-input-method
```

仍然失败：

```text
bundle=true
mode=true
bundleEnabled=false
modeEnabled=true
modeSelectCapable=true
selected=false
make: *** [verify-input-method] Error 3
```

当时真实偏好状态：

- `com.apple.HIToolbox.plist` 的 `AppleEnabledInputSources` 没有 LeftIO。
- `com.apple.inputsources.plist` 的 `AppleEnabledThirdPartyInputSources` 没有 LeftIO。
- `AppleSelectedInputSources` 已经没有 LeftIO，说明不是“当前选择残留”。
- `AppleInputSourceHistory` 里仍有 LeftIO mode，但这不是启用依据。

所以问题不是用户没注销，也不是当前输入法没切，而是 LeftIO parent source 没在启用集合里。

做过一次定点修复，修复前先备份：

```text
~/Library/Preferences/com.apple.HIToolbox.plist.leftio-bak-20260705-013925
~/Library/Preferences/com.apple.inputsources.plist.leftio-bak-20260705-013925
```

只追加 LeftIO 自己的条目，没有动 ABC、微信、简体拼音：

```text
AppleEnabledInputSources += {
  Bundle ID = io.github.cstcat.inputmethod.leftio;
  Input Mode = io.github.cstcat.inputmethod.leftio.onehandt9;
  InputSourceKind = Input Mode;
}

AppleEnabledInputSources += {
  Bundle ID = io.github.cstcat.inputmethod.leftio;
  InputSourceKind = Keyboard Input Method;
}

AppleEnabledThirdPartyInputSources += {
  Bundle ID = io.github.cstcat.inputmethod.leftio;
  InputSourceKind = Keyboard Input Method;
}
```

然后刷新：

```sh
pkill -x cfprefsd
pkill -x LeftIO
pkill -x imklaunchagent
pkill -x TextInputMenuAgent
pkill -x TextInputSwitcher
"$HOME/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO" --register-installed-input-source
make verify-input-method
```

修复后验证通过：

```text
bundle=true
mode=true
bundleEnabled=true
modeEnabled=true
modeSelectCapable=true
selected=false
verify_exit=0
```

随后 `TISSelectInputSource` 从 ABC 切到 LeftIO 返回 `0`：

```text
select com.apple.keylayout.ABC status 0
select io.github.cstcat.inputmethod.leftio.onehandt9 status 0
current io.github.cstcat.inputmethod.leftio.onehandt9
```

但脚本里切换输入源不一定立刻拉起 input method app；通常需要真实文本 client 聚焦后 IMK 才请求 endpoint。手动 `open ~/Library/Input Methods/LeftIO.app` 后，server 以新连接名启动：

```text
starting input method server bundle=io.github.cstcat.inputmethod.leftio connection=io.github.cstcat.inputmethod.leftio_Connection
IMKServer initialized=true
eventTapR enabled
```

下一步真实验收必须在文本框里切到 LeftIO 后按键，并查看：

```text
controller init
activateServer
handle keyCode=...
```

如果只有 `eventTapR enabled`，没有 `controller init`，说明 server 在跑但 IMK client 仍未绑定 controller。

### 18.12 2026-07-05 系统里出现两个 LeftIO 单手九宫格

症状：系统输入法列表/TIS 枚举里出现两个 `LeftIO 单手九宫格`。一开始容易误判为本地装了两个 app 包。

实际检查本机路径：

```text
present ~/Library/Input Methods/LeftIO.app
missing ~/Applications/LeftIO.app
missing /Library/Input Methods/LeftIO.app
missing /Applications/LeftIO.app
```

说明不是安装路径里有两个 `LeftIO.app`。真正原因是偏好域里重复启用了同一个 mode：

```text
com.apple.HIToolbox AppleEnabledInputSources:
  Bundle ID = io.github.cstcat.inputmethod.leftio
  Input Mode = io.github.cstcat.inputmethod.leftio.onehandt9

com.apple.inputsources AppleEnabledThirdPartyInputSources:
  Bundle ID = io.github.cstcat.inputmethod.leftio
  Input Mode = io.github.cstcat.inputmethod.leftio.onehandt9
```

`AppleEnabledThirdPartyInputSources` 里保留 LeftIO parent source 是必要的，但不应该再保留同一个 selectable mode；否则 TIS 会把同一个 `LeftIO 单手九宫格` mode 枚举两次。

本轮修复增加了一个手动修复入口；正常安装流程不自动写 `com.apple.HIToolbox` 或 `com.apple.inputsources`：

```sh
make repair-input-method-sources
```

这个命令的用途很窄：只在系统设置、菜单栏或 TIS 枚举里出现两个 `LeftIO 单手九宫格` 时使用。它不是安装步骤，也不是常规刷新手段。

它只处理 LeftIO 自己的条目：

- 删除旧 bundle ID `io.github.cstcat.leftio`。
- `com.apple.HIToolbox` 里只保留一条 `io.github.cstcat.inputmethod.leftio.onehandt9` mode。
- `com.apple.inputsources` 里只保留 LeftIO parent `Keyboard Input Method`，移除重复 mode。
- 只有确实需要改动时，才先备份对应的 plist。
- 刷新 `cfprefsd` 并杀掉旧 `LeftIO` 进程。

修复后 TIS 应该只看到一个 selectable mode 和一个 parent source：

```text
io.github.cstcat.inputmethod.leftio.onehandt9 | ... | LeftIO 单手九宫格 | enabled=1 | selectCapable=1
io.github.cstcat.inputmethod.leftio | - | LeftIO | enabled=1 | selectCapable=0
```

注意：第二行 parent source 是正常结构，不是第二个输入法。真正要避免的是两个 `LeftIO 单手九宫格` mode。

### 18.13 2026-07-05 菜单栏/Fn 选择器里的 LeftIO 图标发糊或不反色

症状：

- 右上角输入法菜单里 `L` 看起来发糊。
- Fn 输入法选择浮层里偶尔像是“不显示”。
- 菜单栏选中 LeftIO 后，`L` 仍然是黑色，没有像系统输入法一样在选中/深色背景上变浅。

根因拆开看：

1. 之前只生成一个 `16x16 menu_icon.png`。在 Retina 菜单栏、Fn 选择器或系统设置里被放大时必然发糊。
2. `TISIconIsTemplate` 只放在输入法顶层，mode 自己的 `tsInputModeMenuIconFileKey` 没有明确 template 标记。部分 TIS/IMK 场景会把它当普通彩色 PNG 画出来，于是选中后仍是黑色。
3. Fn 选择器和部分系统输入源 UI 更像系统内置输入法那样读取 `TISIconLabels/CustomIcon`，只给 PNG 不够稳。
4. 手写 PDF 时如果 `/Length` 或 page box 不对，CoreGraphics 可能仍能把它识别成 PDF 文件，但 Fn 选择器不会稳定显示。可用 `sips -g pixelWidth -g pixelHeight` 提前发现这类解析错误。

本轮改法：

- 继续保留 `menu_icon.png`，并新增 `menu_icon@2x.png`。
- 新增多表示 `menu_icon.tiff`，包含 16/32/64px 三个 representation，DPI 分别为 72/144/288，让它们都表示同一个 16pt 菜单栏图标，避免 Retina 放大糊。
- 新增矢量 `menu_icon@2x.pdf`，画布为 `28x36`，给 `TISIconLabels/CustomIcon` 使用；这个命名和尺寸对齐系统内置 Ainu 输入法的做法。
- 在 `TISIconLabels` 里同时写入 `Primary = L`，作为 Fn 选择器不吃 custom PDF 时的文字兜底。
- `tsInputMethodIconFileKey`、`tsInputModeMenuIconFileKey`、`tsInputModeAlternateMenuIconFileKey`、`tsInputModePaletteIconFileKey` 全部改为 `menu_icon.tiff`。
- 在 mode 级也增加 `TISIconIsTemplate = true`。

验证口径：

```sh
LEFTIO_ALLOW_LEXICON_ONLY=1 scripts/build_input_method_app.sh
scripts/install_input_method_app.sh
make verify-input-method
```

构建时 `tiffutil` 不应再提示 point size 不一致；`Info.plist` 里必须同时看到：

```text
TISIconIsTemplate = true
tsInputMethodIconFileKey = menu_icon.tiff
mode.TISIconIsTemplate = true
mode.TISIconLabels.Primary = L
mode.TISIconLabels.CustomIcon = menu_icon@2x.pdf
mode.tsInputModeMenuIconFileKey = menu_icon.tiff
```

安装后如果菜单栏仍显示旧黑图标，优先认为是 TIS/菜单栏缓存。可先轻量刷新：

```sh
pkill -x TextInputMenuAgent
pkill -x TextInputSwitcher
pkill -x imklaunchagent
pkill -x LeftIO
```

然后重新切回 `LeftIO 单手九宫格` 测试。仍不刷新时再考虑注销/重新登录。

### 18.14 2026-07-06 候选窗编号缺失、假编号和自绘候选窗边界

用户目标很明确：候选窗只显示 4 个候选，但每个候选仍然要有 `1 2 3 4` 选择标号；视觉要接近 macOS 自带输入法，小数字、圆角、背景、整体质感都要自然。

这轮踩坑很多，核心教训是：`IMKCandidates` 是系统候选窗，但它不等于一定能得到系统输入法同款视觉和 selection key 标注。

踩过的坑：

1. 只改源码、不重新打包安装是无效验证。
   `swift build` 只更新 `.build/...` 里的调试产物，不会让 macOS 正在加载的 `~/Library/Input Methods/LeftIO.app` 自动变化。每次输入法 UI 行为验证前，必须跑：

   ```sh
   scripts/build_input_method_app.sh
   scripts/install_input_method_app.sh
   ```

   然后用 `stat` / `codesign -dv` 确认安装目录的时间和 CDHash 确实更新。

2. `IMKCandidates.setSelectionKeys([18,19,20,21])` 并不保证视觉上显示 `1234`。
   运行日志已经证实过：

   ```text
   candidateWindow show count=4 panel=3 selectionKeys=[18, 19, 20, 21]
   ```

   这里 `panel=3` 是 `kIMKSingleRowSteppingCandidatePanel`，selection keys 也已经进去了，但当前系统上的候选窗仍然不画编号。问题不在“配置没进”，而是这条 IMKCandidates 渲染路径不显示 selection key 标注。

3. `setCandidateData` 里塞 `NSAttributedString("1 候选")` 会变成假编号。
   虽然能看到数字，但数字已经成为候选文本的一部分。即使点击候选时再把前缀剥掉，视觉上仍然像 `1发` / `2分` 这种“假候选正文”，和系统输入法的小标号不是一回事。

4. 透明占位 + overlay 也失败。
   方案曾经尝试：候选文本前留透明数字占位，再用单独 `NSPanel` 把数字贴在 IMKCandidates 上。实际问题：

   - IMKCandidates 的选中态可能忽略或重绘透明属性，导致 `1阿` 仍然露出来。
   - `IMKCandidates.candidateFrame()` 返回的位置不适合拿来贴 overlay，出现数字跑到底部的现象。
   - 这类 overlay 是两个窗口硬叠，和候选窗生命周期/坐标系不稳定。

5. “原生”要区分两层含义。
   `IMKCandidates` 是 InputMethodKit 自带候选窗，但当前无法满足 1234 标注和视觉要求。
   现在的候选窗是 LeftIO 自己创建的 AppKit 候选面板：

   - `NSPanel`
   - `NSVisualEffectView`
   - `NSStackView`
   - `NSTextField`
   - `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)` 定位

   它不是第三方库，也不是往正文里插数字再删除；但它也不是系统 `IMKCandidates`。

当前方向：

- 组合区/正文只保留真实输入和真实候选，不把编号写进 marked text。
- 候选窗由 LeftIO 输入法进程用 AppKit 画。
- 单行 compact 状态按 `1 2 3 4` 展示 4 个候选。
- 数字和候选字是两个 label，不再把数字拼进候选字符串。
- 视觉要继续按 macOS 自带输入法调：白色 popover 材质、细边框、柔和阴影、小号数字、较轻字重、右侧分隔线/箭头。

验收标准：

- 按 `1-4` 提交真实候选。
- 候选文本里不能出现被提交的 `1候选` / `2候选`。
- 不应有底部漂浮数字、重复数字、候选窗和编号错位。
- 每次 UI 修改后必须重新打包安装，不要只看 `swift build`。

### 18.15 2026-07-06 翻页展开不是把 4 个候选横向拉宽

用户期望的翻页/展开效果类似 macOS 自带输入法：按翻页键后出现多行候选面板，而不是单行候选条变宽。

踩坑：

1. 右侧箭头一开始只是视觉装饰，没有绑定展开状态。
   所以按 `F/G` 只会让后端翻页，UI 仍然是 compact 单行。这个是“假交互”，必须避免。

2. 直接把 expanded 面板宽度拉大，但仍只喂 `displayedCandidates`，会变成假展开。
   `displayedCandidates` 按 LeftIO 设计只是一页 4 个候选；拿这 4 个去画 expanded，就会出现一条很宽的面板里只有 4 个候选。

3. `menu/page_size: 4` 是正确设计，不应该为了展开面板改成 30。
   LeftIO 的选择模型是 `1-4`，所以展开也应该按 4 列组织。不能照搬系统拼音 6 列/30 个候选。

4. 30 个候选不是 4 的倍数。
   这是错误设定。展开候选数量必须是 4 的倍数。当前选择 `24`：4 列 x 最多 6 行。

5. Rime `candidate_list_from_index` 不能随便直接读 `iterator.candidate` 就认为拿到了全量候选。
   曾出现日志：

   ```text
   candidatePanel show count=4 requestedPresentation=expanded ...
   ```

   这说明 expanded 状态触发了，但全量候选实际仍只有 4 个。原因是 iterator 接法不对。

当前修正方向：

- 在 C bridge 暴露全量候选读取接口。
- 使用标准迭代流程：

  ```text
  candidate_list_begin
  candidate_list_next
  candidate_list_end
  ```

  逐个拉取前 24 个真实候选，而不是只拿当前页 4 个。

- Swift session 新增 `expandedCandidates`：

  - Rime session：通过 candidate iterator 取前 24 个。
  - Lexicon fallback：从 `allCandidates.prefix(24)` 取。
  - Recording session：提供空数组兜底。

- UI presentation 分两种：

  ```text
  compact  -> 4 个候选单行
  expanded -> expandedCandidates 按 4 列 x 最多 6 行
  ```

- `F/G` 对应 `.pageUp` / `.pageDown` 后切到 expanded。
- 输入新编码、插入分隔符、删除、选词、提交、取消后收回 compact。
- 如果 `expandedCandidates.count <= displayedCandidates.count`，不要假展开，继续显示 compact。

验收口径：

- 按 `G/F` 后日志应看到：

  ```text
  requestedPresentation=expanded effectivePresentation=expanded count>4
  ```

- 如果日志是：

  ```text
  requestedPresentation=expanded effectivePresentation=compact count=4
  ```

  说明当前编码/Rime iterator 只给到了 4 个候选，UI 不应该拉宽假装展开。

- 展开面板必须是 4 列，不是 6 列。
- 展开候选来自 Rime candidate iterator 的真实候选，不是重复当前页，也不是 UI 假补齐。

### 18.16 2026-07-06 展开态不能继续只做 Rime 翻页，也不能每次只看第一行

后续实测又暴露两个问题：

1. 有时候会出现一个空的 expanded 半透明外壳。
   日志里能看到 compact 状态却沿用 expanded 高度：

   ```text
   candidatePanel show count=4 requestedPresentation=compact effectivePresentation=compact frame=(221.0, -89.0, 262.0, 206.0)
   candidatePanel show count=4 requestedPresentation=compact effectivePresentation=compact frame=(221.0, -45.0, 262.0, 162.0)
   ```

   这不是视觉参数问题，而是 `NSPanel` / `NSVisualEffectView` / 内容视图的 frame 没有在同一轮更新里归一。
   只在 `CandidatePanelContentView.configure()` 里改内部 frame，AppKit 会让外层窗口残留旧高度，产生空壳。

   修正要点：

   - `configure()` 只重建内容并标记 `needsLayout`。
   - `CandidateWindowController.update()` 统一计算目标 size。
   - 同一轮里设置 `panel.frame`、`panel.contentView?.frame`、`contentView.frame`。
   - 最后 `layoutSubtreeIfNeeded()` 和 `displayIfNeeded()`，不要等下一轮 layout 自己追上。

2. `F/G` 不能只继续调用 Rime 的 `.pageUp` / `.pageDown`。
   旧逻辑里连续按 `G` 的日志是：

   ```text
   candidatePanel show count=24 requestedPresentation=expanded effectivePresentation=expanded frame=(221.0, 149.0, 312.0, 250.0)
   actions=[OneHand.OneHandAction.pageDown]
   candidatePanel show count=24 requestedPresentation=expanded effectivePresentation=expanded frame=(221.0, 149.0, 312.0, 250.0)
   ```

   count、frame、候选窗口起点都没变，所以用户看到的是“只能展开一次，不能下一行/上一行”。

第二轮又踩了一个坑：把 `G/F` 做成 `expandedCandidateStartIndex += 4/-=4` 仍然不对。
这会导致视觉上永远只是在看“当前窗口第一行”，用户没法在同一个展开页里看第 2、3、4、5、6 行。

正确模型要拆成两个状态：

- `expandedCandidateStartIndex`：当前展开页起点，按 24 个候选一页移动。
- `expandedActiveRowIndex`：当前展开页里的活动行，按 4 个候选一行移动。
- `G`：先 `expandedActiveRowIndex += 1`。
- `F`：先 `expandedActiveRowIndex -= 1`。
- 只有活动行越过当前展开页底部/顶部时，才把 `expandedCandidateStartIndex` 切到下一页/上一页。
- 展开态按 `1-4` 时，提交索引应该是：

  ```text
  expandedCandidateStartIndex + expandedActiveRowIndex * 4 + digitIndex
  ```

- C bridge 需要暴露 librime 的 `select_candidate(session, index)`，Swift session 再提供 `commitExpandedCandidate(at:)`。

验收口径：

- 连续按 `G` 时，日志里的 `activeRow` 应该先按 `1, 2, 3...` 变化，`expandedStart` 在到达当前展开页底部前不应该变化。
- 只有越过当前展开页底部/顶部时，`expandedStart` 才按 `24` 的步长翻到下一页/上一页。
- 按 `F` 时，`activeRow` 应该先回退；到第 0 行再按才回上一页。
- compact/expanded 来回切时 compact 高度应该直接回到 `44`，不能再出现 `206 -> 162 -> 118 -> 74 -> 44` 这种旧高度逐步回落。
- 展开态最后一行即使不足 4 个候选，也仍然应该显示 expanded，而不是被误判回 compact。
- 如果总候选数不超过 4，按 `F/G` 不应该假展开。
