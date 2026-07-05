# LeftIO macOS 输入法安装排查阶段记录

记录时间：2026-07-03 18:04 +0800

## 目标

让 LeftIO 安装后在 macOS 输入法列表里稳定出现，并且能被选中。

明确验收信号：

- `/Library/Input Methods/LeftIO.app` 是唯一有效的 LeftIO 系统输入法包。
- 旧 bundle ID `io.github.cstcat.leftio` 不再残留在 `AppleEnabledInputSources`。
- TIS 新进程枚举能看到：
  - bundle: `io.github.cstcat.inputmethod.leftio`
  - mode: `io.github.cstcat.inputmethod.leftio.onehandt9`
- `TISSelectInputSource` 能选中 LeftIO，或者当前输入法稳定变成 LeftIO。
- 系统设置的输入法列表里能看到并选中 `LeftIO 单手九宫格`。

## 本次改动

### 构建与 Info.plist

- `scripts/build_input_method_app.sh`
  - 构建单一 `LeftIO.app` 输入法包。
  - bundle ID 改为 `io.github.cstcat.inputmethod.leftio`。
  - mode ID 改为 `io.github.cstcat.inputmethod.leftio.onehandt9`。
  - 生成 `Contents/Resources/InfoPlist.strings`，包含 `LeftIO 单手九宫格` 显示名。
  - `InputMethodServerControllerClass` 和 `InputMethodServerDelegateClass` 使用稳定 ObjC 名称 `LeftIOInputController`。
  - 使用 Apple Development 证书签名时增加 hardened runtime：`codesign --options runtime`。
  - 对 `Contents/Frameworks/librime.1.dylib` 也做同一身份签名。

### 输入法主程序与注册逻辑

- `Sources/LeftIOInputMethod/LeftIOInputController.swift`
  - 增加 `@objc(LeftIOInputController)`，让 Info.plist 里的 controller class 能稳定解析。

- `Sources/LeftIOInputMethod/LeftIOInputMethodApp.swift`
  - 注册 helper 支持 `--register-installed-input-source`。
  - 注册时调用 `TISRegisterInputSource`。
  - 写入/修正 `com.apple.HIToolbox` 里的输入源偏好。
  - 清理旧 ID `io.github.cstcat.leftio`。
  - 注册日志写入 `~/Library/Input Methods/LeftIO.register.log`。

### 安装脚本

- `scripts/install_input_method_app.sh`
  - 改为转向系统级安装路径，提示稳定安装需要 `/Library/Input Methods`。

- `scripts/install_input_method_app_system.sh`
  - 安装到 `/Library/Input Methods/LeftIO.app`。
  - 每次安装前先清理旧残留，再执行复制与注册。
  - 删除旧位置：
    - `~/Library/Input Methods/LeftIO.app`
    - `~/Applications/LeftIO.app`
    - `/Applications/LeftIO.app`
    - `/Library/Input Methods/LeftIO.app`
  - 清理旧残留还包括：
    - `com.apple.HIToolbox` 里的 LeftIO 相关条目
    - `~/Library/Input Methods/LeftIO.register.log`
    - `~/Library/Input Methods/LeftIO.server.log`
    - `~/Library/Input Methods/LeftIO.launch.log`
    - 旧 LaunchServices / pluginkit 注册记录
    - `~/Library/Saved Application State/io.github.cstcat.inputmethod.leftio.savedState`
  - 支持 `LEFTIO_INSTALL_WITH_SUDO=1`，用于在用户自己的终端里显示 `sudo` 密码提示，绕开 Codex/osascript 授权窗不可见的问题。
  - 复制后执行已安装二进制：
    - `/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO --register-installed-input-source`
  - 重启 Text Input 相关 agent 并刷新 LaunchServices。

### 验证脚本

- 新增 `scripts/verify_input_method_install.sh`。
- 新增 Makefile 入口：
  - `make verify-input-method`

验证内容包括：

- 已安装 bundle 的 Info.plist 关键字段。
- `codesign --deep --strict`。
- `AppleEnabledInputSources` 里的 LeftIO 条目。
- quarantine/provenance 扩展属性。
- TIS 新进程枚举里的 `bundle/mode/selected` 状态。

### 文档

- `README.md`
  - 更新本地安装说明。
  - 说明稳定安装路径为 `/Library/Input Methods/LeftIO.app`。
  - 增加不可见图形授权窗时的 fallback 命令：

```sh
LEFTIO_INSTALL_WITH_SUDO=1 make install-input-method
```

## 已成功证明的点

### 1. 用户终端 sudo 安装可以完成

用户在本机终端执行：

```sh
cd /Users/cat/Documents/left-io
LEFTIO_INSTALL_WITH_SUDO=1 make install-input-method
```

结果成功输出：

```text
/Library/Input Methods/LeftIO.app
```

说明系统级复制流程已经能通过可见终端密码提示完成。

### 2. 系统安装包已经是新 bundle ID

`make verify-input-method` 显示：

```text
io.github.cstcat.inputmethod.leftio
LeftIO
LeftIOInputMethod_1_Connection
LeftIOInputController
```

说明 `/Library/Input Methods/LeftIO.app` 的核心 Info.plist 字段已经是新结构。

### 3. 代码签名有效

`make verify-input-method` 显示：

```text
/Library/Input Methods/LeftIO.app: valid on disk
/Library/Input Methods/LeftIO.app: satisfies its Designated Requirement
```

另外手动检查显示当前安装包为 Apple Development 签名，并带 hardened runtime：

```text
flags=0x10000(runtime)
Authority=Apple Development: <redacted>
Signed Time=Jul 3, 2026 at 18:00:44
```

### 4. 旧 ID 已从启用列表移除

`AppleEnabledInputSources` 里当前只看到新 ID：

```text
"Bundle ID" = "io.github.cstcat.inputmethod.leftio";
"Input Mode" = "io.github.cstcat.inputmethod.leftio.onehandt9";
```

没有再看到旧 ID：

```text
io.github.cstcat.leftio
```

### 5. 单元测试通过

执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-swift-testing
```

结果：

```text
Executed 58 tests, with 0 failures
```

## 仍失败的点

### 1. TIS 新进程仍然无法稳定枚举 LeftIO

用户 sudo 安装完成后执行：

```sh
make verify-input-method
```

失败输出：

```text
== TIS sources ==
all 320
current com.tencent.inputmethod.wetype.pinyin 微信输入法 com.tencent.inputmethod.wetype
bundle=false
mode=false
selected=false
make: *** [verify-input-method] Error 2
```

这说明当前失败点已经不是“没有复制到系统目录”，而是 TIS 注册/缓存层没有把这个新版 LeftIO 接纳进长期枚举。

### 2. 注册 helper 返回成功，但外部 TIS 进程看不到

手动运行：

```sh
/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO --register-installed-input-source
```

退出码为 0，注册日志持续出现：

```text
register helper started: /Library/Input Methods/LeftIO.app
register helper succeeded: select status=-50
```

但随后新的 Swift/TIS 进程仍显示：

```text
all 320
```

且没有任何 `leftio` / `cstcat` 条目。

结论：`TISRegisterInputSource` 在 helper 内部没有报错，但注册结果没有变成外部 TIS 可见的长期状态。

### 3. `TISSelectInputSource` 仍返回 `-50`

之前在 TIS 能短暂看到 LeftIO 时，mode 曾显示：

```text
io.github.cstcat.inputmethod.leftio.onehandt9 | ... | enabled=1 | selectCapable=1
```

但选择仍返回：

```text
select -50
```

对照 WeType：

```text
select com.tencent.inputmethod.wetype.pinyin 0
```

说明 LeftIO 与已安装第三方输入法 WeType 相比，仍有某个 TIS/IMK 接纳条件不满足。

### 4. `com.apple.provenance` 仍然存在

`make verify-input-method` 仍显示安装包上有大量：

```text
com.apple.provenance
```

但补充观察：

- WeType 没有 provenance，只有 `com.apple.macl`。
- 即使用 `ditto --noextattr --noqtn` 或 `cp -R -X` 复制 app，macOS 26.5.2 仍会自动给新 app bundle 加 provenance。
- 普通 `xattr -d com.apple.provenance` 返回成功但属性仍存在。

结论：provenance 可能相关，但当前不能单独证明它就是根因。

## WeType 对照事实

本机可工作的第三方输入法 WeType：

```text
Bundle ID: com.tencent.inputmethod.wetype
Connection: WeType_Connection
Controller: WeType.InputController
Mode: com.tencent.inputmethod.wetype.pinyin
```

TIS 能看到：

```text
com.tencent.inputmethod.wetype.pinyin | ... | TISTypeKeyboardInputMode | 微信输入法 | 1 | 1 | 0
com.tencent.inputmethod.wetype | ... | TISTypeKeyboardInputMethodModeEnabled | 微信输入法 | 1 | 0 | 0
```

选择 WeType 返回：

```text
select com.tencent.inputmethod.wetype.pinyin 0
```

重要差异：

- WeType 是 Developer ID Application 签名。
- WeType 有 hardened runtime。
- WeType 有 notarized/正式分发背景。
- LeftIO 目前只有 Apple Development 签名，即使已经加 hardened runtime，也不是 Developer ID 分发签名。

## 当前判断

已经排除或部分排除：

- 旧 ID 残留不是当前唯一问题，旧 ID 已清。
- 系统目录未覆盖不是当前问题，用户已 sudo 安装成功。
- 基础签名损坏不是当前问题，`codesign --deep --strict` 通过。
- controller class 基本不再是明显问题，已使用 `@objc(LeftIOInputController)` 且 Info.plist 对应。

仍最可疑：

1. macOS 26.5.2 对 `/Library/Input Methods` 中的第三方输入法可能更依赖 Developer ID / notarization / trust cache。
2. 当前 Apple Development 签名的 direct IMK app 虽然能运行，但 TIS 不把它稳定收进全局可选输入源。
3. Info.plist 还可能缺少某个新系统要求的元数据，但它与 WeType 的核心 `ComponentInputModeDict` 结构已经非常接近。
4. `TISRegisterInputSource` 的返回值不足以证明注册成功，需要 helper 继续记录注册后同进程的 bundle/mode/source 属性，查明它到底看到了什么。

## 下一步建议

### A. 增强注册 helper 日志

在 `LeftIOInputMethodApp.swift` 的 `completeInstalledRegistration()` 中记录：

- `TISRegisterInputSource` 返回值。
- 通过 bundle ID 查询到的 source 数量。
- 通过 mode ID 查询到的 source 数量。
- 每个 source 的：
  - `kTISPropertyInputSourceID`
  - `kTISPropertyInputModeID`
  - `kTISPropertyBundleID`
  - `kTISPropertyInputSourceType`
  - enabled/selectCapable/selected

目的是确认 helper 内部和外部新进程看到的 TIS 状态是否不一致。

### B. 继续和 WeType plist 做最小差异对齐

可尝试但要逐项验证：

- 去掉 LeftIO mode 里的 `TISIconLabels`。
- 把图标从 `.tiff` 改为 `.pdf` 或至少确认 tiff 不影响 TIS 接纳。
- `tsInputMethodCharacterRepertoireKey` 增加 `Hant`，和 WeType 对齐为 `Hans/Hant/Latn`。
- 评估 `NSPrincipalClass` 是否需要自定义 `NSApplication` 子类。

### C. 如果 plist 对齐仍失败，验证签名/公证假设

如果可获得 Developer ID Application 证书，应构建 Developer ID + hardened runtime 版本，再安装到 `/Library/Input Methods` 测试：

```sh
LEFTIO_SIGNING_IDENTITY="Developer ID Application: ..." make install-input-method
make verify-input-method
```

如果 Developer ID 版本能被 TIS 稳定枚举和选中，则当前根因基本可以归为 macOS 26 对开发签名输入法的信任限制。

## 当前结论

本阶段没有完成最终目标。

当前状态是：

- 安装流程已经能在用户终端通过 sudo 成功执行。
- 系统目录安装包、bundle ID、签名、旧 ID 清理都已有明确成功证据。
- 但 TIS 新进程仍显示 `bundle=false`、`mode=false`、`selected=false`。
- 因此 “安装后在 macOS 输入法列表里稳定出现并能选中” 仍未修好。

## 继续推进（本轮新增证据）

在本轮里，继续补了两类改动：

- `Sources/LeftIOInputMethod/LeftIOInputMethodApp.swift`
  - 为 `--register-installed-input-source` helper 增加分阶段 TIS 诊断日志：
    - `before-register`
    - `after-register`
    - `after-select`
  - 记录 `TISRegisterInputSource` 返回值。
  - 记录按 bundle/sourceID/inputModeID 查询到的 source 数量。
  - 记录每个匹配 source 的：
    - `sourceID`
    - `modeID`
    - `bundleID`
    - `type`
    - `name`
    - `enabled`
    - `selectCapable`
    - `selected`

- `scripts/build_input_method_app.sh`
  - 去掉 mode 里的 `TISIconLabels`。
  - 将菜单图标从 `menu_icon.tiff` 改为 `menu_icon.pdf`。
  - `tsInputMethodCharacterRepertoireKey` 增补 `Hant`，与 WeType 更接近。

## 继续推进（23:40 后新增情况）

- 已确认图标资源问题本身已经修正：
  - 当前构建产物 `.build/input-method/LeftIO.app/Contents/Resources/menu_icon.png` 为 `16x16`
  - 当前系统安装包 `/Library/Input Methods/LeftIO.app/Contents/Resources/menu_icon.png` 也已变成 `16x16`
  - 因此 “Logo 过大” 这件事已经不再是旧资源未替换的问题

- 已确认重复注册调用被截断：
  - `LeftIO.register.log` 现在出现：
    - `register helper skipped TISRegisterInputSource because LeftIO is already present in this session`
  - 说明同一会话里如果已能看到 LeftIO source，helper 不会再无条件重复 `TISRegisterInputSource`

- 但新鲜外部 TIS 进程仍然失败：
  - `scripts/verify_input_method_install.sh` 仍显示：
    - `bundle=false`
    - `mode=false`
    - `selected=false`
  - 所以“图标”和“重复 register”不是最终根因，TIS 全局接纳问题还在

- 本轮还暴露出一个副作用，并已立刻回滚：
  - 我为了更彻底清残留，曾删除 `~/Library/Preferences/com.apple.inputsources.plist`
  - 这会误伤用户已有第三方输入法列表，导致 WeType 在系统设置/菜单里的可见状态异常
  - 同时，安装脚本里把 LeftIO 写入 `AppleSelectedInputSources` / `AppleCurrentKeyboardLayoutInputSourceID` 的 fallback，也会不必要地影响用户当前输入法

- 已执行的回滚与恢复：
  - `scripts/install_input_method_app_system.sh`
    - 不再删除 `com.apple.inputsources.plist`
    - 不再强行改 `AppleSelectedInputSources`
    - 不再强行改 `AppleCurrentKeyboardLayoutInputSourceID`
  - `Sources/LeftIOInputMethod/LeftIOInputMethodApp.swift`
    - 当 `TISSelectInputSource` 返回非 `0` 时，只记录失败，不再用 HIToolbox fallback 去强切当前输入法
  - 已手动恢复用户偏好：
    - 把 `com.tencent.inputmethod.wetype`
    - `com.tencent.inputmethod.wetype.pinyin`
    - 重新写回 `com.apple.HIToolbox`
    - 并重建 `com.apple.inputsources.plist` 的 `AppleEnabledThirdPartyInputSources`

- 当前阶段最新判断：
  - LeftIO 图标资源问题已修正
  - WeType 偏好已恢复，后续排查不应再影响用户现有输入法
  - LeftIO 重复项的 UI 现象与外部 TIS `bundle=false / mode=false` 仍未解决
  - 后续若继续推进，应只做“不改当前输入法选择、不删第三方输入法列表”的保守排查

## 继续推进（23:55 后新增情况）

- 用户反馈：不仅 LeftIO，连 WeType 也在菜单/UI 里出现大量重复项

- 重新核对后的事实：
  - `~/Library/Preferences/com.apple.HIToolbox.plist`
    - WeType 与 LeftIO 都只有一组启用项
  - `~/Library/Preferences/com.apple.inputsources.plist`
    - WeType 与 LeftIO 也都只有一组第三方输入源项
  - 说明“十几个重复项”依旧不是偏好文件里真的有十几份

- 新鲜 TIS 进程里的现象：
  - WeType 的 container source 只有 1 条
  - WeType 的 `com.tencent.inputmethod.wetype.pinyin` mode source 出现 2 条
  - LeftIO 的 mode source 也曾出现 2 条
  - 这说明重复项已经进入 TIS/会话层，不只是系统设置列表文本渲染问题

- 已做且已验证的安全恢复：
  - 删除系统设置和输入法菜单缓存：
    - `com.apple.systemsettings.usercache`
    - `com.apple.systemsettings.menucache`
    - `com.apple.textinput.KeyboardServices`
    - `com.apple.TextInputMenuAgent.plist`
    - `com.apple.TextInputMenu.plist`
    - `com.apple.menuextra.textinput.plist`
    - `com.apple.keyboardservicesd.plist`
  - 重启：
    - `TextInputMenuAgent`
    - `TextInputSwitcher`
    - `keyboardservicesd`
    - `SystemUIServer`
    - `ControlCenter`
    - `cfprefsd`

- 结果：
  - 仅清缓存不足以把 TIS 会话里的重复 source 清掉

- 一次额外尝试与回退：
  - 试过先切到系统自带简体拼音，再对 WeType/LeftIO 做一次 `TISDisableInputSource`/`TISEnableInputSource`
  - 结果：
    - WeType 的 `TISSelectInputSource` 返回过 `-50`
    - 当前输入法一度被系统切回 `com.apple.inputmethod.SCIM.ITABC`
  - 已立即恢复：
    - 重新把 `AppleSelectedInputSources`
    - `AppleCurrentKeyboardLayoutInputSourceID`
    - 写回 WeType
    - 当前输入法已恢复为 `com.tencent.inputmethod.wetype.pinyin`

- 最新保守结论：
  - 当前用户可用性已先恢复到“微信输入法重新可用”
  - 但 TIS 会话层重复 source 仍存在
  - 在不注销/不重启整个用户会话的前提下，当前脚本级修复还没有把这个重复态彻底清掉

### 新日志给出的关键事实

把新构建的 `LeftIO.app` 复制到 `~/Library/Input Methods` 后，手动执行：

```sh
~/Library/Input\ Methods/LeftIO.app/Contents/MacOS/LeftIO --register-installed-input-source
```

日志显示：

```text
register helper snapshot[before-register] all=320
register helper snapshot[before-register] bundleMatches=0
register helper snapshot[before-register] sourceIDMatches=0
register helper snapshot[before-register] inputModeMatches=0
```

执行 `TISRegisterInputSource` 后，同一个 helper 进程里立刻变成：

```text
register helper register status=0
register helper snapshot[after-register] all=324
register helper snapshot[after-register] bundleMatches=6
register helper snapshot[after-register] sourceIDMatches=4
register helper snapshot[after-register] inputModeMatches=5
```

而且 helper 进程内部已经能看到 LeftIO source：

```text
sourceID=io.github.cstcat.inputmethod.leftio.onehandt9 | modeID=io.github.cstcat.inputmethod.leftio.onehandt9 | bundleID=io.github.cstcat.inputmethod.leftio | type=TISTypeKeyboardInputMode | name=LeftIO 单手九宫格 | enabled=1 | selectCapable=1 | selected=0
```

但选择仍失败：

```text
register helper succeeded: select status=-50
```

更重要的是，helper 结束后再起一个新的外部 TIS 进程检查，结果仍然是：

```text
all 320
bundle=false
mode=false
```

### 这批新证据意味着什么

当前可以更明确地判断：

- `TISRegisterInputSource` 在 helper 当前进程内确实制造出了 LeftIO source，说明它不是完全 no-op。
- 这些 source 没有变成外部新进程可见的长期全局状态，说明“helper 内可见”不等于“系统已经正式接纳”。
- 反复注册会继续堆叠重复的 LeftIO source 计数，进一步说明现在更像是进程内/临时层面的注册结果，而不是稳定入库。
- 因此，问题比“plist 缺一两个字段”更像是：
  - 系统信任链限制（Developer ID / notarization / trust）
  - 或 macOS 26 对第三方 InputMethodKit app 的更严格接纳条件

### 本轮后的更强判断

到目前为止，最强的新结论是：

- LeftIO 已经能在注册 helper 自己的进程里被 TIS 枚举到。
- 但它仍无法进入外部新进程的稳定全局 TIS 列表。
- 所以当前主问题很可能不再是“helper 没注册”，而是“系统没有持久接纳这份输入法包”。

## 继续推进（系统级复测补充）

在拿到用户 sudo 密码后，本轮又做了两项系统级实验：

- 用新构建重新安装到 `/Library/Input Methods/LeftIO.app`。
- 补强安装脚本，额外清理旧 `~/Applications/LeftIO.app` 的 LaunchServices / pluginkit 残留，并把 `lsregister -f` 提前到 register helper 之前。

同时，在 register helper 里增加了短暂 RunLoop 等待，避免 `TISRegisterInputSource` 刚返回进程就退出。

### 系统级复测结果

重装后，外部验证仍然失败：

```text
all 320
bundle=false
mode=false
selected=false
```

但 helper 日志已经出现了更强的“进程内成功”信号：

```text
register helper snapshot[after-select] source[1] sourceID=io.github.cstcat.inputmethod.leftio.onehandt9 | ... | selected=1
register helper snapshot[after-select] current sourceID=io.github.cstcat.inputmethod.leftio.onehandt9 | ... | selected=1
```

与此同时，日志里仍然写着：

```text
register helper succeeded: select status=-50
```

也就是说，helper 最终能把“自己看到的当前输入法”切成 LeftIO，但这个结果仍没有反映到外部新 TIS 进程。

### 新增结论

这组系统级复测进一步说明：

- 旧 `~/Applications/LeftIO.app` 残留不是当前主因，清理后结果没有根本变化。
- 让 helper 多活一会儿、提前 `lsregister -f`，也没有把 LeftIO 推进到外部全局 TIS 可见状态。
- `TISSelectInputSource` / `TISCopyCurrentKeyboardInputSource` 在 helper 内看到的“已选中”，不能当作系统全局已切换的证据。
- 到这一步，Developer ID / notarization / 更高等级信任链限制的可疑度继续上升。

## 继续推进（本轮新发现）

这一轮从统一日志里挖到了比之前更直接的系统错误：

```text
imklaunchagent ... Refusing connection name for bundle: unrecognized 'InputMethodConnectionName' value
imklaunchagent ... LaunchInputMethod() Error, status=-50
imklaunchagent ... NO Endpoint, Bail & Post to request completion queue!
```

### A. 已确认的一个真实问题：旧 connection name 会被拒绝

当 `InputMethodConnectionName` 还是旧值：

```text
LeftIOInputMethod_1_Connection
```

时，`imklaunchagent` 明确报：

```text
Refusing connection name for bundle: unrecognized 'InputMethodConnectionName' value
```

因此本轮已把构建脚本里的连接名改为：

```text
LeftIO_Connection
```

### B. connection name 修正后，错误前进了一步

系统级重装后再次查看日志，之前那条：

```text
Refusing connection name for bundle: unrecognized 'InputMethodConnectionName' value
```

已经不再出现。

这说明：

- `LeftIOInputMethod_1_Connection` 的确是错误/过时的连接名。
- 把它改成 `LeftIO_Connection` 是有效修复，不是无关噪音。

### C. 但最终问题还没解决：现在卡在 Endpoint/进程生命周期

虽然 connection name 拒绝消失了，但系统仍然报：

```text
LaunchInputMethod() Error, status=-50
IMKLaunchAgent -getIMKXPCEndpointForBundle: NO Endpoint, Bail & Post to request completion queue!
IMKLaunchAgent -requestIMKXPCEndpointInvalid: received notification Request for Endpoint Invalid ...
```

同时，`LeftIO` 进程本身会被系统正常拉起，日志里能看到：

```text
CHECKIN: pid=...
CHECKEDIN: pid=... foreground=0
Registered, pid=...
BringForward: ... uiElement=1
```

但随后大约 3-4 秒后又干净退出，没有 crash report。

关键观察：

- 这更像“进程生命周期 / endpoint 交接失败”而不是“app 根本没被拉起”。
- 也就是说，问题已经从“connection name 非法”推进到了“connection name 合法，但 agent 最终拿不到稳定 endpoint”。

### D. 手动启动时，IMKServer 初始化是成功的

手动从终端运行：

```sh
/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO
```

新加的本地 server 日志会写出：

```text
starting input method server bundle=io.github.cstcat.inputmethod.leftio connection=LeftIO_Connection
IMKServer initialized=true
```

说明：

- 当前安装包里的新二进制确实能创建 `IMKServer`。
- “二进制本身完全起不来” 不是当前结论。

### E. 当前最可疑的剩余方向

到本轮结束，最值得继续追的点变成：

- 系统通过 `imklaunchagent` 拉起时，`LeftIO` 为什么会在数秒内退出。
- endpoint 是不是已经短暂建立、但没有以 agent 认可的方式稳定交给 `imklaunchagent`。
- 启动模式识别（runInputMethod vs installAndRegister）在系统拉起路径下是否存在偏差。

## 安装流程补强（先清残留）

本轮还把“每次安装先清旧残留”固化进了 `scripts/install_input_method_app_system.sh`，不再依赖手动记忆。

当前安装脚本会先执行以下清理：

- kill 旧的 `LeftIO` / `LeftIOInputMethod` / `LeftIOLauncher` / `TextInputMenuAgent` / `TextInputSwitcher` / `imklaunchagent`
- 删除旧 app：
  - `~/Library/Input Methods/LeftIO.app`
  - `~/Applications/LeftIO.app`
  - `/Applications/LeftIO.app`
  - `/Library/Input Methods/LeftIO.app`
- 清理日志：
  - `~/Library/Input Methods/LeftIO.register.log`
  - `~/Library/Input Methods/LeftIO.server.log`
  - `~/Library/Input Methods/LeftIO.launch.log`
- 清理 `com.apple.HIToolbox` 中 LeftIO 相关条目：
  - `AppleEnabledInputSources`
  - `AppleInputSourceHistory`
  - `AppleSelectedInputSources`
  - `AppleCurrentKeyboardLayoutInputSourceID`（若当前正好指向 LeftIO mode）
- 清理旧 LaunchServices / pluginkit 记录
- 清理保存态：
  - `~/Library/Saved Application State/io.github.cstcat.inputmethod.leftio.savedState`

实际复测结果：

- 安装后 `~/Library/Input Methods/LeftIO.register.log` 已从空白重新生成，只包含本轮记录。
- `AppleEnabledInputSources` 中 LeftIO 只保留当前新 bundle 的两条条目，没有旧 `io.github.cstcat.leftio` 残留。

这一步没有直接修好最终 TIS 可见性问题，但至少把“上一轮残留污染本轮实验”的干扰显著压低了。

## 继续推进（18:53 之后的新证据）

### 1. 系统设置里已经能看到并添加 LeftIO

用户在“键盘 > 文本输入 > 编辑”里，已经能看到并添加：

```text
LeftIO 单手九宫格
```

添加完成后，LeftIO 也确实出现在“所有输入法”的当前列表里。

这说明：

- “安装到本机后完全不可见” 这个判断已经不成立。
- `/Library/Input Methods/LeftIO.app` 至少已经被系统设置识别为可添加输入法。

### 2. 之前有一轮实验是误用 root 运行了整段安装脚本

补查共享日志 `/Users/Shared/LeftIO.launch.log` 后发现，曾有一轮执行路径其实是：

```text
uid=0 euid=0 home=/var/root args=["/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO", "--register-installed-input-source"]
```

这说明那一轮不是“当前桌面用户”的真实注册路径，而是把整个安装脚本都放进了 `sudo` 环境里，导致注册 helper 在 root 会话中运行。

因此可以明确修正一条方法结论：

- 正确调用方式应该是：

```sh
LEFTIO_INSTALL_WITH_SUDO=1 make install-input-method
```

- 而不是在脚本外层再套一层整段 `sudo`。

### 3. 用户态 helper 运行后，TIS 外部枚举终于稳定看到 LeftIO

重新用当前用户直接执行：

```sh
/Library/Input Methods/LeftIO.app/Contents/MacOS/LeftIO --register-installed-input-source
```

日志显示 helper 是在真实用户态运行：

```text
uid=501 euid=501 home=/Users/cat
```

并且同进程里再次证明：

```text
register helper snapshot[after-select] current sourceID=io.github.cstcat.inputmethod.leftio.onehandt9
```

随后外部验证脚本的状态从原来的：

```text
bundle=false
mode=false
selected=false
```

推进到：

```text
bundle=true
mode=true
selected=false
```

也就是说：

- LeftIO 已经不再只是“系统设置可见”。
- 它已经进入外部新进程可见的 TIS 列表。

### 4. 真正缺失的是当前用户的 HIToolbox 选择态

虽然系统设置左侧列表里已经有 LeftIO，但当时读取当前用户偏好却发现：

- `AppleEnabledInputSources` 里没有 LeftIO
- `AppleSelectedInputSources` 里仍然只有：
  - `com.apple.PressAndHold`
  - `com.tencent.inputmethod.wetype.pinyin`

这解释了为什么用户当时会看到：

- 系统设置里“已经添加”
- 但右上角输入法菜单和 `fn` 切换里仍然没有

结论不是“LeftIO 没装上”，而是：

- 系统 UI 列表和当前用户输入法选择态发生了脱节。

### 5. 强制写入当前用户输入法偏好后，最终状态已变为 selected=true

手动补写以下用户偏好后：

- `AppleEnabledInputSources`
- `AppleInputSourceHistory`
- `AppleSelectedInputSources`
- `AppleCurrentKeyboardLayoutInputSourceID`

再重启：

- `cfprefsd`
- `TextInputMenuAgent`
- `TextInputSwitcher`
- `imklaunchagent`

重新执行：

```sh
make verify-input-method
```

得到：

```text
current io.github.cstcat.inputmethod.leftio.onehandt9 LeftIO 单手九宫格 io.github.cstcat.inputmethod.leftio
bundle=true
mode=true
selected=true
```

这是本轮最重要的新结论：

- 从外部新进程看，LeftIO 已经被系统真正选中。
- “本地安装 + 注册 + 进入当前输入法状态” 这一条链路已经打通。

### 6. 已把本轮有效补救固化回安装脚本

基于本轮实测，把 `scripts/install_input_method_app_system.sh` 再补强了两点：

- 共享日志 `/Users/Shared/LeftIO.*.log` 也纳入“每次安装前先清残留”
- 在执行用户态注册 helper 后，再强制补写：
  - `AppleEnabledInputSources`
  - `AppleInputSourceHistory`
  - `AppleSelectedInputSources`
  - `AppleCurrentKeyboardLayoutInputSourceID`
- 然后主动重启：
  - `cfprefsd`
  - `TextInputMenuAgent`
  - `TextInputSwitcher`
  - `imklaunchagent`

目的是把这次“手工补偏好后才真正 selected=true”的路径，变成后续安装脚本默认执行的一部分。

## 当前结论（已更新）

到 2026-07-03 18:56 +0800 为止，结论已经从之前的“仍未装上”改成：

- LeftIO 已能被系统设置识别并添加。
- LeftIO 已能出现在外部 TIS 新进程枚举里。
- 通过补齐当前用户 HIToolbox 偏好并刷新输入法 agent 后，外部验证已经达到：

```text
bundle=true / mode=true / selected=true
```

因此，本轮已经首次拿到“LeftIO 本地安装并进入当前输入法状态”的正向系统证据。

## 兼容构建结论（19:08 新增）

后续继续对照后，发现还有一条更关键的事实：

- 问题不在“用户机器是不是 macOS 26”
- 问题更像是“旧式 IMK app 用 macOS 26.5 SDK 直接新构建后，系统接纳路径不稳定”

为排除这一点，做了同机对照实验：

- 机器系统仍然是 macOS 26
- 仅把 LeftIO 输入法 app 改为：
  - 使用本机 `MacOSX15.4.sdk` 构建
  - `LSMinimumSystemVersion` 降到 `15.0`

安装这版后再次执行：

```sh
make verify-input-method
```

结果稳定得到：

```text
current io.github.cstcat.inputmethod.leftio.onehandt9 LeftIO 单手九宫格 io.github.cstcat.inputmethod.leftio
bundle=true
mode=true
selected=true
```

也就是说：

- 同一台 macOS 26 机器上
- 兼容构建版可以稳定进入最终验收态

因此，本轮新增判断是：

1. 用户操作系统版本不是根因。
2. 更可能的根因是：
   - 旧式 InputMethodKit app 在 macOS 26 上，使用 26.5 SDK 现构时，系统注册/接纳路径存在兼容性问题。
3. 一个有效工程修复是：
   - 输入法 app 默认优先使用 15.x macOS SDK 构建
   - 并保持较低的 `LSMinimumSystemVersion`

基于这个结论，已经把构建脚本默认行为改成：

- `scripts/build_input_method_app.sh`
  - 默认 `LSMinimumSystemVersion=15.0`
  - 若本机存在 `MacOSX15*.sdk`，优先用它构建输入法 app
  - 仍保留环境变量覆盖：
    - `LEFTIO_SDKROOT`
    - `LEFTIO_MIN_SYSTEM_VERSION`

当前默认构建再次验证，产物签名信息中已经能看到：

```text
Runtime Version=15.4.0
```

这说明默认构建路径已经切到兼容 SDK，而不是继续走之前不稳定的 26.5 SDK 路径。
