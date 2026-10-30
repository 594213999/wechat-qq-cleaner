@echo off
setlocal EnableExtensions DisableDelayedExpansion
title WeChat / QQ Local Data Cleaner
chcp 65001 >nul 2>&1

rem =====================================================================
rem  WeChat / QQ local data cleaner  ---  launcher only
rem  The real logic is the embedded PowerShell block at the bottom,
rem  between the PS-BEGIN / PS-END markers.
rem  This batch part is pure ASCII on purpose (code page safe);
rem  every Chinese message comes from the PowerShell part.
rem =====================================================================

rem ---- 1. require administrator (needed to scan/clean every user profile) ----
fltmc >nul 2>&1
if errorlevel 1 (
    echo.
    echo [INFO] Administrator privileges required - relaunching elevated ...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$a = '%*'; if ([string]::IsNullOrWhiteSpace($a)) { Start-Process -FilePath '%~f0' -Verb RunAs } else { Start-Process -FilePath '%~f0' -ArgumentList $a -Verb RunAs }"
    exit /b
)

rem ---- 2. forward command line switches through an environment variable ----
set "WXQQ_ARGS=%*"
set "WXQQ_PS1=%TEMP%\wxqq_clean_%RANDOM%%RANDOM%.ps1"
if exist "%WXQQ_PS1%" del /f /q "%WXQQ_PS1%" >nul 2>&1

rem ---- 3. extract the embedded PowerShell script and run it ----
rem  NOTE: the marker strings below are split ('#===PS' + '-BEGIN===') so that
rem  this very command line never contains a complete marker.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = [IO.File]::ReadAllText('%~f0', [Text.Encoding]::UTF8); $b = '#===PS' + '-BEGIN==='; $e = '#===PS' + '-END==='; $i = $t.IndexOf($b); $j = $t.IndexOf($e); if ($i -lt 0 -or $j -le $i) { Write-Host '[ERROR] embedded PowerShell block not found.' -ForegroundColor Red; exit 2 }; [IO.File]::WriteAllText($env:WXQQ_PS1, $t.Substring($i + $b.Length, $j - $i - $b.Length), (New-Object System.Text.UTF8Encoding($true)))"
if errorlevel 1 goto :fail

powershell -NoProfile -ExecutionPolicy Bypass -File "%WXQQ_PS1%"
set "WXQQ_RC=%ERRORLEVEL%"

if exist "%WXQQ_PS1%" del /f /q "%WXQQ_PS1%" >nul 2>&1

echo.
echo [DONE] exit code = %WXQQ_RC%
pause
exit /b %WXQQ_RC%

:fail
echo.
echo [ERROR] Failed to prepare the embedded PowerShell script.
pause
exit /b 2

exit /b

#===PS-BEGIN===
# =====================================================================
#  微信 / QQ 本机记录全量清理引擎
#  由 clean-wx-qq.bat 从自身文件内嵌段提取后以 PowerShell 执行
#  兼容 Windows PowerShell 5.1
# =====================================================================

# ---------------------------------------------------------------- 控制台
try { chcp.com 65001 | Out-Null } catch { }
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding           = [Text.UTF8Encoding]::new($false)
} catch { }

# 本工具大量做"探测不存在 / 无权限"的路径，PowerShell 默认会刷一屏红字。
# 统一静默非关键错误；所有真正关键的操作（Remove-Item / Stop-Process /
# Clear-RecycleBin 等）都已显式写上 -ErrorAction Stop，不会因此漏报失败。
$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- 选项
$script:OptAuto        = $false   # 全自动：扫描后直接彻底清理，不再询问
$script:OptScanOnly    = $false   # 只扫描，不删除
$script:OptKeepProgram = $false   # 保留安装目录
$script:OptShred       = $false   # 删除前覆写文件内容（慢，防恢复）
$script:OptDeepScan    = $false   # 全盘深度搜索 exe（慢，更全）
$script:OptHelp        = $false
$script:OptMaxDepth    = 3        # 全盘目录遍历深度
$script:OptLogPath     = ''       # 指定日志文件

# ---------------------------------------------------------------- 常量
$script:ExeNames       = @('WeChat.exe', 'Weixin.exe', 'QQ.exe', 'TIM.exe')
$script:DataDirNames   = @('WeChat Files', 'xwechat_files', 'Tencent Files')
$script:ConfigDirNames = @('WeChat', 'xwechat', 'WeChatAppEx', 'QQ', 'QQNT', 'QQ2009')
$script:ProcNames      = @(
    'WeChat', 'Weixin', 'WeChatAppEx', 'WeChatPlayer', 'WeChatBrowser',
    'QQ', 'QQNT', 'TIM', 'QQProtect', 'QQScLauncher', 'QQExternal', 'TXPlatform'
)
$script:Items   = New-Object 'System.Collections.Generic.List[object]'
$script:LogText = New-Object 'System.Collections.Generic.List[string]'

# =====================================================================
#  基础辅助
# =====================================================================
function Write-Log {
    param([string]$Text = '', [string]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    $script:LogText.Add($Text)
}

function Write-Section {
    param([string]$Text)
    Write-Log ''
    Write-Log ('  ' + ('-' * 66)) 'DarkCyan'
    Write-Log ('  ' + $Text) 'Cyan'
    Write-Log ('  ' + ('-' * 66)) 'DarkCyan'
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ("$Bytes B")
}

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-FixedDrives {
    $list = New-Object 'System.Collections.Generic.List[string]'
    $ok = $false
    try {
        foreach ($d in (Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
            if ($d.DeviceID) { $list.Add($d.DeviceID); $ok = $true }
        }
    } catch { }
    if (-not $ok) {
        foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if ($d.Root -match '^[A-Za-z]:\\$') { $list.Add($d.Root.TrimEnd('\')) }
        }
    }
    return $list
}

function Get-UserProfiles {
    $list = New-Object 'System.Collections.Generic.List[string]'
    $plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    if (Test-Path -LiteralPath $plKey) {
        foreach ($sub in (Get-ChildItem -LiteralPath $plKey -ErrorAction SilentlyContinue)) {
            $p = [string](Get-ItemProperty -LiteralPath $sub.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
            if ($p -and (Test-Path -LiteralPath $p -PathType Container)) {
                if ($list -notcontains $p) { $list.Add($p) }
            }
        }
    }
    $usersDir = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersDir) {
        foreach ($d in (Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Name -match '^(Public|Default|Default User|All Users|defaultuser0)$') { continue }
            if ($list -notcontains $d.FullName) { $list.Add($d.FullName) }
        }
    }
    return $list
}

function Get-DocFolders {
    param([string]$Profile)
    $c = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in @('Documents', '文档')) {
        $p = Join-Path $Profile $n
        if ((Test-Path -LiteralPath $p -PathType Container) -and ($c -notcontains $p)) { $c.Add($p) }
    }
    foreach ($d in (Get-ChildItem -LiteralPath $Profile -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'OneDrive*' })) {
        foreach ($n in @('Documents', '文档')) {
            $p = Join-Path $d.FullName $n
            if ((Test-Path -LiteralPath $p -PathType Container) -and ($c -notcontains $p)) { $c.Add($p) }
        }
    }
    return $c
}

# 判断一个已存在的目录属于哪一类：Data / Config / Install / $null
function Get-ItemKindForPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $leaf = [IO.Path]::GetFileName($Path.TrimEnd('\'))
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }

    foreach ($e in $script:ExeNames) {
        if ([IO.File]::Exists((Join-Path $Path $e))) { return 'Install' }
    }
    if ($script:DataDirNames -contains $leaf) { return 'Data' }
    $low = $Path.ToLower()
    if (($low -like '*\appdata\*') -or ($low -like '*\programdata\*')) {
        if ($script:ConfigDirNames -contains $leaf) { return 'Config' }
    }
    return $null
}

function Add-Item {
    param(
        [ValidateSet('Data', 'Config', 'Install')][string]$Kind,
        [string]$Path,
        [string]$Source
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if ([string]::IsNullOrWhiteSpace($Source)) { $Source = '自动发现' }
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { return }
    $full = $null
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return }
    if ($full -notmatch '^[A-Za-z]:\\') { return }
    if ($full.Length -le 3) { return }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }

    foreach ($it in $script:Items) {
        if ($it.Path -ieq $full) {
            if ($it.Source -notlike "*$Source*") { $it.Source = $it.Source + '; ' + $Source }
            return
        }
    }
    $script:Items.Add([PSCustomObject]@{
        Kind   = $Kind
        Path   = $full
        Source = $Source
        Bytes  = [long]0
        Files  = [long]0
    })
}

function Measure-TreeSize {
    param([string]$Path)
    $sum = [long]0
    $cnt = [long]0
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try { $sum += ([IO.FileInfo]::new($f)).Length; $cnt++ } catch { }
        }
    } catch { }
    return [PSCustomObject]@{ Bytes = $sum; Files = $cnt }
}

function Get-DirsRecursive {
    param([string]$Path, [int]$Level)
    $out = New-Object 'System.Collections.Generic.List[string]'
    if ($Level -le 0) { return $out }
    try {
        foreach ($d in [IO.Directory]::EnumerateDirectories($Path)) {
            $out.Add($d)
            foreach ($c in (Get-DirsRecursive -Path $d -Level ($Level - 1))) { $out.Add($c) }
        }
    } catch { }
    return $out
}

# =====================================================================
#  扫描器
# =====================================================================
# 1) 注册表：Tencent 下的 WeChat / xwechat / QQ / QQNT / QQ2009
function Scan-Registry {
    $roots = @('HKLM:\SOFTWARE\Tencent', 'HKLM:\SOFTWARE\WOW6432Node\Tencent', 'HKCU:\SOFTWARE\Tencent')
    $names = @('WeChat', 'xwechat', 'Weixin', 'QQ', 'QQNT', 'QQ2009', 'TIM')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sub in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            if ($names -notcontains $sub.PSChildName) { continue }
            $props = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                $v = $p.Value
                if ($v -isnot [string]) { continue }
                $v = $v.Trim().Trim('"')
                if ($v -notmatch '^[A-Za-z]:[\\/]') { continue }
                $v = [Environment]::ExpandEnvironmentVariables($v)
                if (-not (Test-Path -LiteralPath $v -PathType Container)) { continue }
                $kind = Get-ItemKindForPath $v
                if ($kind) { Add-Item -Kind $kind -Path $v -Source ("注册表 " + $sub.PSChildName + "." + $p.Name) }
            }
        }
    }
}

# 2) 卸载信息：DisplayName / InstallLocation / DisplayIcon
function Scan-Uninstall {
    $exclude = 'QQ音乐|QQMusic|QQ浏览器|QQBrowser|QQ影音|QQPlayer|QQ拼音|QQPinyin|QQ五笔|输入法|腾讯会议|Tencent Meeting|企业微信|WeCom|WXWork|QQ游戏|QQGame|电脑管家|PCMgr|腾讯文档|Tencent Docs|腾讯视频|QQLive|TencentVideo|微信读书|WeRead|微信输入法|WeChat Input|腾讯微云|Weiyun|微信开发者工具|WeChat DevTools'
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sub in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $dn = [string]$props.DisplayName
            if ([string]::IsNullOrWhiteSpace($dn)) { continue }
            if ($dn -match $exclude) { continue }
            if ($dn -notmatch '微信|WeChat|Weixin|QQ|TIM|Tencent QQ') { continue }
            foreach ($field in @('InstallLocation', 'DisplayIcon', 'UninstallString')) {
                $v = [string]$props.$field
                if ([string]::IsNullOrWhiteSpace($v)) { continue }
                $v = $v.Trim()
                if ($v.StartsWith('"')) { $v = ($v -split '"')[1] } else { $v = ($v -split '"')[0] }
                $v = ($v -split ',')[0].Trim()
                if ($v -notmatch '^[A-Za-z]:[\\/]') { continue }
                if (-not (Test-Path -LiteralPath $v)) { continue }
                if (Test-Path -LiteralPath $v -PathType Leaf) { $v = Split-Path -Parent $v }
                $kind = Get-ItemKindForPath $v
                if ($kind) { Add-Item -Kind $kind -Path $v -Source ("卸载信息 " + $dn) }
            }
        }
    }
}

# 3) 快捷方式：桌面 / 开始菜单 / 任务栏 → 反查安装目录
function Scan-Shortcuts {
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return }
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    foreach ($prof in (Get-UserProfiles)) {
        foreach ($n in @('Desktop', '桌面')) {
            $d = Join-Path $prof $n
            if ((Test-Path -LiteralPath $d -PathType Container) -and ($dirs -notcontains $d)) { $dirs.Add($d) }
        }
        foreach ($n in @('AppData\Roaming\Microsoft\Windows\Start Menu\Programs',
                         'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')) {
            $d = Join-Path $prof $n
            if ((Test-Path -LiteralPath $d -PathType Container) -and ($dirs -notcontains $d)) { $dirs.Add($d) }
        }
    }
    foreach ($n in @('Microsoft\Windows\Start Menu\Programs')) {
        $d = Join-Path $env:ProgramData $n
        if ((Test-Path -LiteralPath $d -PathType Container) -and ($dirs -notcontains $d)) { $dirs.Add($d) }
    }

    try {
        foreach ($d in $dirs) {
            $files = @()
            try { $files = Get-ChildItem -LiteralPath $d -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue } catch { continue }
            foreach ($f in $files) {
                $target = $null
                try { $target = $shell.CreateShortcut($f.FullName).TargetPath } catch { continue }
                if ([string]::IsNullOrWhiteSpace($target)) { continue }
                $exe = [IO.Path]::GetFileName($target)
                if ($script:ExeNames -notcontains $exe) { continue }
                $dir = Split-Path -Parent $target
                $kind = Get-ItemKindForPath $dir
                if ($kind) { Add-Item -Kind $kind -Path $dir -Source ("快捷方式 " + $f.Name) }
            }
        }
    } finally {
        if ($shell) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { } }
    }
}

# 4) 正在运行的进程 → 安装目录
function Scan-Processes {
    foreach ($n in $script:ProcNames) {
        foreach ($proc in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $path = $null
            try { $path = $proc.Path } catch { }
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $dir = Split-Path -Parent $path
            $kind = Get-ItemKindForPath $dir
            if ($kind) { Add-Item -Kind $kind -Path $dir -Source ("运行中进程 " + $proc.ProcessName) }
        }
    }
}

# 5) 已知固定位置（每个用户 profile）
function Scan-KnownPaths {
    foreach ($prof in (Get-UserProfiles)) {
        $uname = [IO.Path]::GetFileName($prof)
        foreach ($doc in (Get-DocFolders $prof)) {
            foreach ($n in $script:DataDirNames) {
                $p = Join-Path $doc $n
                if (Test-Path -LiteralPath $p -PathType Container) {
                    Add-Item -Kind 'Data' -Path $p -Source ("用户目录 " + $uname)
                }
            }
        }
        $appRoots = @(
            (Join-Path $prof 'AppData\Roaming'),
            (Join-Path $prof 'AppData\Local'),
            (Join-Path $prof 'AppData\LocalLow')
        )
        $relPaths = @(
            'Tencent\WeChat', 'Tencent\xwechat', 'Tencent\WeChatAppEx', 'Tencent\QQ',
            'Tencent\QQNT', 'Tencent\QQ2009', 'QQ', 'QQNT', 'xwechat', 'WeChat'
        )
        foreach ($ar in $appRoots) {
            foreach ($rel in $relPaths) {
                $p = Join-Path $ar $rel
                if (Test-Path -LiteralPath $p -PathType Container) {
                    $kind = Get-ItemKindForPath $p
                    if ($kind) { Add-Item -Kind $kind -Path $p -Source ("用户目录 " + $uname) }
                }
            }
        }
    }
    foreach ($rel in @('Tencent\WeChat', 'Tencent\xwechat', 'Tencent\QQ', 'Tencent\QQNT')) {
        $p = Join-Path $env:ProgramData $rel
        if (Test-Path -LiteralPath $p -PathType Container) {
            Add-Item -Kind 'Config' -Path $p -Source 'ProgramData'
        }
    }
}

# 6) 常见安装位置（Program Files / 各盘常见目录，深度 2）
function Scan-CommonInstallDirs {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in @('ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432')) {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v -and (Test-Path -LiteralPath $v -PathType Container) -and ($roots -notcontains $v)) { $roots.Add($v) }
    }
    foreach ($d in (Get-FixedDrives)) {
        foreach ($n in @('Program Files', 'Program Files (x86)', 'Programs', 'Apps', 'Software', 'Tools', 'Tencent')) {
            $p = Join-Path $d $n
            if ((Test-Path -LiteralPath $p -PathType Container) -and ($roots -notcontains $p)) { $roots.Add($p) }
        }
    }
    foreach ($r in $roots) {
        $cands = @($r)
        foreach ($c in (Get-DirsRecursive -Path $r -Level 2)) { $cands += $c }
        foreach ($c in $cands) {
            $kind = Get-ItemKindForPath $c
            if ($kind -eq 'Install') { Add-Item -Kind 'Install' -Path $c -Source '常见安装位置' }
        }
    }
}

# 7) 全盘遍历（广度优先，限制深度，跳过系统目录）
function Scan-Drives {
    $skip = @(
        '$Recycle.Bin', 'System Volume Information', 'Windows', 'WinSxS', 'System32', 'SysWOW64',
        'Recovery', 'PerfLogs', 'Config.Msi', 'MSOCache', 'WindowsApps', 'Windows.old',
        '.git', '.hg', '.svn', 'node_modules', '.gradle', '.m2', '.nuget', '.conda', '.cargo',
        'Installer', 'SoftwareDistribution', 'DriverStore', 'assembly', 'servicing', '$WinREAgent'
    )
    foreach ($drv in (Get-FixedDrives)) {
        $rootPath = $drv + '\'
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        $queue = New-Object 'System.Collections.Generic.Queue[object]'
        $queue.Enqueue([PSCustomObject]@{ Path = $rootPath; Level = 0 })
        $visited = 0
        while ($queue.Count -gt 0) {
            $cur = $queue.Dequeue()
            if ($cur.Level -ge $script:OptMaxDepth) { continue }
            $subs = $null
            try { $subs = [IO.Directory]::EnumerateDirectories($cur.Path) } catch { continue }
            foreach ($sub in $subs) {
                $visited++
                $leaf = [IO.Path]::GetFileName($sub)
                if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                if ($skip -contains $leaf) { continue }

                if ($script:DataDirNames -contains $leaf) { Add-Item -Kind 'Data' -Path $sub -Source '全盘遍历'; continue }

                $nextLevel = $cur.Level + 1
                $checkExe = ($script:OptDeepScan -or ($nextLevel -le 2))
                $hasExe = $false
                if ($checkExe) {
                    foreach ($e in $script:ExeNames) {
                        if ([IO.File]::Exists((Join-Path $sub $e))) { $hasExe = $true; break }
                    }
                }
                if ($hasExe) { Add-Item -Kind 'Install' -Path $sub -Source '全盘遍历'; continue }

                if ($script:ConfigDirNames -contains $leaf) {
                    $low = $sub.ToLower()
                    if (($low -like '*\appdata\*') -or ($low -like '*\programdata\*')) {
                        Add-Item -Kind 'Config' -Path $sub -Source '全盘遍历'
                        continue
                    }
                }
                $queue.Enqueue([PSCustomObject]@{ Path = $sub; Level = $nextLevel })
            }
        }
        $script:ScanVisited = $script:ScanVisited + $visited
    }
}

# =====================================================================
#  安全校验：只有白名单形态的目录才允许删除
# =====================================================================
function Test-SafeItem {
    param($Item)
    $p = [string]$Item.Path
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    if ($p.Length -lt 6) { return $false }
    $leaf = [IO.Path]::GetFileName($p.TrimEnd('\'))
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $false }

    $blocked = @(
        'Users', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Windows', 'AppData',
        'Local', 'Roaming', 'LocalLow', 'Documents', 'Desktop', 'Downloads', 'Temp', 'OneDrive',
        'Public', 'Default', 'System32', 'SysWOW64', 'Tencent', 'Microsoft', 'Common Files'
    )
    if ($blocked -contains $leaf) { return $false }

    $low = $p.ToLower()
    foreach ($badTail in @('\documents', '\desktop', '\downloads', '\appdata', '\appdata\local', '\appdata\roaming', '\programdata')) {
        if ($low.EndsWith($badTail)) { return $false }
    }
    if ($low -eq $env:SystemRoot.ToLower()) { return $false }

    switch ($Item.Kind) {
        'Data' {
            if ($leaf -notmatch '^(WeChat Files|xwechat_files|Tencent Files)$') { return $false }
        }
        'Config' {
            if ($leaf -notmatch '^(WeChat|xwechat|WeChatAppEx|QQ|QQNT|QQ2009)$') { return $false }
        }
        'Install' {
            $hasExe = $false
            foreach ($e in $script:ExeNames) {
                if ([IO.File]::Exists((Join-Path $p $e))) { $hasExe = $true; break }
            }
            if (-not $hasExe) { return $false }
        }
        default { return $false }
    }
    return $true
}

# =====================================================================
#  删除引擎
# =====================================================================
function Stop-WxQQProcesses {
    $killed = New-Object 'System.Collections.Generic.List[string]'
    # 这些进程名不是个人版微信/QQ 独占的：企业微信的小程序容器同样叫 WeChatAppEx，
    # 所以必须再看一眼进程路径，落在其它腾讯产品目录里的一律不碰。
    $ambiguous = @('WeChatAppEx', 'WeChatPlayer', 'WeChatBrowser', 'WeChat')
    $otherTencent = '\\wxwork\\|\\wxdrive\\|\\wemeet\\|\\wemail\\|\\wedoc\\|\\wwuni\\|\\qimei\\|\\tdsdata\\|\\wecom\\'
    foreach ($n in $script:ProcNames) {
        foreach ($proc in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $pp = $null
            try { $pp = $proc.Path } catch { }
            if ($pp -and ($ambiguous -contains $n) -and ($pp.ToLower() -match $otherTencent)) {
                Write-Log ('    跳过（属于企业微信/腾讯会议等，不是个人微信）: ' + $proc.ProcessName + '  ' + $pp) 'DarkGray'
                continue
            }
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                $killed.Add(($proc.ProcessName + '(' + $proc.Id + ')'))
            } catch { }
        }
    }
    if ($killed.Count -gt 0) { Start-Sleep -Milliseconds 1200 }
    return $killed
}

function Invoke-Shred {
    param([string]$Path)
    $buf = New-Object byte[] (1MB)
    $rnd = New-Object System.Random
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try {
                $fs = [IO.File]::Open($f, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                try {
                    $len = $fs.Length
                    $done = [long]0
                    while ($done -lt $len) {
                        $rnd.NextBytes($buf)
                        $n = [Math]::Min([long]$buf.Length, $len - $done)
                        $fs.Write($buf, 0, [int]$n)
                        $done += $n
                    }
                    $fs.Flush($true)
                } finally { $fs.Dispose() }
            } catch { }
        }
    } catch { }
}

function Remove-Tree {
    param([string]$Path)
    $res = [PSCustomObject]@{ Path = $Path; Ok = $false; Message = '' }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $Path)) { $res.Ok = $true; return $res }
    } catch { $res.Message = $_.Exception.Message }

    try {
        $long = '\\?\' + $Path
        [IO.Directory]::Delete($long, $true)
        if (-not (Test-Path -LiteralPath $Path)) { $res.Ok = $true; $res.Message = ''; return $res }
    } catch { if (-not $res.Message) { $res.Message = $_.Exception.Message } }

    try {
        $empty = Join-Path $env:TEMP ('__wxqq_empty_' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $empty -Force -ErrorAction SilentlyContinue
        $null = robocopy $empty $Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /NC /NS /NP
        Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) { $res.Ok = $true; $res.Message = ''; return $res }
    } catch { if (-not $res.Message) { $res.Message = $_.Exception.Message } }

    if (-not $res.Message) { $res.Message = '部分文件被占用或权限不足' }
    return $res
}

function Remove-RegistryKeys {
    $keys = @(
        'HKCU:\SOFTWARE\Tencent\WeChat', 'HKCU:\SOFTWARE\Tencent\xwechat', 'HKCU:\SOFTWARE\Tencent\QQ',
        'HKCU:\SOFTWARE\Tencent\QQNT', 'HKCU:\SOFTWARE\Tencent\QQ2009', 'HKCU:\SOFTWARE\Tencent\TIM',
        'HKLM:\SOFTWARE\Tencent\WeChat', 'HKLM:\SOFTWARE\Tencent\xwechat', 'HKLM:\SOFTWARE\Tencent\QQNT',
        'HKLM:\SOFTWARE\Tencent\QQ2009',
        'HKLM:\SOFTWARE\WOW6432Node\Tencent\WeChat', 'HKLM:\SOFTWARE\WOW6432Node\Tencent\xwechat',
        'HKLM:\SOFTWARE\WOW6432Node\Tencent\QQNT', 'HKLM:\SOFTWARE\WOW6432Node\Tencent\QQ2009'
    )
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($k in $keys) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try {
            Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop
            $out.Add([PSCustomObject]@{ Path = $k; Ok = $true; Message = '' })
        } catch {
            $out.Add([PSCustomObject]@{ Path = $k; Ok = $false; Message = $_.Exception.Message })
        }
    }
    return $out
}

function Remove-OrphanUninstallKeys {
    $exclude = 'QQ音乐|QQMusic|QQ浏览器|QQBrowser|QQ影音|QQPlayer|QQ拼音|QQPinyin|QQ五笔|输入法|腾讯会议|企业微信|WeCom|WXWork|QQ游戏|电脑管家|PCMgr|腾讯文档|腾讯视频|QQLive|微信读书|微云|Weiyun'
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sub in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $dn = [string]$props.DisplayName
            if ([string]::IsNullOrWhiteSpace($dn)) { continue }
            if ($dn -match $exclude) { continue }
            if ($dn -notmatch '微信|WeChat|Weixin|QQ|TIM|Tencent QQ') { continue }
            $loc = [string]$props.InstallLocation
            if ($loc -and (Test-Path -LiteralPath $loc)) { continue }
            try {
                Remove-Item -LiteralPath $sub.PSPath -Recurse -Force -ErrorAction Stop
                $out.Add([PSCustomObject]@{ Path = ('卸载项 ' + $dn); Ok = $true; Message = '' })
            } catch {
                $out.Add([PSCustomObject]@{ Path = ('卸载项 ' + $dn); Ok = $false; Message = $_.Exception.Message })
            }
        }
    }
    return $out
}

# =====================================================================
#  UI
# =====================================================================
function Show-Banner {
    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor DarkCyan
    Write-Host '          微 信 / Q Q   本 机 记 录 全 量 清 理 工 具' -ForegroundColor Cyan
    Write-Host '          自动定位安装位置与数据目录 -> 彻底清除 -> 复核残留' -ForegroundColor DarkGray
    Write-Host '  ==================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-Help {
    Write-Log '用法:  clean-wx-qq.bat [开关]' 'White'
    Write-Log ''
    Write-Log '  不带开关      交互模式：先扫描并列出全部发现，再让你选择做什么（最安全）' 'Gray'
    Write-Log '  /scan         只扫描并导出报告，不删除任何东西' 'Gray'
    Write-Log '  /auto         全自动彻底清理（数据 + 缓存 + 注册表 + 安装目录 + 回收站），不询问' 'Yellow'
    Write-Log '  /auto /keepprogram   全自动但只清数据/缓存，保留程序与安装目录' 'Yellow'
    Write-Log '  /shred        删除前用随机数据覆写文件（防恢复，很慢，SSD 上效果有限）' 'Gray'
    Write-Log '  /deep         全盘深度搜索 WeChat.exe / Weixin.exe / QQ.exe（更全，更慢）' 'Gray'
    Write-Log '  /help         显示本帮助' 'Gray'
    Write-Log ''
    Write-Log '清除范围: 聊天记录、图片/视频/文件缓存、账号配置、登录状态、安装目录（可选）' 'Gray'
    Write-Log '不会触碰: 企业微信 WXWork、QQ音乐/浏览器/影音、腾讯会议、电脑管家 等非 QQ/微信 数据' 'Gray'
}

function Read-MenuChoice {
    Write-Log ''
    Write-Log '  请选择要执行的操作：' 'White'
    Write-Log ''
    Write-Log '    [1] 清除聊天记录 + 缓存 + 账号配置      （保留程序，最常用）' 'Gray'
    Write-Log '    [2] 彻底清理：上面全部 + 注册表 + 安装目录 + 回收站' 'Gray'
    Write-Log '    [3] 只导出扫描报告，不删除任何文件' 'Gray'
    Write-Log '    [Q] 退出' 'Gray'
    Write-Log ''
    while ($true) {
        $ans = Read-Host '  请输入 1 / 2 / 3 / Q 后回车（默认 1）'
        if ([string]::IsNullOrWhiteSpace($ans)) { return 'data' }
        switch ($ans.Trim().ToUpper()) {
            '1' { return 'data' }
            '2' { return 'full' }
            '3' { return 'scan' }
            'Q' { return 'cancel' }
            default { Write-Host '  无效输入，请重新选择。' -ForegroundColor Yellow }
        }
    }
}

function Wait-Confirm {
    param([string]$Message)
    Write-Log ''
    Write-Log ('  ' + $Message) 'Yellow'
    $ans = Read-Host '  若确认，请输入 YES 后回车（其它任意输入取消）'
    return ($ans -eq 'YES')
}

# =====================================================================
#  参数解析（/auto 或 -auto 都可以）
# =====================================================================
function Resolve-CliArgs {
    param([object[]]$ExtraArgs)
    $src = New-Object 'System.Collections.Generic.List[string]'
    if ($env:WXQQ_ARGS) {
        foreach ($a in ($env:WXQQ_ARGS -split '\s+')) { if ($a) { $src.Add($a) } }
    }
    if ($ExtraArgs) {
        foreach ($a in $ExtraArgs) { if ($a) { $src.Add([string]$a) } }
    }

    foreach ($a in $src) {
        $s = $a.Trim().TrimStart('-', '/', '\').ToLower()
        if (-not $s) { continue }
        switch ($s) {
            'auto'         { $script:OptAuto = $true }
            'a'            { $script:OptAuto = $true }
            'scan'         { $script:OptScanOnly = $true }
            'scanonly'     { $script:OptScanOnly = $true }
            'keepprogram'  { $script:OptKeepProgram = $true }
            'shred'        { $script:OptShred = $true }
            'deep'         { $script:OptDeepScan = $true }
            'deepscan'     { $script:OptDeepScan = $true }
            'help'         { $script:OptHelp = $true }
            'h'            { $script:OptHelp = $true }
            '?'            { $script:OptHelp = $true }
            default        { }
        }
    }
}

# =====================================================================
#  主流程
# =====================================================================
$script:ScanVisited = 0
$script:StartTime = Get-Date
Resolve-CliArgs -ExtraArgs $args

Show-Banner

$isAdmin = Test-Admin
if ($script:OptHelp) { Show-Help; exit 0 }

Write-Log ('  计算机     : ' + $env:COMPUTERNAME)
Write-Log ('  当前用户   : ' + $env:USERNAME)
Write-Log ('  管理员权限 : ' + $(if ($isAdmin) { '是' } else { '否（其他用户目录 / Program Files 可能扫不全，建议右键以管理员身份运行本 bat）' }))
$drives = Get-FixedDrives
Write-Log ('  固定磁盘   : ' + ($drives -join ' '))
Write-Log ('  遍历深度   : ' + $script:OptMaxDepth + ' 层' + $(if ($script:OptDeepScan) { ' + 深度 exe 搜索' } else { '' }))
Write-Log ('  运行模式   : ' + $(if ($script:OptScanOnly) { '只扫描' } elseif ($script:OptAuto) { '全自动清理' } else { '交互' }))

# ---------------- 扫描 ----------------
Write-Section '第 1/3 步   读取注册表、卸载信息、快捷方式、进程'
Scan-Registry
Scan-Uninstall
Scan-Shortcuts
Scan-Processes
Write-Log ('    已发现 ' + $script:Items.Count + ' 项') 'DarkGray'

Write-Section '第 2/3 步   检查各用户目录的已知位置'
Scan-KnownPaths
Scan-CommonInstallDirs
Write-Log ('    累计 ' + $script:Items.Count + ' 项') 'DarkGray'

Write-Section '第 3/3 步   遍历磁盘查找安装位置与数据目录'
Scan-Drives
Write-Log ('    累计 ' + $script:Items.Count + ' 项（本次遍历 ' + $script:ScanVisited + ' 个目录）') 'DarkGray'

# ---------------- 结果 ----------------
if ($script:Items.Count -eq 0) {
    Write-Section '扫描结果'
    Write-Log '  没有在本机找到微信 / QQ 的安装目录或聊天数据。' 'Yellow'
    Write-Log '  可能原因：' 'Gray'
    Write-Log '    - 这台电脑确实没装过（那就不用清理）' 'Gray'
    Write-Log '    - 数据装在移动硬盘/网络盘（本工具只遍历本机固定磁盘）' 'Gray'
    Write-Log '    - 安装位置很偏，试试加开关 /deep 再跑一次' 'Gray'
    $logDefault = Join-Path ([Environment]::GetFolderPath('Desktop')) ('微信QQ扫描_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    try { [IO.File]::WriteAllLines($logDefault, $script:LogText, (New-Object Text.UTF8Encoding($true))); Write-Log ('  日志：' + $logDefault) 'DarkGray' } catch { }
    exit 0
}

$order = @{ 'Data' = 0; 'Config' = 1; 'Install' = 2 }
$kindName = @{ 'Data' = '聊天记录'; 'Config' = '配置缓存'; 'Install' = '安装目录' }
$script:Items = @($script:Items | Sort-Object -Property @{ Expression = { $order[$_.Kind] } }, Path)

Write-Section ('扫描结果：共 ' + $script:Items.Count + ' 项')
Write-Log '  正在统计体积，请稍候 ...' 'DarkGray'
$i = 0
foreach ($it in $script:Items) {
    $i++
    [Console]::Write(("`r    统计 {0}/{1}   {2}" -f $i, $script:Items.Count, $it.Path.PadRight(40)))
    $m = Measure-TreeSize -Path $it.Path
    $it.Bytes = $m.Bytes
    $it.Files = $m.Files
}
[Console]::Write("`r" + (' ' * 110) + "`r")
Write-Log ''

$totalBytes = [long]0
$i = 0
foreach ($it in $script:Items) {
    $i++
    $totalBytes += $it.Bytes
    $tag = $kindName[$it.Kind]
    Write-Log ("  [{0}] {1}   {2}   （{3} 个文件）" -f $i, $tag.PadRight(4), (Format-Size $it.Bytes).PadLeft(9), $it.Files) 'White'
    Write-Log ("      " + $it.Path) 'Gray'
    Write-Log ("      来源: " + $it.Source) 'DarkGray'
    if ($it.Kind -eq 'Data') {
        try {
            $subs = @(Get-ChildItem -LiteralPath $it.Path -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 8 -ExpandProperty Name)
            if ($subs.Count -gt 0) { Write-Log ("      账号/子目录: " + ($subs -join ', ')) 'DarkGray' }
        } catch { }
    }
}
Write-Log ''
Write-Log ('  合计: ' + $script:Items.Count + ' 项，' + (Format-Size $totalBytes)) 'Cyan'

# ---------------- 选择动作 ----------------
$mode = 'cancel'
if ($script:OptScanOnly) {
    $mode = 'scan'
} elseif ($script:OptAuto) {
    $mode = $(if ($script:OptKeepProgram) { 'data' } else { 'full' })
} else {
    $mode = Read-MenuChoice
}

if ($mode -eq 'cancel') {
    Write-Log ''
    Write-Log '  已取消，没有删除任何东西。' 'Yellow'
    exit 0
}

if ($mode -eq 'scan') {
    $logPath = $script:OptLogPath
    if (-not $logPath) { $logPath = Join-Path ([Environment]::GetFolderPath('Desktop')) ('微信QQ扫描_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log') }
    try {
        [IO.File]::WriteAllLines($logPath, $script:LogText, (New-Object Text.UTF8Encoding($true)))
        Write-Log ('  扫描报告已保存：' + $logPath) 'Green'
    } catch { Write-Log ('  报告保存失败：' + $_.Exception.Message) 'Red' }
    exit 0
}

$targets = @()
if ($mode -eq 'full') {
    $targets = @($script:Items)
} else {
    $targets = @($script:Items | Where-Object { $_.Kind -ne 'Install' })
}

if ($targets.Count -eq 0) {
    Write-Log '  没有需要处理的项目。' 'Yellow'
    exit 0
}

if (-not $script:OptAuto) {
    Write-Log ''
    Write-Log ('  即将执行：' + $(if ($mode -eq 'full') { '彻底清理（数据 + 缓存 + 注册表 + 安装目录 + 回收站）' } else { '清除聊天记录与配置缓存（保留程序）' })) 'White'
    Write-Log ('  影响 ' + $targets.Count + ' 个目录，约 ' + (Format-Size ($targets | Measure-Object -Property Bytes -Sum).Sum)) 'White'
    Write-Log '  此操作不可撤销 —— 请确保手机端聊天记录完好（本地删除不影响服务器/手机）。' 'Yellow'
    if (-not (Wait-Confirm '确认要删除以上全部内容吗？')) {
        Write-Log ''
        Write-Log '  已取消，没有删除任何东西。' 'Yellow'
        exit 0
    }
}

# ---------------- 执行删除 ----------------
Write-Section '正在清理'

Write-Log '  结束微信 / QQ 相关进程 ...' 'DarkGray'
$killed = Stop-WxQQProcesses
if ($killed.Count -gt 0) { Write-Log ('    已结束: ' + ($killed -join ', ')) 'Yellow' }
else { Write-Log '    没有运行中的相关进程' 'DarkGray' }

$results = New-Object 'System.Collections.Generic.List[object]'
$i = 0
foreach ($t in $targets) {
    $i++
    Write-Log ''
    Write-Log ("  [{0}/{1}] {2}" -f $i, $targets.Count, $t.Path) 'White'

    if (-not (Test-SafeItem -Item $t)) {
        Write-Log '      [跳过] 未通过安全校验（避免误删）' 'Red'
        $results.Add([PSCustomObject]@{ Path = $t.Path; Ok = $false; Message = '未通过安全校验' })
        continue
    }

    $existsBefore = Test-Path -LiteralPath $t.Path
    $sizeBefore = $t.Bytes

    if ($script:OptShred) {
        Write-Log '      覆写文件内容（防恢复，耗时较长）...' 'DarkGray'
        Invoke-Shred -Path $t.Path
    }

    $r = Remove-Tree -Path $t.Path
    if ($r.Ok) {
        Write-Log ('      已删除，释放 ' + (Format-Size $sizeBefore)) 'Green'
        $results.Add([PSCustomObject]@{ Path = $t.Path; Ok = $true; Message = '' })
    } else {
        Write-Log ('      删除失败：' + $r.Message) 'Red'
        $results.Add([PSCustomObject]@{ Path = $t.Path; Ok = $false; Message = $r.Message })
    }
}

# 注册表
if ($mode -eq 'full') {
    Write-Section '清理注册表残留'
    $regResults = Remove-RegistryKeys
    $regOk = @($regResults | Where-Object { $_.Ok }).Count
    Write-Log ('    注册表项: 删除成功 ' + $regOk + ' 项，失败 ' + ($regResults.Count - $regOk) + ' 项') 'White'
    foreach ($rr in $regResults) {
        if ($rr.Ok) { Write-Log ('      [OK] ' + $rr.Path) 'DarkGray' }
        else { Write-Log ('      [失败] ' + $rr.Path + ' -> ' + $rr.Message) 'DarkGray' }
    }
    $orphans = Remove-OrphanUninstallKeys
    if ($orphans.Count -gt 0) {
        Write-Log ('    清理失效的卸载条目: ' + $orphans.Count + ' 项') 'White'
    }
    Write-Log '    清空回收站 ...' 'DarkGray'
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log '    回收站已清空' 'Green' } catch { Write-Log ('    回收站未清空或本来就是空的: ' + $_.Exception.Message) 'DarkGray' }
}

# ---------------- 复核 ----------------
Write-Section '复核残留'
$left = New-Object 'System.Collections.Generic.List[string]'
foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t.Path) { $left.Add($t.Path) }
}
if ($left.Count -eq 0) {
    Write-Log '  已确认：本次处理的目标目录全部不存在了。' 'Green'
} else {
    Write-Log ('  仍有 ' + $left.Count + ' 项未完全删除（多为文件被占用），建议重启电脑后再运行一次本工具：') 'Yellow'
    foreach ($l in $left) { Write-Log ('    - ' + $l) 'Yellow' }
}

$okCount = @($results | Where-Object { $_.Ok }).Count
$failCount = $results.Count - $okCount

# ---------------- 报告 ----------------
Write-Section '完成'
Write-Log ('  成功删除 : ' + $okCount + ' 项') 'Green'
Write-Log ('  失败     : ' + $failCount + ' 项') $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
foreach ($r in $results) {
    if (-not $r.Ok) { Write-Log ('    x ' + $r.Path + '  -> ' + $r.Message) 'Red' }
}
if ($mode -ne 'full') {
    Write-Log ''
    Write-Log '  提示：程序本体和注册表仍在（下次启动微信/QQ 会重新生成配置目录）。' 'DarkGray'
    Write-Log '        要把电脑彻底交出去，请选 [2] 彻底清理，或手动卸载微信 / QQ。' 'DarkGray'
}
Write-Log ''
Write-Log '  安全建议：' 'Cyan'
Write-Log '    1. 手机上打开「设置 - 账号安全 - 登录设备管理」，删除这台电脑。' 'Gray'
Write-Log '    2. 若担心数据被恢复：本工具 /shred 只做单遍覆写，SSD 上仍可能残留；' 'Gray'
Write-Log '       稳妥做法是给对方前重装系统，或开启 BitLocker 加密后格式化。' 'Gray'
Write-Log '    3. 顺手清理：浏览器账号密码、邮箱客户端、输入法词库、下载目录里的私人文件。' 'Gray'

$logPath = $script:OptLogPath
if (-not $logPath) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = $env:TEMP }
    $logPath = Join-Path $desk ('微信QQ清理_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
}
try {
    Write-Log ''
    Write-Log ('  日志文件：' + $logPath) 'DarkGray'
    [IO.File]::WriteAllLines($logPath, $script:LogText, (New-Object Text.UTF8Encoding($true)))
} catch { }

exit $(if ($failCount -gt 0) { 1 } else { 0 })

#===PS-END===
