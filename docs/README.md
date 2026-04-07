# DFU-Tools

`DFU-Tools` 是一个面向 macOS 的桌面工具，用于辅助 Apple Silicon、T2 以及部分 iPhone、iPad 设备进行 DFU、重启、恢复和修复操作。

![main](main.png)

## 功能

- 自动识别并显示已连接设备
- 支持 `DFU`、`Reboot`、`Restore`、`Revive`
- 支持手动选择 IPSW 文件
- 支持中英文界面
- 提供日志输出

## 适用设备

- Apple Silicon Mac
- T2 Mac
- 部分 iPhone / iPad

## 运行要求

- macOS 11.0 或更高版本
- 建议在 Apple Silicon Mac 上运行
- 本机已安装 `Apple Configurator`
- `DFU` / `Reboot` 需要管理员权限
- `Restore` / `Revive` 需要本机已安装 `Apple Configurator`

## 使用方法

1. 打开 `DFU-Tools`
2. 连接设备并等待设备出现在列表中
3. 选择需要的操作：`DFU`、`Reboot`、`Restore` 或 `Revive`
4. 如需刷写固件，按提示选择 IPSW 文件

## 说明

- 应用会自动保存常用配置
- 执行过程中可查看日志输出
- 如果设备没有显示，先检查线材、接口和 `Apple Configurator` 是否正常可用

### 已损坏 打不开 / Can't open

```bash
sudo xattr -rd com.apple.quarantine /Applications/DFU-Tools.app
```
