# Add to Zotero for Windows（加入 Zotero · Windows 版）

> Windows 资源管理器里**右键任意文件 → 加入 Zotero**，把它作为条目加入正在运行的 Zotero，
> 并对 PDF/EPUB **自动抓取元数据**（标题、作者、DOI…）——效果等同拖进 Zotero，但不用切窗口。
> 可选择目标集合。仅适用于 **Windows 10 / 11**。

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D6)
![Zotero](https://img.shields.io/badge/Zotero-7%2B-CC2936)
![License](https://img.shields.io/badge/license-MIT-green)

[English](README.md) · **中文**

<p align="center"><img src="assets/demo.svg" alt="右键菜单与集合选择框" width="620"></p>

<sub>左为右键菜单，右为可搜索的集合选择框。</sub>

## 功能

- **右键 → 加入 Zotero**，支持 PDF、EPUB、DjVu、MOBI、AZW3、CAJ 等本地文件。
- 两个菜单项：
  - **加入 Zotero** —— 加入 Zotero 当前选中的集合（快速，不弹窗）。
  - **加入 Zotero（选择集合）…** —— 弹出可搜索的集合选择框，自己选目标。
- **自动元数据** —— PDF/EPUB 自动识别标题/作者/DOI（与拖拽一致）。
- **多选** —— 选中多个文件，选择框只弹一次，全部归入同一集合。
- **中英双语** —— 自动检测系统语言，可在安装时指定。
- **无需插件 / 浏览器 / 管理员** —— 只写当前用户注册表（`HKCU`）。
- **无需在 Zotero 里开启任何设置** —— 见[工作原理](#工作原理)。

## 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows 10 / 11 |
| Zotero | **7 或更新版本**（已在 9.0.5 / 9.0.6 验证），需保持运行（工具可自动启动） |
| PowerShell | Windows 自带的 Windows PowerShell 5.1 |

## 安装

1. 下载并解压到任意位置——临时文件夹也行（见第 3 步）。
2. 双击 **`Install.bat`**（只写 `HKCU`，免管理员）。它会把运行文件复制到 `%LOCALAPPDATA%\AddToZotero` 并让菜单指向那里。
3. **现在可以删掉下载的文件夹了**——工具从那份副本运行。右键个 PDF 试试。

> 想就地从当前文件夹运行？用 `powershell -ExecutionPolicy Bypass -File Install.ps1 -InPlace`（之后勿移动/删除该文件夹）。

> SmartScreen/杀软提示时：脚本均为纯文本（`.ps1/.vbs/.bat`），可自查；选「仍要运行」。

## 使用

保持 **Zotero 打开**——不开也行：没开时工具会自动启动 Zotero（并弹「正在启动」提示），最多等 60 秒。
右键文件（**Windows 11 先点「显示更多选项」**或按 `Shift`+`F10`）：

- **加入 Zotero** → 进 Zotero 当前选中的集合。
- **加入 Zotero（选择集合）…** → 列出全部可写集合（缩进、默认高亮当前集合），输入可筛选，
  双击或回车确认，`Esc` 取消。

## 语言

自动检测系统语言。强制指定：

```powershell
powershell -ExecutionPolicy Bypass -File Install.ps1 -Language zh   # 或 en
```

## 自定义

```powershell
# 增加文件类型
powershell -ExecutionPolicy Bypass -File Install.ps1 -Extensions '.pdf','.docx','.txt'
# 为「所有文件」加菜单
powershell -ExecutionPolicy Bypass -File Install.ps1 -AllFiles
# 只装快速项，不装「选择集合」项
powershell -ExecutionPolicy Bypass -File Install.ps1 -NoPicker
```

默认扩展名：`.pdf .epub .djvu .mobi .azw3 .caj`。只有 PDF/EPUB 会自动识别元数据；其它类型作为独立附件存入（标题取文件名）。

## 卸载

双击 **`Uninstall.bat`**（在 `%LOCALAPPDATA%\AddToZotero`，或你保留的下载文件夹里）。它会删除菜单项并清理安装副本。

## 工作原理

Zotero 运行时在 `127.0.0.1:23119` 提供**连接器 HTTP 服务**（浏览器插件用的那个）。本工具直接调用：

1. `getSelectedCollection` —— 取集合树（填充选择框）；
2. `saveStandaloneAttachment` —— 上传文件字节（返回 `201`），Zotero 存入并自动识别 PDF/EPUB 元数据；
3. `updateSession` —— 若选了集合，把条目移动过去（返回 `200`）。

**无需在 Zotero 里开启任何设置**：连接器服务随 Zotero 常驻。
（设置里那个「允许其他应用程序与 Zotero 通讯」只控制只读的 `localhost:23119/api/` REST 接口，本工具**不用**它。）
`launch.vbs` 是隐身启动器，右键时不闪黑框。

## 排错

- **右键没菜单？** Win11 在「显示更多选项」里；或先跑 `Install.bat`。
- **`Diagnose.bat`**：报告 Zotero 状态、版本、`supportsAttachmentUpload`、已注册的扩展名。
- **日志** `add-to-zotero.log`：关键行 `TARGET C37 文献`、`OK 论文.pdf`、`DONE ok=1 fail=0`。
- **执行策略被锁**：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。

## 致谢

本仓库由 Anthropic 的 [Claude Code](https://claude.com/claude-code) 智能体 **Claude** 创建与维护，与 **[mak0711](https://github.com/mak0711)** 协作完成。

## 许可

[MIT](LICENSE) © 2026 mak0711
