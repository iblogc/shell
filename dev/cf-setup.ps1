# PowerShell script for Windows: Setup and run cloudflared tunnel
# PowerShell命令："iwr -useb https://gh-proxy.com/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"

# === 彩色输出函数 ===
function Write-Color {
    param (
        [string]$Message,
        [ConsoleColor]$Color = 'White'
    )
    $oldColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Message
    $Host.UI.RawUI.ForegroundColor = $oldColor
}

# === 变量定义 ===
$cloudflaredUrl = "https://gh-proxy.com/https://github.com/cloudflare/cloudflared/releases/download/2025.5.0/cloudflared-windows-amd64.exe"
$installDir = "$env:ProgramData\cloudflared"
$cloudflaredBin = Join-Path $installDir "cloudflared.exe"
$logPath = Join-Path $installDir "cloudflared.log"
$serviceName = "CloudflaredTunnel"

# 创建安装目录
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 下载 cloudflared
if (Test-Path $cloudflaredBin) {
    Write-Color "已存在 cloudflared.exe，跳过下载。" Green
} else {
    Write-Color "正在下载 cloudflared 到 $cloudflaredBin" Cyan
    try {
        Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredBin -UseBasicParsing
        Write-Color "下载完成。" Green
    } catch {
        Write-Color "下载失败，请检查网络连接或 URL。" Red
        exit 1
    }
}

# 检查是否存在旧服务
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Color "检测到已存在的 cloudflared 服务: $serviceName" Yellow
    $uninstall = Read-Host "是否卸载旧服务？(y/n)"
    if ($uninstall -eq "y" -or $uninstall -eq "Y") {
        Write-Color "正在卸载旧服务..." Cyan
        Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
        Remove-Item -Force $logPath -ErrorAction SilentlyContinue
        Write-Color "服务卸载完成。" Green
    } else {
        Write-Color "将保留旧服务，仅更新运行地址。" Yellow
    }
}

# 模式选择
Write-Color "`n请选择运行模式：" Yellow
Write-Host "1) 临时运行（前台运行并显示 trycloudflare 域名）"
Write-Host "2) 后台运行（注册为系统服务）"
$mode = Read-Host "请输入 1 或 2"

# 获取本地地址
$localAddr = Read-Host "请输入本地服务地址（例如 127.0.0.1:8080）"

if ($mode -eq "1") {
    Write-Color "以临时模式运行 cloudflared..." Cyan
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $cloudflaredBin
    $processInfo.Arguments = "tunnel --url $localAddr"
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null

    $reader = $process.StandardOutput
    Write-Color "等待 cloudflared 输出公网地址..." Yellow

    $domain = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $output = $reader.ReadToEnd()
        if ($output -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $domain = $matches[0]
            break
        }
    }

    if ($domain) {
        Write-Color "`n公网临时访问地址：" Green
        Write-Color "$domain" Green
    } else {
        Write-Color "未能获取访问地址，请检查日志或参数。" Red
    }

    $process.WaitForExit()

} elseif ($mode -eq "2") {
    Write-Color "注册为系统服务并后台运行..." Cyan
    $svcCmd = "`"$cloudflaredBin`" tunnel --url $localAddr --logfile `"$logPath`""
    sc.exe create $serviceName binPath= $svcCmd start= auto | Out-Null
    Start-Sleep -Seconds 2
    Start-Service -Name $serviceName

    Write-Color "服务已启动，等待输出日志..." Green

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path $logPath) {
            $content = Get-Content $logPath -Raw
            if ($content -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                $domain = $matches[0]
                Write-Color "`n公网访问地址：" Green
                Write-Color "$domain" Green
                break
            }
        }
    }

    if (-not $domain) {
        Write-Color "未检测到访问域名，请手动查看日志：$logPath" Red
    }

} else {
    Write-Color "无效选项，请输入 1 或 2。" Red
    exit 1
}
