# UI 自检截图脚本：启动 cfnb_app.exe，遍历四个页面截图到 /ui_shots/。
# 可选参数：-DebugExe <path> 使用指定 exe 并重定向输出到 ui_shots\app_console.log
param([string]$DebugExe = '')
$ErrorActionPreference = 'Stop'

if ($DebugExe) {
  $exe = $DebugExe
} else {
  $exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\cfnb_app.exe'
}
$outDir = Join-Path $PSScriptRoot '..\ui_shots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Get-Process -Name cfnb_app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

if (-not (Test-Path $exe)) { Write-Host "exe not found: $exe"; exit 1 }
if ($DebugExe) {
  $stdout = Join-Path $outDir 'app_stdout.log'
  $stderr = Join-Path $outDir 'app_console.log'
  $p = Start-Process -FilePath $exe -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
} else {
  $p = Start-Process -FilePath $exe -PassThru
}

# 等待主窗口出现
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $hwnd -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 500
  $p.Refresh()
  if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Host 'window not found'; exit 1 }
Write-Host "window handle: $hwnd"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UINative {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

[UINative]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 800

$rect = New-Object UINative+RECT
[UINative]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
Write-Host "window rect: $($rect.Left),$($rect.Top) ${w}x${h}"

# 鼠标点击窗口内坐标（窗口客户区原点 = 窗口左上角）
function Click([int]$x, [int]$y) {
  $absX = $rect.Left + $x
  $absY = $rect.Top + $y
  # mouse_event 需要绝对坐标
  $screenW = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
  $screenH = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
  $nx = [uint32]([math]::Round($absX * 65535.0 / $screenW))
  $ny = [uint32]([math]::Round($absY * 65535.0 / $screenH))
  [UINative]::mouse_event(0x8000 -bor 0x0001, $nx, $ny, 0, [UIntPtr]::Zero)  # MOVE + ABSOLUTE
  [UINative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [UINative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
}

function Snap([string]$name) {
  Start-Sleep -Milliseconds 1200
  [UINative]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
  $w = $rect.Right - $rect.Left
  $h = $rect.Bottom - $rect.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [UINative]::PrintWindow($hwnd, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  $g.Dispose()
  $path = Join-Path $outDir "$name.png"
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "saved: $path"
}

# 侧边栏导航（宽 88 图标栏）4 个页面的点击坐标
# 布局：logo 顶区 22 + 40 + 24 → 首个 item 顶部 ~86，item 高 62 + margin 2*2 → 间距 66
$navY = @(120, 186, 252, 318)   # 工作台 / 优选配置 / 结果 / 设置
$names = @('dashboard', 'config', 'results', 'settings')

# 先截默认页（工作台），再逐个点击切换
Snap $names[0]
for ($i = 1; $i -lt 4; $i++) {
  Click 44 $navY[$i]
  Snap $names[$i]
}
# 切回工作台
Click 44 $navY[0]
Snap 'dashboard2'

Get-Process -Name cfnb_app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host 'done'