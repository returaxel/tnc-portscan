$CSVSrc = Import-CSV ".\portscan_server.csv" 

# Path
$SavePath = "C:\Temp\PortScan"

# INF
Write-Host "Getting status of the following hosts and ports"
Write-Host $row -ForegroundColor DarkGray

# Current Host
$TargetHost = $null
$TargetAddr = $null

# Scriptblock
$SB_ICMP = { 
    param($TargetHost,$TargetAddr) 
    $ProgressPreference = 'SilentlyContinue'
    if (tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Quiet) {
        tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Detailed | Out-File "$SavePath\$($TargetHost),ICMP,TRUE.txt"
        Write-Output "ICMP,`t`t TRUE, $TargetHost($TargetAddr)"
    }
    else {
        try {
            Out-File "$SavePath\$($TargetHost),ICMP,FALSE.log"
            Write-Output "ICMP,`t`tFALSE, $TargetHost($TargetAddr)"
        }
        catch {
        }
        }
    }

$SB_PORT = { 
    param($TargetHost,$TargetAddr,$port
    ) 
    $ProgressPreference = 'SilentlyContinue'

    if (tnc -ComputerName $TargetAddr -TraceRoute -InformationLevel Quiet) {
        if (tnc -ComputerName $TargetAddr -Port $port -InformationLevel Quiet) {
            Out-File "$SavePath\$($TargetHost),$($port),TRUE.txt" ; Write-Output "Port $($port),`t TRUE, $TargetHost($TargetAddr)"
        }
        else {
            try {
                Out-File "$SavePath\$($TargetHost),$($port),FALSE.log" ; Write-Output "Port $($port),`T FALSE, $TargetHost($TargetAddr)"
            }
            catch {
            }
        }
    }
}
    

Write-Host "Testing... ICMP"

# Iterate 
foreach ($row in $CSVSrc) {
        Write-Host "`n[info] Target: " -NoNewline -ForegroundColor Cyan
        $TargetHost = $row.Host
        $TargetAddr = $row.IP
        Write-Host "$TargetHost, $TargetAddr"

        Start-Job -Name "Trace_$($row.Description)" -ScriptBlock $SB_ICMP -ArgumentList @($TargetAddr, $TargetHost) | Out-Null

        $ports = $row.Ports -split " "
        foreach ($port in $ports) {
            Start-Job -Name "Prt_$($row.Description)" -ScriptBlock $SB_PORT -ArgumentList @($TargetAddr, $TargetHost, $port) | Out-Null
        }

    # Avoid mistakes
    Clear-Variable TargetHost, TargetAddr

    # Wait for jobs to finish
    $StillRunning = $true
    Write-Host "`nResults:" -ForegroundColor Blue
    while ($StillRunning) {
        Start-Sleep 3
        if ((Get-Job).State -notcontains "Running") {
            Receive-Job *
            $StillRunning = $false
            Remove-Job * 
        }
    }
}