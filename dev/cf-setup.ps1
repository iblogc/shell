# PowerShell script for Windows: Setup and run cloudflared tunnel
# PowerShell: "iwr -useb https://gh-proxy.com/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex"
# Path："C:\ProgramData\cloudflared\"

# Color output function
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

# Variables
$cloudflaredUrl = "https://gh-proxy.com/https://github.com/cloudflare/cloudflared/releases/download/2025.5.0/cloudflared-windows-amd64.exe"
$installDir = "$env:ProgramData\cloudflared"
$cloudflaredBin = Join-Path $installDir "cloudflared.exe"
$logPath = Join-Path $installDir "cloudflared.log"
$serviceName = "CloudflaredTunnel"
$scPath = Join-Path $env:SystemRoot "System32\sc.exe"

# Create installation directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Download cloudflared
if (Test-Path $cloudflaredBin) {
    Write-Color "cloudflared.exe already exists at: $cloudflaredBin" Green
} else {
    Write-Color "Downloading cloudflared to: $cloudflaredBin" Cyan
    try {
        Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredBin -UseBasicParsing
        Write-Color "Download completed successfully." Green
        Write-Color "File location: $cloudflaredBin" Yellow
    } catch {
        Write-Color "Download failed, please check network connection or URL." Red
        Write-Color "Error: $($_.Exception.Message)" Red
        exit 1
    }
}

# Check for existing service
$serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($serviceExists) {
    Write-Color "Detected existing cloudflared service: $serviceName" Yellow
    $uninstall = Read-Host "Do you want to uninstall the old service? (y/n)"
    if ($uninstall -eq "y" -or $uninstall -eq "Y") {
        Write-Color "Uninstalling old service..." Cyan
        Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
        & $scPath delete $serviceName | Out-Null
        Remove-Item -Force $logPath -ErrorAction SilentlyContinue
        Write-Color "Service uninstalled." Green
    } else {
        Write-Color "Keeping old service, only updating running address." Yellow
    }
}

# Mode selection
Write-Color "`nPlease select running mode:" Yellow
Write-Host "1) Temporary run (foreground run and display trycloudflare domain)"
Write-Host "2) Background run (register as system service)"
$mode = Read-Host "Please enter 1 or 2"

# Get local address
$localAddr = Read-Host "Please enter local service address (e.g., 127.0.0.1:8080)"

if ($mode -eq "1") {
    Write-Color "Running cloudflared in temporary mode..." Cyan
    Write-Color "Starting cloudflared process..." Yellow
    
    # Start cloudflared process with proper output redirection
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $cloudflaredBin
    $processInfo.Arguments = "tunnel --url $localAddr"
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    
    # Register event handlers for real-time output reading
    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder
    $domain = $null
    
    Register-ObjectEvent -InputObject $process -EventName "OutputDataReceived" -Action {
        param($sender, $e)
        if ($e.Data) {
            [void]$Event.MessageData.stdoutBuilder.AppendLine($e.Data)
            $line = $e.Data
            if ($line -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                $Event.MessageData.domain = $matches[0]
            }
        }
    } -MessageData @{stdoutBuilder = $stdoutBuilder; domain = [ref]$domain} | Out-Null
    
    Register-ObjectEvent -InputObject $process -EventName "ErrorDataReceived" -Action {
        param($sender, $e)
        if ($e.Data) {
            [void]$Event.MessageData.stderrBuilder.AppendLine($e.Data)
            $line = $e.Data
            if ($line -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                $Event.MessageData.domain = $matches[0]
            }
            # Write real-time error output
            Write-Host $e.Data -ForegroundColor Gray
        }
    } -MessageData @{stderrBuilder = $stderrBuilder; domain = [ref]$domain} | Out-Null

    # Start the process
    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    
    Write-Color "Waiting for tunnel URL (watching output)..." Yellow
    
    # Wait for the domain to be found or timeout
    $timeout = 60
    for ($i = 0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        
        # Check all output for the URL
        $allOutput = $stdoutBuilder.ToString() + $stderrBuilder.ToString()
        if ($allOutput -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $domain = $matches[0]
            break
        }
        
        if ($i % 5 -eq 0) {
            Write-Host "." -NoNewline
        }
    }
    
    Write-Host ""
    
    if ($domain) {
        Write-Color "`n=== TUNNEL CREATED SUCCESSFULLY ===" Green
        Write-Color "Public access URL: $domain" Green
        Write-Color "Local service: $localAddr" Cyan
        Write-Color "`nPress Ctrl+C to stop the tunnel" Yellow
    } else {
        Write-Color "Could not automatically extract the tunnel URL." Red
        Write-Color "But the tunnel may still be running. Check the output above." Yellow
        
        # Show recent output
        $recentOutput = $stderrBuilder.ToString().Split("`n") | Select-Object -Last 10
        Write-Color "`nRecent output:" Cyan
        foreach ($line in $recentOutput) {
            if ($line.Length -gt 0) {
                Write-Host $line
            }
        }
    }

    # Keep the process running
    try {
        $process.WaitForExit()
    } catch {
        Write-Color "`nProcess interrupted." Yellow
    } finally {
        # Clean up event handlers
        Get-EventSubscriber | Unregister-Event
        if (-not $process.HasExited) {
            $process.Kill()
        }
    }

} elseif ($mode -eq "2") {
    Write-Color "Registering as system service and running in background..." Cyan
    # Fixed: Use proper PowerShell string escaping
    $svcCmd = """$cloudflaredBin"" tunnel --url $localAddr --logfile ""$logPath"""
    & $scPath create $serviceName binPath= $svcCmd start= auto | Out-Null
    Start-Sleep -Seconds 2
    
    try {
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-Color "Service started, waiting for log output..." Green

        $domain = $null
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            if (Test-Path $logPath) {
                $content = Get-Content $logPath -Raw
                if ($content -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                    $domain = $matches[0]
                    Write-Color "`nPublic access address:" Green
                    Write-Color "$domain" Green
                    break
                }
            }
        }

        if (-not $domain) {
            Write-Color "No access domain detected, please check log manually: $logPath" Red
        }
    } catch {
        Write-Color "Failed to start service. Error: $($_.Exception.Message)" Red
        Write-Color "Please check if you have administrator privileges." Yellow
    }

} else {
    Write-Color "Invalid option, please enter 1 or 2." Red
    exit 1
}
