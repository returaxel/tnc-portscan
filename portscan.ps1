$CSVSrc = Import-CSV ".\portscan_server.csv"

# Path
$SavePath = "C:\Temp\PortScan"

# Current Host
$TargetHost = $null
$TargetAddr = $null

# Scriptblock
$SB_ICMP = { 
    param($TargetHost,$TargetAddr,$SavePath) 
    $ProgressPreference = 'SilentlyContinue'

    if (tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Quiet) {
        #tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Detailed | 
        Out-File "$SavePath\$($TargetHost),ICMP,TRUE.txt" -Force
        Write-Output "$(Get-Date -Format HH:mm:ss.fff), ICMP,`t TRUE, $TargetHost, $TargetAddr"
    }
    else {
        Out-File "$SavePath\$($TargetHost),ICMP,FALSE.log"
        Write-Output "$(Get-Date -Format HH:mm:ss.fff),ICMP,`t FALSE, $TargetHost, $TargetAddr"
        }
    }

$SB_PORT = { 
    param($TargetHost,$TargetAddr,$SavePath,$port) 
    $ProgressPreference = 'SilentlyContinue'

    if (tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Quiet) {

        #  Initialize object
        $PortWhack = New-Object -TypeName Net.Sockets.TcpClient
        if (($PortWhack.BeginConnect($TargetAddr,[int]$port,$Null,$Null)).AsyncWaitHandle.WaitOne(2500)) {
            Out-File "$SavePath\$($TargetHost),$($port),TRUE.txt" -Force
            Write-Output "$(Get-Date -Format HH:mm:ss.fff), $($port),`t TRUE, $TargetHost, $TargetAddr"
        }
        else {
            Out-File "$SavePath\$($TargetHost),$($port),FALSE.log" -Force
            Write-Output "$(Get-Date -Format HH:mm:ss.fff), $($port),`t FALSE, $TargetHost, $TargetAddr"
        }
    }
    $PortWhack.Close()
}

# Iterate 
foreach ($row in $CSVSrc) {
    Write-Host "[info] Target: " -NoNewline -ForegroundColor Cyan
    $TargetHost = $row.Host
    $TargetAddr = $row.IP
    Write-Host $row -ForegroundColor DarkGray

    Start-Job -Name "Trace_$($row.Description)" -ScriptBlock $SB_ICMP -ArgumentList @($TargetAddr, $TargetHost ,$SavePath) | Out-Null

    $ports = $row.Ports -split " "
    foreach ($port in $ports) {
        Start-Job -Name "Prt_$($row.Description)" -ScriptBlock $SB_PORT -ArgumentList @($TargetAddr, $TargetHost,$SavePath, [int]$port) | Out-Null
    }
}

# Wait for jobs to finish
# Move inside loop to get grouped results for each host
$StillRunning = $true
while ($StillRunning) {
    Start-Sleep 5
    if ((Get-Job).State -notcontains "Running") {
        Receive-Job *
        $StillRunning = $false
        Remove-Job * 
    }
}