# cloudflared-setup.ps1
# PowerShell script for Windows: Setup and run cloudflared tunnel
# powershell -ExecutionPolicy Bypass -Command "iwr -useb https://gh-proxy.com/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"

# === 颜色函数 ===
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
$cloudflaredBin = ".\cloudflared.exe"
$logPath = "$PSScriptRoot\cloudflared.log"
$serviceName = "CloudflaredTunnel"

# 下载 cloudflared
if (Test-Path $cloudflaredBin) {
    Write-Color "已存在 cloudflared.exe，跳过下载。" Green
} else {
    Write-Color "正在下载 cloudflared..." Cyan
    try {
        Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredBin -UseBasicParsing
    } catch {
        Write-Color "下载失败，请检查网络连接或 URL。" Red
        exit 1
    }
}

# 检查服务是否存在
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Color "检测到 cloudflared 后台服务: $serviceName" Yellow
    $uninstall = Read-Host "是否要卸载旧服务？(y/n)"
    if ($uninstall -eq "y" -or $uninstall -eq "Y") {
        Write-Color "正在卸载旧服务..." Cyan
        Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
        Remove-Item -Force $logPath -ErrorAction SilentlyContinue
        Write-Color "服务卸载完成" Green
    } else {
        Write-Color "将保留旧服务，仅修改穿透地址。" Yellow
    }
}

# 运行模式选择
Write-Color "`n请选择运行模式：" Yellow
Write-Host "1) 临时运行（前台运行并显示临时访问域名）"
Write-Host "2) 后台运行（注册服务并自动运行）"
$mode = Read-Host "请输入 1 或 2"

# 获取本地地址
$localAddr = Read-Host "请输入要穿透的本地地址（例如 127.0.0.1:8080）"

if ($mode -eq "1") {
    Write-Color "正在前台运行 cloudflared..." Cyan

    $logFile = New-TemporaryFile
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $cloudflaredBin
    $startInfo.Arguments = "tunnel --url $localAddr"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null

    $reader = $process.StandardOutput
    Write-Color "等待 cloudflared 输出访问域名..." Yellow

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
        Write-Color "`n成功获取公网临时访问域名：" Green
        Write-Color "$domain" Green
    } else {
        Write-Color "超时未能获取临时域名，手动查看日志：$logFile" Red
    }
    $process.WaitForExit()
} elseif ($mode -eq "2") {
    Write-Color "正在注册 cloudflared 为系统服务..." Cyan
    $fullPath = Resolve-Path $cloudflaredBin

    $svcCmd = "`"$fullPath`" tunnel --url $localAddr"
    sc.exe create $serviceName binPath= $svcCmd start= auto | Out-Null
    Start-Sleep -Seconds 2
    Start-Service -Name $serviceName

    Write-Color "服务已启动，等待 cloudflared 输出访问域名..." Green

    # 日志检测：cloudflared 默认输出路径可配置（需 cloudflared 本身支持 Windows 日志）
    Start-Sleep -Seconds 3
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path $logPath) {
            $content = Get-Content $logPath -Raw
            if ($content -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                $domain = $matches[0]
                Write-Color "`n成功获取公网访问域名：" Green
                Write-Color "$domain" Green
                break
            }
        }
    }
    if (-not $domain) {
        Write-Color "未检测到访问域名，请手动查看日志：$logPath" Red
    }
} else {
    Write-Color "无效输入，请输入 1 或 2" Red
    exit 1
}
