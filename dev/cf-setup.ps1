# PowerShell 脚本用于 Windows: 设置和运行 cloudflared 隧道
# 远程执行: "iwr -useb https://gh-proxy.com/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"
# 安装路径: "C:\ProgramData\cloudflared\"

# 兼容性检查和设置
$ProgressPreference = 'SilentlyContinue'  # 禁用进度条避免远程执行问题
$ErrorActionPreference = 'Stop'

# 彩色输出函数 - 兼容所有PowerShell版本
function Write-ColorMessage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')]
        [string]$Color = 'White'
    )
    
    try {
        $originalColor = $null
        if ($Host.UI -and $Host.UI.RawUI -and $Host.UI.RawUI.ForegroundColor) {
            $originalColor = $Host.UI.RawUI.ForegroundColor
            $Host.UI.RawUI.ForegroundColor = $Color
        }
        
        # 使用Write-Host确保正确显示
        Write-Host $Message
        
        if ($originalColor -ne $null) {
            $Host.UI.RawUI.ForegroundColor = $originalColor
        }
    } catch {
        # 回退方法：直接输出不进行编码转换
        try {
            Write-Host $Message -ForegroundColor $Color
        } catch {
            Write-Host $Message
        }
    }
}

# 安全的文件下载函数
function Download-File {
    param (
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        # 兼容不同PowerShell版本的下载方法
        if ($PSVersionTable.PSVersion.Major -ge 3) {
            # 使用 Invoke-WebRequest (PowerShell 3.0+)
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
        } else {
            # 回退到 .NET WebClient
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
        }
        return $true
    } catch {
        Write-ColorMessage "Download failed: $($_.Exception.Message)" Red
        return $false
    }
}

# 检查管理员权限
function Test-AdminRights {
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# 主脚本开始
Write-Host "====== CloudFlared Tunnel Setup Tool ======" -ForegroundColor Cyan
Write-Host "Initializing..." -ForegroundColor Yellow

# 变量定义
$cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/download/2024.12.2/cloudflared-windows-amd64.exe"
$installDir = "$env:ProgramData\cloudflared"
$cloudflaredBin = Join-Path $installDir "cloudflared.exe"
$logPath = Join-Path $installDir "cloudflared.log"
$serviceName = "CloudflaredTunnel"

# 检查PowerShell版本
$psVersion = $PSVersionTable.PSVersion.Major
Write-Host "Detected PowerShell version: $psVersion" -ForegroundColor Green

# 创建安装目录
try {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-ColorMessage "Created installation directory: $installDir" Green
    }
} catch {
    Write-ColorMessage "Cannot create installation directory, may need administrator privileges" Red
    Write-ColorMessage "Error: $($_.Exception.Message)" Red
    exit 1
}

# 下载 cloudflared
Write-ColorMessage "`nChecking cloudflared..." Yellow
if (Test-Path $cloudflaredBin) {
    Write-ColorMessage "cloudflared.exe already exists: $cloudflaredBin" Green
    
    # 获取文件版本信息
    try {
        $fileInfo = Get-Item $cloudflaredBin
        $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-ColorMessage "File size: ${fileSize} MB" Cyan
    } catch {
        # 忽略版本信息获取错误
    }
} else {
    Write-ColorMessage "Starting download of cloudflared..." Cyan
    Write-ColorMessage "Download URL: $cloudflaredUrl" Gray
    Write-ColorMessage "Save location: $cloudflaredBin" Gray
    
    $downloadSuccess = Download-File -Url $cloudflaredUrl -OutputPath $cloudflaredBin
    
    if ($downloadSuccess) {
        Write-ColorMessage "Download complete!" Green
        try {
            $fileInfo = Get-Item $cloudflaredBin
            $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-ColorMessage "File size: ${fileSize} MB" Cyan
        } catch {
            # 忽略文件信息获取错误
        }
    } else {
        Write-ColorMessage "Download failed, please check your network connection or download manually" Red
        Write-ColorMessage "Manual download URL: $cloudflaredUrl" Yellow
        exit 1
    }
}

# 检查现有服务
Write-ColorMessage "`nChecking existing services..." Yellow
try {
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($serviceExists) {
        Write-ColorMessage "Detected existing cloudflared service: $serviceName" Yellow
        Write-ColorMessage "Service status: $($serviceExists.Status)" Cyan
        
        do {
            $uninstall = Read-Host "Do you want to uninstall the old service? (y/n)"
        } while ($uninstall -notin @('y','Y','n','N','yes','no'))
        
        if ($uninstall -in @('y','Y','yes')) {
            Write-ColorMessage "Uninstalling old service..." Cyan
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                # 使用 sc.exe 删除服务
                $scResult = & "$env:SystemRoot\System32\sc.exe" delete $serviceName
                
                # 清理日志文件
                if (Test-Path $logPath) {
                    Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
                }
                
                Write-ColorMessage "Service uninstallation complete" Green
            } catch {
                Write-ColorMessage "Error uninstalling service: $($_.Exception.Message)" Red
            }
        } else {
            Write-ColorMessage "Keeping existing service, only updating run address" Yellow
        }
    }
} catch {
    Write-ColorMessage "Error checking service: $($_.Exception.Message)" Red
}

# 模式选择
Write-ColorMessage "`nPlease select run mode:" Yellow
Write-Host "1) Temporary run (foreground with trycloudflare domain display)"
Write-Host "2) Background run (register as system service)"

do {
    $mode = Read-Host "Please enter 1 or 2"
} while ($mode -notin @('1','2'))

# 获取本地地址
do {
    $localAddr = Read-Host "Please enter local service address (e.g.: 127.0.0.1:8080)"
} while ([string]::IsNullOrWhiteSpace($localAddr))

if ($mode -eq "1") {
    # 临时运行模式
    Write-ColorMessage "`nRunning cloudflared in temporary mode..." Cyan
    Write-ColorMessage "Starting cloudflared process..." Yellow
    Write-ColorMessage "Local service address: $localAddr" Green
    
    try {
        # 构建命令参数
        $arguments = @("tunnel", "--url", $localAddr)
        
        # 启动进程
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = $cloudflaredBin
        $processStartInfo.Arguments = $arguments -join " "
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        $processStartInfo.CreateNoWindow = $false
        $processStartInfo.WorkingDirectory = $installDir
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processStartInfo
        
        # 启动进程
        $process.Start() | Out-Null
        
        Write-ColorMessage "Waiting for tunnel URL (monitoring output)..." Yellow
        Write-ColorMessage "If there's no output for a long time, check if local service is running at $localAddr" Cyan
        
        # 读取输出并查找域名
        $domain = $null
        $timeout = 60
        $outputLines = @()
        
        for ($i = 0; $i -lt $timeout; $i++) {
            Start-Sleep -Seconds 1
            
            # 读取输出
            try {
                if (-not $process.StandardOutput.EndOfStream) {
                    $line = $process.StandardOutput.ReadLine()
                    if ($line) {
                        $outputLines += $line
                        Write-Host $line -ForegroundColor Gray
                        
                        if ($line -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                            $domain = $matches[0]
                            break
                        }
                    }
                }
                
                if (-not $process.StandardError.EndOfStream) {
                    $errorLine = $process.StandardError.ReadLine()
                    if ($errorLine) {
                        $outputLines += $errorLine
                        Write-Host $errorLine -ForegroundColor Gray
                        
                        if ($errorLine -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                            $domain = $matches[0]
                            break
                        }
                    }
                }
            } catch {
                # 继续尝试读取
            }
            
            # 检查进程是否还在运行
            if ($process.HasExited) {
                Write-ColorMessage "Process unexpectedly exited, exit code: $($process.ExitCode)" Red
                break
            }
            
            # 显示进度
            if ($i % 5 -eq 0 -and $i -gt 0) {
                Write-Host "." -NoNewline
            }
        }
        
        Write-Host ""
        
        if ($domain) {
            Write-ColorMessage "`n=== Tunnel Created Successfully ===" Green
            Write-ColorMessage "Public access URL: $domain" Green
            Write-ColorMessage "Local service address: $localAddr" Cyan
            Write-ColorMessage "`nPress Ctrl+C to stop the tunnel" Yellow
            
            # 保持进程运行
            try {
                $process.WaitForExit()
            } catch [System.Threading.ThreadInterruptedException] {
                Write-ColorMessage "`nProcess interrupted" Yellow
            }
        } else {
            Write-ColorMessage "Could not automatically extract tunnel URL" Red
            Write-ColorMessage "But the tunnel may still be running, please check the output above" Yellow
            
            # 显示最近的输出
            if ($outputLines.Count -gt 0) {
                Write-ColorMessage "`nRecent output:" Cyan
                $outputLines | Select-Object -Last 10 | ForEach-Object {
                    if (![string]::IsNullOrWhiteSpace($_)) {
                        Write-Host $_
                    }
                }
            }
        }
        
    } catch {
        Write-ColorMessage "Error starting process: $($_.Exception.Message)" Red
    } finally {
        # 清理进程
        try {
            if ($process -and -not $process.HasExited) {
                $process.Kill()
                $process.WaitForExit(5000)
            }
            if ($process) {
                $process.Dispose()
            }
        } catch {
            # 忽略清理错误
        }
    }
    
} elseif ($mode -eq "2") {
    # 服务运行模式
    Write-ColorMessage "`nRegistering as system service and running in background..." Cyan
    
    # 检查管理员权限
    if (-not (Test-AdminRights)) {
        Write-ColorMessage "Warning: Administrator privileges may be required to create system services" Yellow
        Write-ColorMessage "If this fails, please run this script as administrator" Yellow
    }
    
    try {
        # 构建服务命令
        $serviceCommand = "`"$cloudflaredBin`" tunnel --url $localAddr --logfile `"$logPath`""
        
        # 创建服务
        $scResult = & "$env:SystemRoot\System32\sc.exe" create $serviceName binPath= $serviceCommand start= auto
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "Service created successfully" Green
        } else {
            Write-ColorMessage "Service creation may have failed, exit code: $LASTEXITCODE" Yellow
        }
        
        Start-Sleep -Seconds 2
        
        # 启动服务
        Write-ColorMessage "Starting service..." Yellow
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-ColorMessage "Service started successfully, waiting for log output..." Green
        
        # 等待并读取日志
        $domain = $null
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            
            if (Test-Path $logPath) {
                try {
                    $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
                    if ($logContent -and $logContent -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                        $domain = $matches[0]
                        Write-ColorMessage "`n=== Service Running Successfully ===" Green
                        Write-ColorMessage "Public access URL: $domain" Green
                        Write-ColorMessage "Local service address: $localAddr" Cyan
                        Write-ColorMessage "Log file location: $logPath" Gray
                        break
                    }
                } catch {
                    # 继续等待
                }
            }
            
            # 显示等待进度
            if ($i % 3 -eq 0) {
                Write-Host "." -NoNewline
            }
        }
        
        Write-Host ""
        
        if (-not $domain) {
            Write-ColorMessage "No access domain detected, please check the log manually: $logPath" Yellow
            Write-ColorMessage "The service may need more time to establish connection" Cyan
            
            # 显示服务状态
            try {
                $serviceStatus = Get-Service -Name $serviceName
                Write-ColorMessage "Service status: $($serviceStatus.Status)" Cyan
            } catch {
                Write-ColorMessage "Unable to get service status" Red
            }
        }
        
        Write-ColorMessage "`nService management commands:" Yellow
        Write-ColorMessage "Stop service: Stop-Service -Name $serviceName" Gray
        Write-ColorMessage "Start service: Start-Service -Name $serviceName" Gray
        Write-ColorMessage "Delete service: sc.exe delete $serviceName" Gray
        
    } catch {
        Write-ColorMessage "Failed to create or start service" Red
        Write-ColorMessage "Error: $($_.Exception.Message)" Red
        Write-ColorMessage "Please make sure you have administrator privileges" Yellow
        
        # 尝试清理失败的服务
        try {
            & "$env:SystemRoot\System32\sc.exe" delete $serviceName 2>$null
        } catch {
            # 忽略清理错误
        }
    }
    
} else {
    Write-ColorMessage "Invalid option, please enter 1 or 2" Red
    exit 1
}

Write-ColorMessage "`nScript execution complete" Green
