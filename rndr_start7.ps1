﻿# RNDR Watchdog
# Generated by: Anthony Morella
# Generated on: 11/04/2020
# Donations ETH 0x0517414451423b1C36f101f68f021E2781cfd2AC (gravitymaster.eth)


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

# Countdown timer
function Start-CountdownTimer {
  param (
    [int]$Days = 0,
    [int]$Hours = 0,
    [int]$Minutes = 0,
    [int]$Seconds = 0,
    [int]$TickLength = 1
  )
  $t = New-TimeSpan -Days $Days -Hours $Hours -Minutes $Minutes -Seconds $Seconds
  $origpos = $host.UI.RawUI.CursorPosition
  $spinner = @('|', '/', '-', '\')
  $spinnerPos = 0
  $remain = $t
  $d = ( get-date) + $t
  $remain = ($d - (get-date))
  while ($remain.TotalSeconds -gt 0) {
    Write-Host (" {0} " -f $spinner[$spinnerPos % 4]) -BackgroundColor White -ForegroundColor Black -NoNewline
    write-host (" {0}D {1:d2}h {2:d2}m {3:d2}s " -f $remain.Days, $remain.Hours, $remain.Minutes, $remain.Seconds)
    $host.UI.RawUI.CursorPosition = $origpos
    $spinnerPos += 1
    Start-Sleep -seconds $TickLength
    $remain = ($d - (get-date))
  }
  $host.UI.RawUI.CursorPosition = $origpos
  Write-Host " * "  -BackgroundColor White -ForegroundColor Black -NoNewline
  " Countdown finished"
}

#Set Windows Size Function
function Set-WindowSize {
  param([int]$x = $host.ui.rawui.windowsize.width,
    [int]$y = $host.ui.rawui.windowsize.heigth)
  $size = New-Object System.Management.Automation.Host.Size ($x, $y)
  $host.ui.rawui.windowsize = $size
}

#Kill RNDR APP Function
function Exit-RNDR {
  if ( $allProcesses = get-process -name TCPSVCS -errorAction SilentlyContinue ) {
    foreach ($oneProcess in $allProcesses) {
      $oneProcess.kill()
    } 
  }
} 

#Get Nvidia details function 
function get-nvidiasmi {
  $pinfo = New-Object System.Diagnostics.ProcessStartInfo
  $pinfo.FileName = "nvidia-smi.exe"
  $pinfo.Arguments = "--format=csv,noheader --query-gpu=index,name,utilization.gpu,memory.used,utilization.memory,power.draw,temperature.gpu,pstate,fan.speed"
  $pinfo.RedirectStandardError = $true
  $pinfo.RedirectStandardOutput = $true
  $pinfo.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $pinfo
  $p.Start() | Out-Null
  $p.WaitForExit()
  $output = $p.StandardOutput.ReadToEnd()
  $output += $p.StandardError.ReadToEnd()
  $output
}

#Retry function
function Redo-Command {
  [CmdletBinding()]
  param (
    [parameter(Mandatory, ValueFromPipeline)] 
    [ValidateNotNullOrEmpty()]
    [scriptblock] $ScriptBlock,
    [int] $RetryCount = 3,
    [int] $TimeoutInSecs = 30,
    [string] $SuccessMessage = "Command executed successfuly!",
    [string] $FailureMessage = "Failed to execute the command"
  )     
  process {
    $Attempt = 1
    $Flag = $true 
    do {
      try {
        $PreviousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        Invoke-Command -ScriptBlock $ScriptBlock -OutVariable Result              
        $ErrorActionPreference = $PreviousPreference
        Write-Verbose "$SuccessMessage `n"
        $Flag = $false
      }
      catch {
        if ($Attempt -gt $RetryCount) {
          Write-Verbose "$FailureMessage! Total retry attempts: $RetryCount"
          Write-Verbose "[Error Message] $($_.exception.message) `n"
          $Flag = $false
        }
        else {
          Write-Verbose "[$Attempt/$RetryCount] $FailureMessage. Retrying in $TimeoutInSecs seconds..."
          Start-Sleep -Seconds $TimeoutInSecs
          $Attempt = $Attempt + 1
        }
      }
    }
    While ($Flag)     
  }
}

#Convert Unix Time Function
Function ConvertFrom-UnixDate {
  Param(
    [int]$Date,
    [bool]$Utc = $true
  )
  $unixEpochStart = new-object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
  $Output = $unixEpochStart.AddSeconds($Date)
  if (-not $utc) {
    $Output = $Output.ToLocalTime()
  }
  $Output
}

Function Get-CPURAM {
  $totalRam = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).Sum
  $availMem = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue
  $cpuTime = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
  #$totaldisk = (Get-CimInstance Win32_LogicalDisk | Measure-Object -Property size)
  'CPU: ' + $cpuTime.ToString("#,0.0") + '%,' + ' RAM: ' + ($totalRam / 1gb) + 'MB' + ', Available RAM: ' + $availMem.ToString("N0") + 'MB (' + (104857600 * $availMem / $totalRam).ToString("#,0.0") + '%)'
}

Function Get-PageFileInfo {
  $PGCurrentUsage = (Get-CimInstance -Class Win32_PageFileUsage | Select-Object -ExpandProperty CurrentUsage | Measure-Object -sum).sum
  $PGAllocatedBaseSize = (Get-CimInstance -Class Win32_PageFileUsage | Select-Object -ExpandProperty AllocatedBaseSize | Measure-Object -sum).sum
  $PGPeakUsage = (Get-CimInstance -Class Win32_PageFileUsage | Select-Object -ExpandProperty PeakUsage | Measure-Object -sum).sum
  'PageFile - Used: ' + $PGCurrentUsage.ToString("#,#") + 'MB,  Allocated: ' + $PGAllocatedBaseSize.ToString("#,#") + 'MB,  Peek: ' + $PGPeakUsage.ToString("#,#") + 'MB'
}

Function Send-SendGridMail {
  param (
    [cmdletbinding()]
    [parameter()]
    [string]$ToAddress,
    [parameter()]
    [string]$ToName,
    [parameter()]
    [string]$FromAddress,
    [parameter()]
    [string]$FromName,
    [parameter()]
    [string]$Subject,
    [parameter()]
    [string]$Body,
    [parameter()]
    [string]$BodyAsHTML,
    [parameter()]
    [string]$Token
  )
  if (-not[string]::IsNullOrEmpty($BodyAsHTML)) {
    $MailbodyType = 'text/HTML'
    $MailbodyValue = $BodyAsHTML
  }
  else {
    $MailbodyType = 'text/plain'
    $MailBodyValue = $Body
  }
  # Create a body for sendgrid
  $SendGridBody = @{
    "personalizations" = @(
      @{
        "to"      = @(
          @{
            "email" = $ToAddress
            "name"  = $ToName
          }
        )
        "subject" = $Subject
      }
    )
    "content"          = @(
      @{
        "type"  = $mailbodyType
        "value" = $MailBodyValue
      }
    )
    "from"             = @{
      "email" = $FromAddress
      "name"  = $FromName
    }
  }
  $BodyJson = $SendGridBody | ConvertTo-Json -Depth 4
  #Create the header
  $Header = @{
    "authorization" = "Bearer $token"
  }
  #send the mail through Sendgrid
  $Parameters = @{
    Method      = "POST"
    Uri         = "https://api.sendgrid.com/v3/mail/send"
    Headers     = $Header
    ContentType = "application/json"
    Body        = $BodyJson
  }
  Invoke-RestMethod @Parameters
}

#Set Window size
Set-WindowSize 80 50
[console]::bufferwidth = 32766

#Main Vars
$mainpath = $scriptpath
$logpath = "$mainpath\logs"
$logFile = "$logpath\RNDRWatchdog.log"
$logFile1 = "$env:LOCALAPPDATA/OtoyRndrNetwork/rndr_log.txt"
$logFilejobs = "$logpath\RNDRJobs.log"
#$lastboot = (Get-CimInstance -ComputerName localhost -Class CIM_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LastBootUpTime )
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

Function Get-EtherDetails {
  #$unixdatetoday = ([int](Get-Date -UFormat %s -Millisecond 0))
  $etherscanget = "http://api.etherscan.io/api?module=account&action=tokentx&address=$rndrwalletid&startblock=0&endblock=999999999&sort=asc&apikey=$etherscanapikey"
  $etherscanresult = Invoke-WebRequest -uri $etherscanget | ConvertFrom-Json | Select-Object -ExpandProperty result
  $etherscanresulttimes = $etherscanresult | Select-Object timestamp -Last 20 | ForEach-Object { $_.timestamp } 
  $etherscanresultstimesfinal = ForEach ($etherscanresulttime in $etherscanresulttimes) { ConvertFrom-UnixDate $etherscanresulttime }
  $etherscanresultvalues = $etherscanresult | Select-Object value -Last 20 | ForEach-Object { $_.value }
  $etherscanresultsvaluesfinal = ForEach ($etherscanresultvalue in $etherscanresultvalues) { .000000000000000001 * $etherscanresultvalue }
  for ( $i = 0; $i -lt 20; $i++) {
    Write-Verbose "$($etherscanresultstimesfinal[$i]),$($etherscanresultsvaluesfinal[$i])"
    [PSCustomObject]@{
      Time = $etherscanresultstimesfinal[$i]
      RNDR = $etherscanresultsvaluesfinal[$i]
 
    }
  }
}

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
  
  #$rndrsrvpid = (Get-Process -Name $rndrsrv -ErrorAction SilentlyContinue).Id
  #$rndrsrvpid1 =  $rndrsrvpid.ForEach({ [RegEx]::Escape($_) }) -join '|'
  #$RNDRServerCheck = Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $rndrsrvpid1.State -like "Established" } | Where-Object {($rndrsrvpid1.RemotePort -eq "433") -or ($rndrsrvpid1.RemotePort -eq "3002")}
  
  #$RNDRProcessID = Get-Process -name TCPSVCS -errorAction SilentlyContinue
  #  foreach ($oneProcess in $RNDRProcessID) {
  #    if (Get-NetTCPConnection -state ESTABLISHED -RemotePort 443 -OwningProcess $oneProcess) {
  #      $RNDRServerCheck = $true
  #    } 
  #    else {
  #      $RNDRServerCheck = $false  
  #    }
  #  }

  #  $RNDRProcessID = (Get-Process -name TCPSVCS -errorAction SilentlyContinue).id
  #  $regex_pid =  $RNDRProcessID.ForEach({ [RegEx]::Escape($_) }) -join '|'
  #  $RNDRServerCheck = Get-NetTCPConnection -State Established -RemotePort 443 | Select-Object * | Where-Object  {$_.OwningProcess -match $regex_pid}

  $RNDRServerCheck = ((Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "104.20.39.*" -ErrorAction Silent) `
      -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "104.20.40.*" -ErrorAction Silent) `
      -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "172.67.38.*" -ErrorAction Silent) `
      -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "99.84.174.*" -ErrorAction Silent) `
      -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "52.54.211.*" -ErrorAction Silent) `
      -or (Get-NetTCPConnection -State Established -RemotePort 443 -RemoteAddress "172.67.16.*" -ErrorAction Silent)
  )

  #$nodeuptime = (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime | ForEach-Object { $_.TotalHours }
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
  if ((Get-Process | Where-Object { $_.Name -eq $rndrsrv }).Count -lt 2) {
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
    $timeout = New-TimeSpan -Seconds 600
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
      Start-sleep -Seconds 5 
      Write-Host "Waiting for RNDR to start"
    }
    until (((Get-Process | Where-Object { $_.Name -eq $rndrsrv }).Count -eq 2) -or ($stopwatch.elapsed -gt $timeout))
  } 

  #Pause untill benchmark is complete 
  elseif ($null -eq ($rndrscore)) {
    do {
      Start-sleep -Seconds 10
      $rndrscore = (Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\SOFTWARE\OTOY -Name SCORE -errorAction SilentlyContinue).SCORE  
      Write-Host "Waiting for benchmark to complete"
    }
    until ($null -ne ($rndrscore))
  }

  #Check if RNDR app is hung and restart if true 
  elseif ($null -ne (Get-Process | Where-Object { $_.Name -eq $rndrsrv } | Where-Object { $_.Responding -like "False" })) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "RNDR Client Hung, Restarting App"
    Write-Host ""; ""
    Exit-RNDR
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", RNDR Client Hung Restarted App" -Encoding UTF8
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
  elseif (($RNDRServerCheck) -eq $False) {
    $appRestartCount++
    $appRestartDate = Get-Date
    Clear-Host
    Write-Host -ForegroundColor Red "No connection to RNDR Client Server. Restarting App"
    Write-Host ""; ""
    Exit-RNDR
    Add-Content -Path $logFile -Value $appRestartDate -Encoding UTF8 -NoNewline
    Add-Content -Path $logFile -Value ", No connection to RNDR Client Server" -Encoding UTF8
  }  

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
  write-Host -ForegroundColor  "   Donations ETH        - 0x39A6467226E55587D6de0DAB1EB696dAeC3EECAc"
  Write-Host -ForegroundColor  "   Path                 - $mainpath"
  Write-Host -ForegroundColor  "   Last checked         - $date"
  Write-Host -ForegroundColor  "   RNDR Watchdog Uptime - $([math]::Round($TimeSpan.Totalhours,2)) hours"
  Write-Host -ForegroundColor  "   Node Uptime          - $([math]::Round($nodeuptime,2)) hours"
  # Write-Host -ForegroundColor "   Last Boot Time       - $lastboot"
  Write-Host -ForegroundColor  "   Router               - $router"
  Write-Host -ForegroundColor  "   Jobs Complete        - $rndrjobscompleted"
  Write-Host -ForegroundColor  "   Previews Sent        - $rndrpreviewssent"
  Write-Host -ForegroundColor  "   Thumbnails Sent      - $rndrthumbnailssent"
  Write-Host -ForegroundColor  "   OctaneBench Score    - $rndrscore"
  Write-Host -ForegroundColor  "   ETH Wallet           - $rndrwalletid"
  Write-Host -ForegroundColor  "   RNDR Connection      - $RNDRServerCheck"
  #Write-Host -ForegroundColor "   RNDR Balance         - $etherscangetrndrbalance"
  #Write-Host -ForegroundColor "   RNDR Past 24 Hr      - $etherscangetrndrtoday"
  #Write-Host -ForegroundColor "   RNDR Past Week       - $etherscangetrndrweek"
  Write-Host -ForegroundColor  "====================================================================="
  Write-Host -ForegroundColor  " "

  #Show Page File Use
  Get-PageFileInfo

  #Show CPU and RAM info
  Get-CPURAM
  
  Write-Host -ForegroundColor Yellow "====================================================================="
  
  #Show Nvidia Details
  $header = 'IX', 'Name', 'GPU%', 'VRAM Used', 'VRAM%', 'Watts  ', 'Temp', 'PS', 'Fan%'
  get-nvidiasmi | ConvertFrom-Csv -Header $header | Format-Table
  
  Write-Host -ForegroundColor Yellow "====================================================================="
  
  #Add RNDR Job details to log
  $NewLogFileJobs = "$date,$rndrjobscompleted,$rndrthumbnailssent,$rndrpreviewssent"
  $NewLogFileJobs | Add-Content -Path $logFilejobs

  #Tail RNDR Log files
  $logs1 = Get-Content $logFile | Select-Object -Last 5 
  $logs2 = Get-Content $logFile1 | Select-String -Pattern "ERROR" -SimpleMatch | Select-Object -Last 5 
  
  $logs1
  $logs2

  #Add RNDR Job details to log
  #$NewLogFileJobs = "$date,$rndrjobscompleted,$rndrthumbnailssent,$rndrpreviewssent" | Add-Content -Path $logFilejobs
  #$timer = New-Object Timers.Timer
  #$timer.Interval = 60000     # fire every 10min
  #$timer.AutoReset = $true  # do not enable the event again after its been fired
  #$timer.Enabled = $true
  #Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier Notepad  -Action $NewLogFileJobs 
  
  Start-sleep -Seconds 30
}