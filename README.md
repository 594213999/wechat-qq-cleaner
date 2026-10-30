# 微信 / QQ 本机记录清理工具

> 一键清除 Windows 上微信与 QQ 的全部本地记录：聊天记录、图片视频缓存、账号配置、登录状态、安装目录。
>
> 面向 **"电脑要转手 / 送人 / 归还公司"** 场景：先自动遍历全盘定位安装与数据目录，列出清单让你过目，确认后彻底清除并复核残留。

**单文件、零依赖、双击即用** —— 就是一个 `.bat`，拷到 U 盘带到那台电脑上运行即可，不需要安装任何东西。

```
clean-wx-qq.bat
```

---

## 为什么需要它

手动清微信 QQ 很麻烦：

- 聊天记录不在安装目录里，而在 `Documents\WeChat Files`、`Tencent Files`，还可能被你改到 D 盘；
- 微信 3.x 和 4.x 的数据目录名都不一样（`WeChat Files` vs `xwechat_files`）；
- QQ 老版和新版（NT）数据路径不同；
- 每台电脑的安装位置都可能不一样（自定义安装、非 C 盘、绿色版）；
- 还有一堆 AppData 配置、注册表登录信息、卸载残留；
- 电脑上可能有多个 Windows 账户，每个账户都有各自的一份。

只删一个文件夹，往往会漏。这个工具把这些位置一次性全部找出来。

---

## 快速开始

把 `clean-wx-qq.bat` 拷到目标电脑，**右键 → 以管理员身份运行**（会自动请求 UAC 提权）。

```
双击                    先扫描并列出全部发现，再让你选择要做什么（默认，最安全）
clean-wx-qq.bat /scan   只扫描并导出报告到桌面，不删除任何文件  ← 建议第一次先跑这个
clean-wx-qq.bat /auto   全自动彻底清理，不询问（数据+缓存+注册表+安装目录+回收站）
clean-wx-qq.bat /help   查看全部参数
```

### 参数

| 参数 | 说明 |
| --- | --- |
| *(无)* | 交互模式：扫描 → 列出清单 → 你选 [1]清数据 [2]彻底清 [3]只导报告 [Q]退出 |
| `/scan` | 只扫描，导出报告，不删任何东西 |
| `/auto` | 全自动彻底清理（= 菜单的 [2]，跳过所有确认） |
| `/auto /keepprogram` | 全自动但只清数据与缓存，保留程序本体和安装目录 |
| `/shred` | 删除前用随机数据覆写文件（防恢复，很慢，SSD 上效果有限） |
| `/deep` | 全盘深度搜索 `WeChat.exe` / `Weixin.exe` / `QQ.exe`（更全，也更慢） |

> `/auto` 会清空回收站。如果回收站里有你还要的东西，先跑一次不带参数的交互模式，选 [1]。

---

## 它会扫描哪些地方

不是写死路径，而是 6 路交叉定位，互相补充、自动去重：

| 来源 | 覆盖的情况 |
| --- | --- |
| 注册表 `HKLM/HKCU\SOFTWARE\Tencent\*` | 读安装路径与聊天记录保存路径（**包括你改到别的盘的情况**） |
| 卸载信息 `...\CurrentVersion\Uninstall\*` | 解析 `InstallLocation` / `DisplayIcon` |
| 桌面 / 开始菜单 / 任务栏快捷方式 | 解析 `.lnk` 目标，反查安装目录（自定义安装最可靠） |
| 运行中的进程 | 微信/QQ 正开着时，直接取进程路径 |
| 每个 Windows 用户目录 | `Documents`、OneDrive 重定向后的 `Documents`、`AppData\Roaming|Local|LocalLow` |
| 全盘广度优先遍历 | 所有固定磁盘，默认 3 层深度，跳过系统目录（`/deep` 会搜得更深更全） |

识别规则：

- **聊天数据**：目录名是 `WeChat Files`、`xwechat_files`（微信 4.x）、`Tencent Files`
- **安装目录**：目录内实际存在 `WeChat.exe` / `Weixin.exe` / `QQ.exe` / `TIM.exe`
- **配置缓存**：`AppData` / `ProgramData` 下的 `Tencent\WeChat`、`Tencent\xwechat`、`Tencent\QQ`、`Tencent\QQNT` 等

扫描结果会显示每项的**类型、体积、文件数、来源、微信号/QQ 号子目录名**，方便你核对这些确实是你自己的账号。

---

## 它会删什么，不会删什么

**删除**：聊天记录数据库、接收的图片/视频/文件、小程序缓存、账号配置、登录状态、注册表项、失效的卸载条目、（可选）安装目录、回收站。

**绝不触碰**：

- 企业微信 `WXWork`、腾讯会议、WeCom、WeDrive
- QQ音乐、QQ浏览器、QQ影音、QQ输入法、腾讯视频、腾讯文档
- 电脑管家 `QQPCMgr`
- 任何非微信/QQ 的个人文件

> 顺带一提：企业微信的小程序容器进程也叫 `WeChatAppEx.exe`。工具在结束进程时会检查进程路径，落在企业微信目录里的一律跳过，不会误杀。

---

## 安全设计

这个脚本要删文件，所以做了几层硬校验：

1. **路径白名单**：只允许删除末端目录名命中 `WeChat Files` / `xwechat_files` / `Tencent Files` / `WeChat` / `xwechat` / `QQ` / `QQNT` 等白名单的目录；
2. **黑名单拦截**：`C:\Users`、`Documents`、`AppData`、`Program Files`、`ProgramData`、`Tencent`、盘根等一律拒绝，即使逻辑出错也删不了；
3. **安装目录二次验证**：只有在目录里当场找到对应 `.exe` 才允许删除；
4. **二次确认**：交互模式下必须手动输入 `YES` 才会执行；
5. **删前先列清单**：所有目标先完整展示（含体积和来源），再动手；
6. **删后复核**：结束时会重新检查每个目标是否还存在，被占用的会明确列出来，提示重启后再跑一次。

每次运行都会在桌面留下完整日志（`微信QQ清理_时间戳.log`），方便事后核对到底删了什么。

---

## 结束进程说明

删除前会自动结束微信 / QQ 相关进程（否则文件被占用删不掉）：`WeChat`、`Weixin`、`QQ`、`TIM`、`QQProtect`、`QQScLauncher` 等。
`WeChatAppEx`、`WeChatPlayer`、`WeChatBrowser` 这些名字不独占的进程，会先检查路径，属于企业微信的一律跳过，并在日志里标明。

---

## 转手电脑前的几条建议

1. **手机上解绑**：微信「设置 → 账号安全 → 登录设备管理」、QQ「设置 → 账号安全 → 登录设备管理」，把这台电脑删掉。这比删本地文件更关键 —— 否则对方理论上仍可能看到登录态残留。
2. **删除 ≠ 不可恢复**：`/shred` 只做单遍覆写，**SSD 上仍有残留可能**（磨损均衡会让覆写落到别的物理块）。如果对方是陌生人或数据敏感，最稳的做法是交接前**重装系统**，或开启 BitLocker 加密后格式化。
3. **顺手清理**：浏览器保存的账号密码、邮箱客户端、输入法词库、下载目录、剪贴板历史、最近打开的文件记录。
4. 清完建议**重启一次**再检查一遍（部分被占用的文件要重启后才能删干净）。

---

## 环境要求

- Windows 10 / 11（Windows PowerShell 5.1，系统自带，无需安装）
- 建议管理员权限（要扫描其它用户目录、删除 `Program Files` 下的安装目录）
- 脚本全程只在**本机固定磁盘**上工作，不会访问网络、不会上传任何数据

---

## 它是怎么实现的

`clean-wx-qq.bat` 是**单文件自包含**的：

- 上半部分（纯 ASCII 的批处理）负责提权、把自己内部的一段 PowerShell 代码提取到临时文件；
- 下半部分（`#===PS-BEGIN===` 到 `#===PS-END===` 之间）是真正干活的 PowerShell 引擎；
- 运行结束自动删除临时文件。

所以你只需要分发一个 `.bat`，不用额外带 `.ps1`，也不会被杀软误判成"释放文件的加载器"（源码全部明文可读，就在你双击的那个文件里）。

---

## English summary

A single-file Windows batch utility that wipes **all local WeChat / QQ data** (chat history, media cache, account config, login state, registry entries, optionally the install directory) — built for the "I'm handing this PC to someone else" scenario.

It **scans the whole machine first** (registry, uninstall entries, shortcuts, running processes, every user profile, then a full-disk breadth-first walk) to locate both the install and data directories, shows you the complete list with sizes, and only then deletes — with a strict path whitelist, post-delete verification and a full log.

```
clean-wx-qq.bat            # interactive (recommended)
clean-wx-qq.bat /scan      # scan only, delete nothing
clean-wx-qq.bat /auto      # fully automatic deep clean
```

Requires Windows 10/11 + admin rights. No dependencies, no network access.

---

## 免责声明

本工具会**不可逆地删除文件**。请在使用前用 `/scan` 确认清单，并确保你的聊天记录在手机端仍然完整（本地删除不影响手机/服务器）。

作者不对因误用造成的数据丢失负责 —— 请先跑一遍只扫描模式，看清楚它要删什么。

## License

[MIT](LICENSE)
