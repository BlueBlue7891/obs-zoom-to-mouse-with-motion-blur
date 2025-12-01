# OBS 鼠标缩放与运动模糊

一个增强版的OBS Lua脚本，可以将显示捕获源缩放到鼠标光标位置——现在增加了可配置的运动模糊，实现平滑、电影般的过渡效果。

## 🚀 功能特性

- **鼠标缩放**：自动将显示捕获源缩放到鼠标光标位置
- **运动模糊控制**：在缩放和平移过程中添加可配置的运动模糊
- **方向性模糊**：运动模糊方向与移动向量匹配
- **热键支持**：使用自定义热键切换缩放和跟随功能
- **平滑动画**：可自定义缩放速度和跟随灵敏度
- **灵活设置**：支持各种显示捕获源

## 📋 系统要求

- OBS Studio 30.0 或更高版本
- 启用Lua脚本支持（默认启用）
- 一个用于应用缩放的显示捕获源

## 🛠️ 安装方法

1. 下载 `obs-zoom-to-mouse-motion-blur.lua` 脚本文件
2. 将其放入OBS脚本文件夹：
   - Windows: `C:\Program Files\obs-studio\data\obs-plugins\frontend-tools\scripts`
3. 重启OBS Studio
4. 进入 工具 → 脚本 添加脚本
5. 在脚本属性中配置源和设置

## ⚙️ 配置说明

### 基础设置
- **缩放源**：选择要缩放的显示捕获源
- **缩放倍数**：缩放的倍数（例如，2 = 2倍缩放）
- **缩放速度**：缩放动画的执行速度
- **自动跟随鼠标**：缩放后是否自动跟随鼠标

### 跟随设置
- **跟随速度**：缩放跟随鼠标的速度
- **跟随边界**：触发跟随的缩放窗口边缘百分比
- **锁定灵敏度**：何时锁定缩放中心（启用自动锁定时）
- **边界外跟随**：鼠标在源边界外时是否跟随

### 运动模糊设置
- **启用运动模糊**：切换运动模糊控制
- **模糊滤镜名称**：源上的模糊滤镜名称（例如，"Composite Blur"）
- **模糊参数名称**：要控制的参数（例如，"radius"、"Size"、"kawase_passes"）
- **模糊强度**：运动模糊强度的倍数
- **启用方向性模糊**：应用与移动向量匹配的模糊方向（需要兼容的模糊滤镜）
- **模糊角度参数名称**：模糊方向的参数名称（例如，"angle"）

## 🔧 设置运动模糊

使用运动模糊功能：

1. **安装Composite Blur插件**：
   - 下载地址：https://github.com/finitesingularity/obs-composite-blur/
   - 按照仓库中的说明安装插件
   - 重启OBS Studio

2. **为源添加Composite Blur滤镜**：
   - 在源面板中右键点击显示捕获源
   - 选择"滤镜"
   - 点击"+"按钮并添加"Composite Blur"
   - 配置模糊滤镜设置（参见图片：composite_blur_settings.png）
   
   ![Composite Blur设置](https://github.com/BlueBlue7891/obs-zoom-to-mouse-with-motion-blur/blob/main/composite_blur_settings.png)

3. **配置脚本**：
   - 在脚本设置中，启用"启用运动模糊"
   - 脚本预配置了与Composite Blur兼容的默认参数
   - 根据需要调整"模糊强度"（建议：0.1 - 0.3，更高值可能导致性能问题）
   - 参见图片：script_settings.png 作为参考配置
     
   ![脚本设置](https://github.com/BlueBlue7891/obs-zoom-to-mouse-with-motion-blur/blob/main/script_settings.png)

## 🎮 热键功能

- **切换缩放**：切换缩放的开启/关闭
- **切换跟随**：切换鼠标跟随（缩放时）

## 📖 工作原理

脚本的工作方式：
1. 为源添加裁剪滤镜以创建缩放效果
2. 根据鼠标位置动态调整裁剪滤镜
3. 可选择根据移动速度控制模糊滤镜
4. 可选择应用与移动方向匹配的方向性模糊

## 🔄 更新内容

此脚本是 [BlankSourceCode/obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) 的分支，具有以下增强功能：
- 添加了运动模糊控制功能
- 添加了方向性模糊支持
- 修复了 `obs_property_get_group_properties` 兼容性问题
- 改进了缩放动画计时

## 🧪 测试环境

此脚本已在 **OBS Studio 32.0.2** 上开发和测试。虽然它应该在其他版本上也能工作，但OBS 32.0.2是确认正常工作的环境。

## 🐛 故障排除

### 常见问题：

1. **脚本无法加载**：检查是否使用兼容的OBS版本
2. **模糊不工作**：验证模糊滤镜名称和参数名称是否完全匹配
3. **缩放不跟随鼠标**：确保源在当前场景中且监视器信息正确
4. **性能问题**：降低缩放倍数或使用更简单的模糊滤镜

### 调试日志：

在脚本设置中启用"启用调试日志记录"以在OBS的脚本控制台中查看详细日志。

## 🤝 贡献

欢迎提交Pull Request！对于重大更改，请先开Issue讨论您想要更改的内容。

## 📄 许可证

此项目根据MIT许可证授权 - 详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- 原脚本作者 [BlankSourceCode](https://github.com/BlankSourceCode)
- Composite Blur插件作者 [finitesingularity](https://github.com/finitesingularity/obs-composite-blur/)
- FFI鼠标位置代码改编自各种OBS社区脚本
- 运动模糊概念受专业视频编辑软件启发

## 🌐 Language
- [English Documentation](README.md)



