# 更新日志

## v1.0.7 (2026-06-30)：自动更新目标验证版

### 验证

* 用于验证 1.0.6 到 1.0.7 的桌面端自动更新替换和重启链路。

## v1.0.6 (2026-06-30)：macOS 自动更新修复基线版

### 问题修复

* 修复 macOS 沙盒包缺少 Sparkle 安装服务配置，导致下载完成后无法替换并重启的问题。
* 修复 macOS 更新退出时可能被托盘关闭到后台逻辑拦截的问题。

### 发布流程

* 串行化 release workflow，确保连续发版时更新元数据按版本顺序写入。

## v1.0.5 (2026-06-30)：自动更新目标版

### 验证

* 用于验证 1.0.4 到 1.0.5 的桌面端自动更新链路。

## v1.0.4 (2026-06-30)：自动更新安装版

### 验证

* 修复 macOS Sparkle 更新包签名流程。
* 用于安装后验证后续 1.0.5 自动更新提示。

## v1.0.3 (2026-06-30)：自动更新目标版

### 验证

* 用于验证 1.0.2 到 1.0.3 的桌面端自动更新链路。

## v1.0.2 (2026-06-30)：自动更新验证版

### 功能新增

* 支持 macOS 和 Windows 桌面端原生自动更新。
* 新增关于页面手动检查更新入口。

### 发布流程

* 发布流程会生成 Sparkle appcast 和旧版 JSON 更新元数据。
* 发布资产会使用已配置的 macOS EdDSA 与 Windows DSA 密钥签名。

## v1.0.1 (2026-06-26)

### 界面优化

* 将设置图标更换为轮廓风格齿轮图标。
* 优化模型选择页面; 支持按提供商分组展示模型。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 设置关于页面新增QQ群联系方式。([#20](https://github.com/Radiant303/SpringNote/issues/20); 感谢 [Radiant303](https://github.com/Radiant303))


### 功能新增

* 支持自定义日报整理提示词。([#7](https://github.com/Radiant303/SpringNote/issues/7); 感谢 [Radiant303](https://github.com/Radiant303))
* 支持 OpenAI /responses API。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 支持自定义配置文件存储目录。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 新增默认模型配置功能。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 新增附件的文件路径上传功能。([#21](https://github.com/Radiant303/SpringNote/pull/21); 感谢 [lxfight](https://github.com/lxfight))
* 新增组件圆球化样式及记忆组件位置功能。([#27](https://github.com/Radiant303/SpringNote/pull/27); 感谢 [lxfight](https://github.com/lxfight))
* 新增回忆书检索结果最大字符数配置([#29](https://github.com/Radiant303/SpringNote/issues/29); 感谢 [Radiant303](https://github.com/Radiant303))

### 问题修复

* 修复切换日期时日期选择器按钮闪烁的问题。([#6](https://github.com/Radiant303/SpringNote/issues/6); 感谢 [Radiant303](https://github.com/Radiant303))
* 修复日报内容底部显示被截断的问题。([#12](https://github.com/Radiant303/SpringNote/issues/12); 感谢 [Radiant303](https://github.com/Radiant303))
* 修复启用 max 推理强度参数后 GPT 请求异常的问题。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 修复模型选择列表中的冲突问题。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 修复打开便签日报页面无法自动生成日报的问题([#28](https://github.com/Radiant303/SpringNote/issues/28); [Radiant303](https://github.com/Radiant303))

### 平台支持

* 新增Mac端支持。([#21](https://github.com/Radiant303/SpringNote/issues/21); 感谢 [lxfight](https://github.com/lxfight))

## v1.0.0 (2026-06-21)

- 实现了更新功能
- 优化了软件默认图标
- 正式版发布
