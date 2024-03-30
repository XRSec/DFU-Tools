## macOS DFU Tools

### 必读 / Must read
> 本项目是一个macOS下的DFU工具，用于快速进入DFU模式、快速重启以及进入Recovery模式(尚未测试)。
> 
> This project is a DFU tool under mac OS for fast entry into DFU mode, fast restart, and entry into Recovery mode (not yet tested).
> 
> 依赖于 / depend on [AsahiLinux/macvdmtool](https://github.com/AsahiLinux/macvdmtool)
> 
> **(Apple -> Apple || Intel -> Intel)** by Apple: 400-666-8800

### 下载 / Download

> [Github Release](https://github.com/XRSec/DFU-Tools/releases)
> 
> [镜像加速(Inter 1.1.9)](https://mirror.ghproxy.com/https://github.com/XRSec/DFU-Tools/releases/download/1.1.9/DFU-Tools_x64.dmg)
> 
> [镜像加速(Apple 1.1.9)](https://mirror.ghproxy.com/https://github.com/XRSec/DFU-Tools/releases/download/1.1.9/DFU-Tools_arm64.dmg)

### 使用 / Usage

![dashboard](./dashboard_en.png)
![dashboard](./dashboard.png)

## 报错汇总 / FAQ

### 已损坏 打不开 / Can't open

```bash
sudo xattr -rd com.apple.quarantine /Applications/DFU-Tools.app
```
