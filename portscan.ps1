<#
    .NOTES 
        now with less async and more wait
#>

param (
    [Parameter()][switch]$EnableFancyOutput
)

$CSVSrc = Import-CSV ".\portscan_server.csv" 

$ProgressPreference = 'SilentlyContinue'
#$ErrorActionPreference = 'Ignore'

# Current Host
$TargetHost = $null
$TargetAddr = $null

# TimeToWait (MS)
$WaitPort = 2500
$WaitICMP = 3750

# Return this object
[hashtable]$HostTable = @{}

function tnc-icmpstatus {
    param (
        $TargetHost,$TargetAddr
    )

    # ping HostName 
    $resultICMP = '{0} DNS' -f ([System.Net.NetworkInformation.Ping]::new().SendPingAsync($TargetHost)).AsyncWaitHandle.WaitOne($WaitICMP)

    if ($resultICMP.Split(' ')[0] -eq 'false') {
        # ping IP
        $resultICMP = '{0} IP' -f (([System.Net.NetworkInformation.Ping]::new().SendPingAsync($TargetAddr)).AsyncWaitHandle.WaitOne($WaitICMP))
    }

    # Write-Host "$(Get-Date -Format HH:mm:ss.fff),`tICMP,$resultICMP`t $TargetHost, $TargetAddr"
    return @($resultICMP, "$(Get-Date -Format HH:mm:ss.fff),`tICMP,$resultICMP`t $TargetHost, $TargetAddr")
}

# Iterate
foreach ($row in $CSVSrc) {

    $TargetHost = $row.Host
    $TargetAddr = $row.IP

    #Write-Host "[info] " -NoNewline
    #Write-Host "$TargetHost, $TargetAddr" -ForegroundColor DarkGray

    $NewHost = [hashtable]@{
        RawViewer = [System.Collections.Generic.List[string]]@()
        Description = $row.Description
        Host = $row.Host
        IP = $row.Ip
        ICMP = (tnc-icmpstatus $TargetAddr $TargetHost)
        Ports = @{}
    }
        
    if (($NewHost['ICMP'][0] -split ' ')[0] -and (-not[string]::IsNullOrEmpty($row.Ports))) {
        $ports = $row.Ports -split " "
        
        foreach ($port in $ports) {
            # Open TcpClient
            $PortWhack = New-Object -TypeName Net.Sockets.TcpClient
            # tnc -ComputerName $TargetAddr -Port $port -InformationLevel Quiet
            $NewHost['Ports'][$port] = if ( ($PortWhack.BeginConnect($TargetAddr,[int]$port,$Null,$Null)).AsyncWaitHandle.WaitOne($WaitPort) ) {
                $true
            }
            else {
                $false
            }
            $NewHost['RawViewer'].Add("$port, $($NewHost['Ports'][$port]), $TargetHost, $TargetAddr")
            $PortWhack.Close()
        }
    }

    $HostTable[$row.Host] = $NewHost
    
    # Avoid mistakes
    Clear-Variable TargetHost, TargetAddr

}

# Fluff
if ($EnableFancyOutput) {
    foreach ($h in $HostTable.Keys) {
        Write-Host "`n$($HostTable[$h].Host)" -NoNewline -ForegroundColor DarkGreen
        Write-Host "  $($HostTable[$h].IP)" -ForegroundColor DarkGray
        Write-Host `tICMP: $HostTable[$h].ICMP
        Write-Host "PORT ----------------------- RESULT" -ForegroundColor DarkGray
        $HostTable[$h].Ports | Out-Host
    }
} 

$HostTable.values.RawViewer | convertfrom-csv -Header Port, Result, Host, IP |  Out-GridView -OutputMode Multiple