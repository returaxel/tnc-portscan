<#
    .NOTES 
        now with less async and more wait
#>

param (
    [Parameter()][switch]$EnableFancyOutput
)

$CSVSrc = Import-CSV ".\portscan_server.csv" 

# Check for a range of ports... (just one per entry tho, :-)
foreach ($row in $CSVSrc) {
    
    $portArray = ($row.Ports -split ' ')
    $portRange = $portArray -Match "-"

    $row.ports = $row.ports -replace $portRange, ''

    [string]$portOutput = if ($portRange) {

        [int]$portLow, [int]$portHigh = $portRange -split '-'

        for ($i = $portLow; $i -lt $portHigh+1; $i++) {
            "$i"    
        }
    }

    $row.ports = '{0}{1}' -f $row.Ports, $portOutput
}

$ProgressPreference = 'SilentlyContinue'
#$ErrorActionPreference = 'Ignore'

# Current Host
$TargetHost = $null
$TargetAddr = $null

# TimeToWait (MS)
$WaitPort = 500

# Basic info
Write-Host "`nINTERFACE" -BackgroundColor DarkGray
Get-NetIPInterface -ConnectionState Connected -AddressFamily IPv4 |  Get-NetIPConfiguration | where Ipv4DefaultGateway -match "[\d.]" 

Write-Host "`nResolveDNS one.one.one.one" -BackgroundColor DarkGray
Resolve-DnsName one.one.one.one -NoHostsFile -Type A | Out-Host

Write-Host "`nTraceRoute 1.1.1.1" -BackgroundColor DarkGray
Test-NetConnection '1.1.1.1' -TraceRoute -InformationLevel Quiet

# Return this object
[hashtable]$HostTable = @{}

function tnc-icmpstatus {
    param (
        [string]$TargetHost,[ipaddress]$TargetAddr
    )

    # ping HostName 
    $returnICMP = switch ((([System.Net.NetworkInformation.Ping]::new().Send($TargetAddr).Status))) {
        DestinationHostUnreachable { $false }
        Default { $true }
    }

    # Write-Host "$(Get-Date -Format HH:mm:ss.fff),`tICMP,$returnICMP`t $TargetHost, $TargetAddr"
    return @("ICMP", $returnICMP, $TargetHost, $TargetAddr)
}

Write-Host "`n" -BackgroundColor DarkGray
Write-Host "`n[info] Iterate..."

# Iterate
foreach ($row in $CSVSrc) {

    $TargetHost = $row.Host
    $TargetAddr = $row.IP


    Write-Host "`t$TargetAddr`t`t$TargetHost" -ForegroundColor DarkGray

    $ResultICMP = (tnc-icmpstatus $TargetHost $TargetAddr)

    $NewHost = [hashtable]@{
        RawViewer = [System.Collections.Generic.List[string]]@()
        Description = $row.Description
        Host = $row.Host
        IP = $row.Ip
        ICMP = ($ResultICMP -Join ',')
        Ports = @{}
    }

    $NewHost['RawViewer'].Add($ResultICMP -Join ',')
        
    if ($ResultICMP[1] -and (-not[string]::IsNullOrEmpty($row.Ports))) {
        $ports = $row.Ports -split ' '
        
        foreach ($port in $ports) {

            # TcpClient
            $PortWhack = New-Object -TypeName Net.Sockets.TcpClient
            $ResultPort = ($PortWhack.BeginConnect($targetAddr,$port,$Null,$Null)).AsyncWaitHandle.WaitOne($WaitPort) 
            
            if ($ResultPort -eq 'true') {
                $NewHost['Ports'][$port] = $true
            }
            else {
                $NewHost['Ports'][$port] = $false
            }
            $NewHost['RawViewer'].Add("$port, $($NewHost['Ports'][$port]), $TargetHost, $TargetAddr")
            $PortWhack.Close()
        }
    }
    else {
        Write-Host "`tSkipped" -ForegroundColor Yellow
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
        Write-Host `t$HostTable[$h].ICMP
        Write-Host "PORT ----------------------- RESULT" -ForegroundColor DarkGray
        $HostTable[$h].Ports | Out-Host
    }
} 

$HostTable.values.RawViewer | convertfrom-csv -Header Port, Result, Host, IP |  Out-GridView -OutputMode Multiple