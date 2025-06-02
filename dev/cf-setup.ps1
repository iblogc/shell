# PowerShell 脚本用于 Windows: 设置和运行 cloudflared 隧道
# 远程执行: "iwr -useb https://gh-proxy.com/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"
# 安装路径: "C:\ProgramData\cloudflared\"

# 设置控制台编码以支持中文字符
if ($PSVersionTable.PSVersion.Major -ge 5) {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {
        # 忽略编码设置错误，继续执行
    }
}

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
    
    # 确保在所有环境中都能正常工作
    try {
        $originalColor = $null
        if ($Host.UI -and $Host.UI.RawUI) {
            $originalColor = $Host.UI.RawUI.ForegroundColor
            $Host.UI.RawUI.ForegroundColor = $Color
        }
        
        Write-Host $Message
        
        if ($originalColor -ne $null) {
            $Host.UI.RawUI.ForegroundColor = $originalColor
        }
    } catch {
        # 回退到基本输出
        Write-Host $Message
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
        Write-ColorMessage "下载失败: $($_.Exception.Message)" Red
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
Write-ColorMessage "====== CloudFlared 隧道设置工具 ======" Cyan
Write-ColorMessage "正在初始化..." Yellow

# 变量定义
$cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/download/2024.12.2/cloudflared-windows-amd64.exe"
$installDir = "$env:ProgramData\cloudflared"
$cloudflaredBin = Join-Path $installDir "cloudflared.exe"
$logPath = Join-Path $installDir "cloudflared.log"
$serviceName = "CloudflaredTunnel"

# 检查PowerShell版本
$psVersion = $PSVersionTable.PSVersion.Major
Write-ColorMessage "检测到 PowerShell 版本: $psVersion" Green

# 创建安装目录
try {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-ColorMessage "创建安装目录: $installDir" Green
    }
} catch {
    Write-ColorMessage "无法创建安装目录，可能需要管理员权限" Red
    Write-ColorMessage "错误: $($_.Exception.Message)" Red
    exit 1
}

# 下载 cloudflared
Write-ColorMessage "`n正在检查 cloudflared..." Yellow
if (Test-Path $cloudflaredBin) {
    Write-ColorMessage "cloudflared.exe 已存在: $cloudflaredBin" Green
    
    # 获取文件版本信息
    try {
        $fileInfo = Get-Item $cloudflaredBin
        $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-ColorMessage "文件大小: ${fileSize} MB" Cyan
    } catch {
        # 忽略版本信息获取错误
    }
} else {
    Write-ColorMessage "开始下载 cloudflared..." Cyan
    Write-ColorMessage "下载地址: $cloudflaredUrl" Gray
    Write-ColorMessage "保存位置: $cloudflaredBin" Gray
    
    $downloadSuccess = Download-File -Url $cloudflaredUrl -OutputPath $cloudflaredBin
    
    if ($downloadSuccess) {
        Write-ColorMessage "下载完成!" Green
        try {
            $fileInfo = Get-Item $cloudflaredBin
            $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-ColorMessage "文件大小: ${fileSize} MB" Cyan
        } catch {
            # 忽略文件信息获取错误
        }
    } else {
        Write-ColorMessage "下载失败，请检查网络连接或手动下载" Red
        Write-ColorMessage "手动下载地址: $cloudflaredUrl" Yellow
        exit 1
    }
}

# 检查现有服务
Write-ColorMessage "`n正在检查现有服务..." Yellow
try {
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($serviceExists) {
        Write-ColorMessage "检测到现有的 cloudflared 服务: $serviceName" Yellow
        Write-ColorMessage "服务状态: $($serviceExists.Status)" Cyan
        
        do {
            $uninstall = Read-Host "是否要卸载旧服务? (y/n)"
        } while ($uninstall -notin @('y','Y','n','N','yes','no'))
        
        if ($uninstall -in @('y','Y','yes')) {
            Write-ColorMessage "正在卸载旧服务..." Cyan
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                # 使用 sc.exe 删除服务
                $scResult = & "$env:SystemRoot\System32\sc.exe" delete $serviceName
                
                # 清理日志文件
                if (Test-Path $logPath) {
                    Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
                }
                
                Write-ColorMessage "服务卸载完成" Green
            } catch {
                Write-ColorMessage "卸载服务时出错: $($_.Exception.Message)" Red
            }
        } else {
            Write-ColorMessage "保留现有服务，仅更新运行地址" Yellow
        }
    }
} catch {
    Write-ColorMessage "检查服务时出错: $($_.Exception.Message)" Red
}

# 模式选择
Write-ColorMessage "`n请选择运行模式:" Yellow
Write-Host "1) 临时运行 (前台运行并显示 trycloudflare 域名)"
Write-Host "2) 后台运行 (注册为系统服务)"

do {
    $mode = Read-Host "请输入 1 或 2"
} while ($mode -notin @('1','2'))

# 获取本地地址
do {
    $localAddr = Read-Host "请输入本地服务地址 (例如: 127.0.0.1:8080)"
} while ([string]::IsNullOrWhiteSpace($localAddr))

if ($mode -eq "1") {
    # 临时运行模式
    Write-ColorMessage "`n正在以临时模式运行 cloudflared..." Cyan
    Write-ColorMessage "启动 cloudflared 进程..." Yellow
    Write-ColorMessage "本地服务地址: $localAddr" Green
    
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
        
        Write-ColorMessage "正在等待隧道URL (监控输出中)..." Yellow
        Write-ColorMessage "如果长时间没有输出，请检查本地服务是否运行在 $localAddr" Cyan
        
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
                Write-ColorMessage "进程意外退出，退出代码: $($process.ExitCode)" Red
                break
            }
            
            # 显示进度
            if ($i % 5 -eq 0 -and $i -gt 0) {
                Write-Host "." -NoNewline
            }
        }
        
        Write-Host ""
        
        if ($domain) {
            Write-ColorMessage "`n=== 隧道创建成功 ===" Green
            Write-ColorMessage "公网访问地址: $domain" Green
            Write-ColorMessage "本地服务地址: $localAddr" Cyan
            Write-ColorMessage "`n按 Ctrl+C 停止隧道" Yellow
            
            # 保持进程运行
            try {
                $process.WaitForExit()
            } catch [System.Threading.ThreadInterruptedException] {
                Write-ColorMessage "`n进程被中断" Yellow
            }
        } else {
            Write-ColorMessage "无法自动提取隧道URL" Red
            Write-ColorMessage "但隧道可能仍在运行，请检查上方输出" Yellow
            
            # 显示最近的输出
            if ($outputLines.Count -gt 0) {
                Write-ColorMessage "`n最近的输出:" Cyan
                $outputLines | Select-Object -Last 10 | ForEach-Object {
                    if (![string]::IsNullOrWhiteSpace($_)) {
                        Write-Host $_
                    }
                }
            }
        }
        
    } catch {
        Write-ColorMessage "启动进程时出错: $($_.Exception.Message)" Red
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
    Write-ColorMessage "`n正在注册为系统服务并后台运行..." Cyan
    
    # 检查管理员权限
    if (-not (Test-AdminRights)) {
        Write-ColorMessage "警告: 可能需要管理员权限来创建系统服务" Yellow
        Write-ColorMessage "如果失败，请以管理员身份重新运行此脚本" Yellow
    }
    
    try {
        # 构建服务命令
        $serviceCommand = "`"$cloudflaredBin`" tunnel --url $localAddr --logfile `"$logPath`""
        
        # 创建服务
        $scResult = & "$env:SystemRoot\System32\sc.exe" create $serviceName binPath= $serviceCommand start= auto
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "服务创建成功" Green
        } else {
            Write-ColorMessage "服务创建可能失败，退出代码: $LASTEXITCODE" Yellow
        }
        
        Start-Sleep -Seconds 2
        
        # 启动服务
        Write-ColorMessage "正在启动服务..." Yellow
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-ColorMessage "服务启动成功，正在等待日志输出..." Green
        
        # 等待并读取日志
        $domain = $null
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            
            if (Test-Path $logPath) {
                try {
                    $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
                    if ($logContent -and $logContent -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                        $domain = $matches[0]
                        Write-ColorMessage "`n=== 服务运行成功 ===" Green
                        Write-ColorMessage "公网访问地址: $domain" Green
                        Write-ColorMessage "本地服务地址: $localAddr" Cyan
                        Write-ColorMessage "日志文件位置: $logPath" Gray
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
            Write-ColorMessage "未检测到访问域名，请手动检查日志: $logPath" Yellow
            Write-ColorMessage "服务可能需要更多时间来建立连接" Cyan
            
            # 显示服务状态
            try {
                $serviceStatus = Get-Service -Name $serviceName
                Write-ColorMessage "服务状态: $($serviceStatus.Status)" Cyan
            } catch {
                Write-ColorMessage "无法获取服务状态" Red
            }
        }
        
        Write-ColorMessage "`n服务管理命令:" Yellow
        Write-ColorMessage "停止服务: Stop-Service -Name $serviceName" Gray
        Write-ColorMessage "启动服务: Start-Service -Name $serviceName" Gray
        Write-ColorMessage "删除服务: sc.exe delete $serviceName" Gray
        
    } catch {
        Write-ColorMessage "创建或启动服务失败" Red
        Write-ColorMessage "错误: $($_.Exception.Message)" Red
        Write-ColorMessage "请确认您有管理员权限" Yellow
        
        # 尝试清理失败的服务
        try {
            & "$env:SystemRoot\System32\sc.exe" delete $serviceName 2>$null
        } catch {
            # 忽略清理错误
        }
    }
    
} else {
    Write-ColorMessage "无效选项，请输入 1 或 2" Red
    exit 1
}

Write-ColorMessage "`n脚本执行完成" Green
