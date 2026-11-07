# NTEDesktopMode 0.6.2 release

在 PlayCover 中启用《异环》已有的原生键鼠和桌面 UI。本构建关闭诊断日志，供游戏内测试。

## 使用

完全退出游戏，用 `libNTEDesktopMode.dylib` 替换旧版，只保留一份插件，保持 PlayCover 键位映射关闭。先检查按钮能否完成按下、松开并触发功能，再检查键盘、Esc/Option 和地图拖动、缩放。

启动时会同步解析主程序，可能增加数秒加载时间。原生输入初始化首次维护任务约延迟 0.25 秒，初始化期间每秒重试，就绪后恢复三秒周期。游戏内测试由用户完成。

## 0.6.2 原生通道调整

- 启动时固定 UIKit 原生间接指针能力，由游戏现有的 type=3 分支过滤鼠标触摸副本。
- 动态查找并关闭原生 `bUseMouseForTouch` 配置，只修改该配置位，不保存配置文件。
- 不过滤或改写传给游戏的触摸集合，不补发释放事件，不修改按钮按下状态。
- release 不包装或替换 GameController 的键盘、鼠标硬件回调。
- 保留地图拖动的原生光标坐标适配，修正 hover 结束时过早丢弃坐标的问题。
- 保留 0.6.1 的 C++ 初始化顺序修复，以及 0.6.0 的动态地址解析。

分析、证据和验证边界见 `REGRESSION-0.6.2.md`。0.6.1 文档记录的是历史方案，其延迟切换输入策略已被本版替换。

## 动态定位与兼容范围

平台查询使用反射名称、调用关系及操作形状定位；Objective-C 方法使用类名、selector、类型编码定位；原生对象和配置在操作前核对布局。不使用游戏 UUID 或版本号白名单。UUID 只核对被解析的文件与当前进程一致。

同一解析器在本地 1.4.0/build 0.0.27 与 1.5.0/build 0.0.46 上均通过静态核对，包括原生触摸过滤和鼠标模拟触摸配置。静态与隔离检查不能代替游戏内测试。未来引擎布局、编译方式或输入架构改变时仍可能需要维护。

## 构建与验证

```sh
zsh build.sh
zsh tests/run.sh
```

日志默认 `NTE_ENABLE_LOGGING=0`；只有开发者显式使用 `NTE_ENABLE_LOGGING=1 zsh build.sh` 才生成诊断构建。

静态解析指定主程序，不执行游戏：

```sh
xcrun clang++ -std=c++17 -O2 tests/resolver_checks.cpp -o /tmp/nte-resolver-checks
/tmp/nte-resolver-checks /path/to/HTGame-IOS-Shipping
```

产物哈希与检查结果见 `VALIDATION.json`。
