﻿# RNDR Watchdog
# Generated by: Anthony Morella
# Generated on: 11/09/2020
# Donations ETH 0x39A6467226E55587D6de0DAB1EB696dAeC3EECAc (gravitymaster.eth)

#Get Admin
param([switch]$Elevated)
function Test-Admin {
  $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if ((Test-Admin) -eq $false) {
  if ($elevated) {
    # tried to elevate, did not work, aborting
  } 
  else {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
  }
  exit
}

# Set active path to script-location:
$scriptpath = $MyInvocation.MyCommand.Path
if (!$scriptpath) {
  $scriptpath = $psISE.CurrentFile.Fullpath
}
if ($scriptpath) {
  $scriptpath = Split-Path $scriptpath -Parent
}

Import-Module "$PSScriptRoot\functions.ps1"

#Set Window size
Set-WindowSize 80 50
[console]::bufferwidth = 32766

#Main Vars
$version = 1109
$mainpath = $scriptpath
$logpath = "$mainpath\logs"
$logFile = "$logpath\RNDRWatchdog.log"
$logFile1 = "$env:LOCALAPPDATA/OtoyRndrNetwork/rndr_log.txt"
$logFilejobs = "$logpath\RNDRJobs.log"
#$lastboot = (Get-CimInstance -ComputerName localhost -Class CIM_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LastBootUpTime )
$PGCurrentUsage = 0
$PGAllocatedBaseSize = 0 
$PGPeakUsage = 0
$startdate = Get-Date
$appRestartCount = 0
$appRestartDate = Get-Date
$progressArray = "|", "/", "-", "\"
$arrayIndex = 0
$rndrsrv = "TCPSVCS"
$nvidiasmipath = $env:ProgramW6432 + "\NVIDIA Corporation\NVSMI\"
$rndrapp = "rndrclient.exe"
$router = Get-NetRoute | Where-Object -FilterScript { $_.NextHop -Ne "::" } | Where-Object -FilterScript { $_.NextHop -Ne "0.0.0.0" } | Where-Object -FilterScript { $_.RouteMetric -eq "0" } | ForEach-Object { $_.NextHop }
$sleep = 420 #Countdown Time sleep before reboot
$rndrwalletid = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name WALLETID).WALLETID
$etherscanapikey = 'ERKISXUQFM7UVXKHQV5CMUMDCMQVRW657Q'

#Create Logs Directory
If (!(test-path $logpath)) {
  New-Item -ItemType Directory -Force -Path $logpath 
}
Add-Content -Path $logFile -Value (Get-Date) -Encoding UTF8 -NoNewline
Add-Content -Path $logFile -Value ", RNDR Client Watchdog started/restart" -Encoding UTF8
Write-Host ""; ""
Write-Host $startdate
Write-Host -ForegroundColor Green "Starting RNDR Watchdog ..."
Write-Host ""

#Add path
Write-Host "Adding $nvidiasmipath to environment variable Path now..."
Set-Item -Path Env:Path -Value ($nvidiasmipath + ";" + $Env:Path)
 
#Start RNDR if not running
if ((Get-Process | Where-Object { $_.Name -eq $rndrsrv }).Count -lt 1) {
  $date = Get-Date
  Clear-Host
  Write-Host "Starting RNDR Client ..."
  Write-Host ""; ""
  Write-Host -ForegroundColor Yellow "======================================================="
  Write-Host -ForegroundColor Yellow "          Last checked $date"
  Write-Host -ForegroundColor Yellow "          RNDR Watchdog Uptime - $([math]::Round($TimeSpan.Totalhours,1)) hours"
  Write-Host -ForegroundColor Yellow "======================================================="
  & "$mainpath\Start-Cleanup.ps1"
  & "$mainpath\$rndrapp"
  $timeout = New-TimeSpan -Seconds 600
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  do { Start-sleep -Seconds 10 }
    until (((Get-Process | Where-Object { $_.Name -eq $rndrsrv }).Count -eq 2) -or ($stopwatch.elapsed -gt $timeout))
  Start-sleep -Seconds 60
} 

# Main RNDR Check Loop1
while ($true) {
  #Loop vars
  $date = Get-Date
  $rndrjobscompleted = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name JOBS_COMPLETED -errorAction SilentlyContinue).JOBS_COMPLETED
  $rndrpreviewssent = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name PREVIEWS_SENT -errorAction SilentlyContinue).PREVIEWS_SENT
  $rndrthumbnailssent = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name THUMBNAILS_SENT -errorAction SilentlyContinue).THUMBNAILS_SENT
  $rndrscore = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name SCORE -errorAction SilentlyContinue).SCORE
  $rndrappcrash1001a = Get-EventLog -LogName application -EntryType Information -InstanceId 1001 -message *rndr* -After ((Get-Date).AddMinutes(-1)) -errorAction SilentlyContinue
  #$rndrappcrash1001b = Get-EventLog -LogName application -EntryType Information -InstanceId 1001 -message *WUDFHost* -After ((Get-Date).AddMinutes(-1)) -errorAction SilentlyContinue
  $rndrappcrash1000a = Get-EventLog -LogName application -EntryType Error -InstanceId 1000 -message *rndr* -After ((Get-Date).AddMinutes(-1)) -errorAction SilentlyContinue
  #$rndrappcrash1000b = Get-EventLog -LogName application -EntryType Error -InstanceId 1000 -message *WUDFHost* -After ((Get-Date).AddMinutes(-1)) -errorAction SilentlyContinue
  $rndrvmemcrach = Get-EventLog -LogName system -EntryType Information -InstanceId 26 -After ((Get-Date).AddMinutes(-1)) -errorAction SilentlyContinue
  
  #RNDR Server check
  $RNDRProcessID = (Get-Process -name TCPSVCS -errorAction SilentlyContinue).id
  $regex_pid =  $RNDRProcessID.ForEach({ [RegEx]::Escape($_) }) -join '|'
  $RNDRServerCheck = if (Get-NetTCPConnection -State Established -RemotePort 443 | Select-Object * | Where-Object  {$_.OwningProcess -match $regex_pid})
                        {$true} else {$false}

  #$RNDRServerCheck = ((Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "104.20.39.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "104.20.40.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "104.22.52.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "172.67.38.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "99.84.174.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "52.54.211.*" -ErrorAction Silent) `
  #    -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "172.67.16.*" -ErrorAction Silent)
  #)

  $nodeuptime = (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime | ForEach-Object { $_.TotalHours }
  
  ##$etherscangetrndrbalanceapi = "https://api.etherscan.io/api?module=account&action=tokenbalance&contractaddress=0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24&address=$rndrwalletid&tag=latest&apikey=$etherscanapikey"
  #$etherscangetrndrbalanceget = Invoke-WebRequest -uri $etherscangetrndrbalanceapi | ConvertFrom-Json | Select-Object -ExpandProperty result
  #$etherscangetrndrbalance = (.000000000000000001 * $etherscangetrndrbalanceget).tostring("##########.##") 
  #$etherscangetrndrtoday = (Get-EtherDetails | Where-Object { $_.Time -ge ((Get-Date).AddDays(-1)) } | Select-Object -ExpandProperty RNDR | Measure-Object -sum).sum
  #$etherscangetrndrweek = (Get-EtherDetails | Where-Object { $_.Time -ge ((Get-Date).AddDays(-7)) } | Select-Object -ExpandProperty RNDR | Measure-Object -sum).sum
  #$etherscangetrndrmonth = (Get-EtherDetails | Where-Object { $_.Time -ge ((Get-Date).AddDays(-30)) } | Select-Object -ExpandProperty RNDR | Measure-Object -sum).sum
  #Error ID 26 = Low on virtual memory
  #Error ID 1000 = RNDR Application Crash
  #Error ID 10110-10110 DriverFrameWork-Usermode Crash Critical

  #Redo-Command -ScriptBlock {
  #Check is RNDR is running if not start 
  if ((Get-Process | Where-Object { $_.Name -eq $rndrsrv }).Count -lt 1) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "RNDR Client Not Running. Restarting."
    Write-Host ""; ""
    Exit-RNDR
    & "$mainpath\Start-Cleanup.ps1"
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR Client Restarted Process not running" -Encoding UTF8
    & "$mainpath\Start-Cleanup.ps1"
    & "$mainpath\$rndrapp"
  } 

  #Pause untill benchmark is complete 
  elseif ($null -eq ($rndrscore)) {
    do {
      Start-sleep -Seconds 10
      $rndrscore = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name SCORE -errorAction SilentlyContinue).SCORE  
      Write-Host "Waiting for benchmark to complete"
    }
    until ($null -ne ($rndrscore))
    Start-sleep -Seconds 30
  }

  #Check if RNDR app is hung and restart if true 
  elseif ($null -ne (Get-Process | Where-Object { $_.Name -eq $rndrsrv } | Where-Object { $_.Responding -like "False" })) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "RNDR Client Not Responding, Restarting App"
    Write-Host ""; ""
    Exit-RNDR
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR Client Not Responding, Restarting App" -Encoding UTF8
  }  

  #Check for RNDR DLL Crash Restart RNDR Client Error 1000
  elseif ($null -ne ($rndrappcrash1000a)) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "RNDR Faulting application Error 1000. Restarting App"
    Write-Host ""; ""
    Exit-RNDR
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR Faulting application Error 1000. Restarting App" -Encoding UTF8
  }  
  
  #Check for DLL Crash Restart RNDR Client Error 1000
  #elseif ($null -ne ($rndrappcrash1000b)) {
  #  $appRestartCount++
  #  $appRestartDate = Get-Date
  #  Clear-Host
  #  Write-Host -ForegroundColor Red "WUDFHost Faulting application Error 1000. Restarting App"
  #  Write-Host ""; ""
  #  Exit-RNDR
  #  Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
  #  Add-Content -Path $logFile -Value ", WUDFHost Faulting application Error 1000. Restarting App" -Encoding UTF8
  #}  

  #Check for DLL Crash Restart RNDR Client Error 1001
  elseif ($null -ne ($rndrappcrash1001a)) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "RNDR FaultFault bucket Error 1001. Restarting App"
    Write-Host ""; ""
    Exit-RNDR
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR FaultFault RNDR bucket Error 1001. Restarting App" -Encoding UTF8
  }  
  
  #Check for WUDFHost Crash Restart RNDR Client Error 1001
  #elseif ($null -ne ($rndrappcrash1001b)) {
  #  $appRestartCount++
  #  $appRestartDate = Get-Date
  #  Clear-Host
  #  Write-Host -ForegroundColor Red "RNDR FaultFault bucket Error 1001. Restarting App"
  #  Write-Host ""; ""
  #  Exit-RNDR
  #  Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
  #  Add-Content -Path $logFile -Value ", RNDR FaultFault WUDFHost bucket Error 1001. Restarting App" -Encoding UTF8
  #}  

  #Check for VRAM error Reboot Computer
  elseif ($null -ne ($rndrvmemcrach)) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "VRAM Error Restarting Computer"
    Write-Host ""; ""
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR VRAM Crash Reboot" -Encoding UTF8
    Exit-RNDR
    Start-CountdownTimer -Seconds $sleep
    Restart-Computer -Force
  }
  
  #Check for RNDR App Connection to Server restart app if
 # elseif (($RNDRServerCheck) -eq $False) {
 #   $appRestartCount++
 #   $appRestartDate = Get-Date
 #   Clear-Host
 #   Write-Host -ForegroundColor Red "No connection to RNDR Client Server. Restarting App"
 #   Write-Host ""; ""
 #  Exit-RNDR
 #   Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
 #   Add-Content -Path $logFile -Value ", No connection to RNDR Client Server" -Encoding UTF8
 # }  

  #Check connection to Router, reboot if False
  #elseif (-not (Test-Connection $router -Count 1 -Quiet)) {
  #  Write-host "Can not connect to router will reboot in 120 seconds"
  #  Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
  #  Add-Content -Path $logFile -Value ", No connection router reboot" -Encoding UTF8
  #  Exit-RNDR
  #  Start-CountdownTimer -Seconds $sleep
  #  Restart-Computer -Force
  #}

  #RNDR is Running
  else {
    Clear-Host
    Write-Host -ForegroundColor Green "GravityMasters RNDR Watchdog"
    Write-Host -ForegroundColor Green "RNDR Client Is Running " -NoNewline
    Write-Host -ForegroundColor Green $progressArray[$arrayIndex]
    Write-Host ""
    if ($arrayIndex -lt 3) {
      $arrayIndex++
    }
    else {
      $arrayIndex = 0
    }
    if ($appRestartCount -gt 0) {
      Write-Host "Client restarted" $appRestartCount "times. Last client restart date:" $appRestartDate
    }
  }
  
  #Details Display
  $TimeSpan = $date - $startdate
  Write-Host -ForegroundColor Yellow "======================================================================="
  write-Host -ForegroundColor Yellow "   Donations ETH        - 0x39A6467226E55587D6de0DAB1EB696dAeC3EECAc"
  Write-Host -ForegroundColor Yellow "   Path                 - $mainpath"
  Write-Host -ForegroundColor Yellow "   Last checked         - $date"
  Write-Host -ForegroundColor Yellow "   RNDR Watchdog Uptime - $([math]::Round($TimeSpan.Totalhours,2)) hours"
  Write-Host -ForegroundColor Yellow "   Node Uptime          - $([math]::Round($nodeuptime,2)) hours"
  # Write-Host -ForegroundColor Yellow "   Last Boot Time       - $lastboot"
  Write-Host -ForegroundColor Yellow "   Router               - $router"
  Write-Host -ForegroundColor Yellow "   Jobs Complete        - $rndrjobscompleted"
  Write-Host -ForegroundColor Yellow "   Previews Sent        - $rndrpreviewssent"
  Write-Host -ForegroundColor Yellow "   Thumbnails Sent      - $rndrthumbnailssent"
  Write-Host -ForegroundColor Yellow "   OctaneBench Score    - $rndrscore"
  Write-Host -ForegroundColor Yellow "   ETH Wallet           - $rndrwalletid"
  Write-Host -ForegroundColor Yellow "   RNDR Connection      - $RNDRServerCheck"
  #Write-Host -ForegroundColor Yellow "   RNDR Balance         - $etherscangetrndrbalance"
  #Write-Host -ForegroundColor Yellow "   RNDR Past 24 Hr      - $etherscangetrndrtoday"
  #Write-Host -ForegroundColor Yellow "   RNDR Past Week       - $etherscangetrndrweek"
  Write-Host -ForegroundColor Yellow "====================================================================="
  
  #Show Page File Use
  Get-PageFileInfo
  
  #Show CPU and RAM info
  Get-CPURAM
  Write-Host -ForegroundColor Yellow "====================================================================="
 
  #Show Nvidia Details
  $header = 'IX', 'Name', 'GPU%', 'VRAM Used', 'VRAM%', 'Watts  ', 'Temp', 'PS', 'Fan%'
  get-nvidiasmi | ConvertFrom-Csv -Header $header | Format-Table
  Write-Host -ForegroundColor Yellow "====================================================================="
  
  #Tail RNDR Log files
  Get-Content $logFile1 | Where-Object {$_ -like ‘*ERROR*’} | Select-Object -Last 5 
  Write-Host -ForegroundColor Yellow "====================================================================="
  Get-Content $logFile | Select-Object -Last 5 
  Write-Host -ForegroundColor Yellow "====================================================================="

  #Add RNDR Job details to log
  $NewLogFileJobs = "$date,$rndrjobscompleted,$rndrthumbnailssent,$rndrpreviewssent"
  $NewLogFileJobs | Add-Content -Path $logFilejobs
  
  #Add RNDR Job details to log
  #$NewLogFileJobs = "$date,$rndrjobscompleted,$rndrthumbnailssent,$rndrpreviewssent" | Add-Content -Path $logFilejobs
  #$timer = New-Object Timers.Timer
  #$timer.Interval = 60000     # fire every 10min
  #$timer.AutoReset = $true  # do not enable the event again after its been fired
  #$timer.Enabled = $true
  #Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier Notepad  -Action $NewLogFileJobs 
  Start-sleep -Seconds 30
}