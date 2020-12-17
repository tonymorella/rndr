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
  $pinfo.Arguments = "--format=csv,noheader --query-gpu=pci.bus,name,utilization.gpu,memory.used,utilization.memory,power.draw,temperature.gpu,pstate,fan.speed"
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
  

#SetLockMemoryPages permissions
function SetLockMemoryPages {
    $TempLocation = "C:\Temp"
    $UserName = $env:UserName
    $ChangeFrom = "SeManageVolumePrivilege = "
    $ChangeFrom2 = "SeLockMemoryPrivilege = "
    $ChangeTo = "SeManageVolumePrivilege = $UserName,"
    $ChangeTo2 = "SeLockMemoryPrivilege = $UserName,"
    $fileName = "$TempLocation\SecPolExport.cfg"

    Remove-Item $fileName -ErrorAction SilentlyContinue
    secedit /export /cfg $filename
    (Get-Content $fileName) -replace $ChangeFrom, $ChangeTo | Set-Content $fileName
    if ((Get-Content $fileName) | Where-Object { $_.Contains("SeLockMemoryPrivilege") }) {
        Write-Host "Appending line containing SeLockMemoryPrivilege"
        (Get-Content $fileName) -replace $ChangeFrom2, $ChangeTo2 | Set-Content $fileName
    } else {
        Write-Host "Adding new line containing SeLockMemoryPrivilege"
        Add-Content $filename "`nSeLockMemoryPrivilege = $UserName"
    }
    Write-Host "Importing Security Policy…"
    secedit /configure /db secedit.sdb /cfg $fileName 1> $null
    Write-Host "Security Policy has been imported"
    Remove-Item $fileName -ErrorAction SilentlyContinue
}   
   
    