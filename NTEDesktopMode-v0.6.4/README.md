# NTEDesktopMode 0.6.4 release

基于用户确认已修复角色列表问题的 0.6.4-test.1，保留桌面角色槽位修复、一次性列表重建及失败恢复逻辑，并保留 0.6.3 的按键提示音修复。

## 使用

完全退出游戏，用本包的 `libNTEDesktopMode.dylib` 替换旧插件，只保留一份同名插件。PlayCover 键位映射继续关闭。

## 地址定位核对

角色列表修复已经采用动态定位，本 release 保留测试版的解析器：

- `PCSlotClass`、`MobileSlotClass` 等属性偏移来自当前主程序的反射信息。
- 主界面、头像控件和容器类缓存由类名和注册代码解析。
- 列表刷新函数由 Mach-O 函数边界、容器访问、类 getter 调用及指令特征交叉识别。
- 子项访问和 ClearChildren 虚表位置由当前程序的原生包装器和调用关系解析。
- 运行时使用本次解析结果加当前映像基址，调用前核对对象类型和原指令。

未写死某个游戏版本的函数地址，也未按 UUID／版本号白名单绑定。相同解析器在本地 1.4、1.5 上定位到不同地址并通过检查。部分识别依赖 Unreal 元数据布局和编译特征；未来这些结构变化仍可能需要维护。角色列表能力缺失或识别不唯一时跳过该修复。

## 日志关闭

本包默认关闭通用日志和角色列表日志，不创建／写入 plugin.log 或 party-ui.log，不采集键盘焦点／调用栈或角色控件诊断信息。关闭日志时，诊断参数不会求值，也不会为日志读取控件可见性和透明度。修复所需的类型与列表有效性检查保留。

原有可选布尔配置继续有效，通常无需修改：`KeyboardBeepFixEnabled`、`RepairPartyDesktopUI`、`PartyUIRebuildExisting`，均默认开启。修改只作用于当前游戏进程，不保存游戏设置、不改写资源文件。

## 构建和验证

```sh
zsh build.sh
zsh tests/run.sh
```

默认 `NTE_ENABLE_LOGGING=0`、`NTE_ENABLE_PARTY_LOGGING=0`、`NTE_ENABLE_HARDWARE_OBSERVERS=0`。开发者需要日志时可显式设置前两项为 1 重新编译；本包附带的二进制关闭全部日志。

哈希、动态定位核对、无日志二进制检查与隔离测试结果见 RELEASE.json、VALIDATION.json 和 validation/。游玩有效性来自用户对 0.6.4-test.1 的反馈；本次 release 未启动游戏或替换已安装插件。
