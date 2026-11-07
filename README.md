# NTEDesktopMode 0.6.2 正式版

适用于《异环》iOS 1.5.0，通过反射方式加载控制地址，移除了固定的地址映射，在 PlayCover 中启用原生桌面输入。

正式版默认关闭插件自身的文件日志和标准错误输出。

## 你需要做什么

只需要下载libNTEDesktopMode.dylib文件，同时安装最新版Playcover。选择异环设置-杂项-添加插件-选择下载的dylib文件，同时关闭所有Playcover键盘映射。然后进去游戏即可使用桌面版键鼠操作。

## 开发文档

完整设计见 [原理与维护指南](../playcoverNTEDesktopMode/NTEDesktopMode：原理与维护指南（ 0.5.5 正式版）.md)。

## 构建与调试

正式版：

```sh
zsh build.sh
```

需要恢复诊断输出时，重新构建：

```sh
NTE_ENABLE_LOGGING=1 zsh build.sh
```

编译开关 `NTE_ENABLE_LOGGING` 默认值为 `0`，也在源码中提供默认值。日志实现、调用点和诊断代码均保留在 `src/` 中。启用后继续使用原有的 `Documents/NTEDesktopMode/plugin.log` 路径与轮转规则。

本次发布只调整版本标识和日志开关，不更改平台识别、键位、UI、地图输入或鼠标捕获/释放策略。保持原有主程序 UUID 和指令签名检查。

## 已知问题

### 进入游戏闪退或者出现提示无法获取有效服务器：

见https://macgaming-m.pages.dev/games/neverness-to-everness修复方式

### 桌面版UI无按键提示：

目前判断是相关资源缺失，暂无修复方案，键位可以参考PC版本
