Write-Verbose "Getting latest Version" -Verbose

class SourceForge {
    [string]        $Project = $Null
    [PSCustomObject]$LatestRelease = $Null
    
    SourceForge([string] $project) {
        $this.Project = $project
        $this.GetLatestRelease()
    }
   
    [void] GetLatestRelease() {
        $originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12        
        $this.GetLatestRelease('https://sourceforge.net/projects/{0}/best_release.json')
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    }

    [void] GetLatestRelease([string] $url) {
        $url = $url -f @($this.Project)
        Write-Debug "[SourceForge].GetLatestRelease URL: ${url}"
        $this.LatestRelease = ConvertFrom-Json (Invoke-WebRequest $url -UseBasicParsing).Content
    }
    
    [string] LatestVersion() {
        if (-not $this.LatestRelease) {
            $this.GetLatestRelease()
        }
        return $this.LatestRelease.release.filename.Split('/')[2]
    }

    [hashtable] LatestHash() {
        if (-not $this.LatestRelease) {
            $this.GetLatestRelease()
        }
        return @{
            'Algorithm' = 'MD5';
            'Hash' = $this.LatestRelease.release.md5sum.ToUpper();
        }
    }
}

$7zip = [SourceForge]::new('sevenzip')

$Version = $7zip.LatestVersion() 

# get Numbers from String

$Version = $Version -replace("[^\d]","")

# Silent Install 7-Zip
# http://www.7-zip.org/download.html 

# Path for the workdir
$workdir = 'C:\Installer'

Write-Verbose "Creating Working Directory: $workdir" -Verbose

# Check if work directory exists if not create it

If (!(Test-Path -Path $workdir -PathType Container))
{ New-Item -Path $workdir  -ItemType directory }

# Download the installer
Write-Verbose "Downloading 7-Zip Version $Version" -Verbose

$source = "http://www.7-zip.org/a/7z$Version-x64.exe"

$destination = "$workdir\7-Zip.exe"

# Check if Invoke-Webrequest exists otherwise execute WebClient

if (Get-Command 'Invoke-Webrequest')
{
     Invoke-WebRequest $source -OutFile $destination
}
else
{
    $WebClient = New-Object System.Net.WebClient
    $webclient.DownloadFile($source, $destination)
}

Invoke-WebRequest $source -OutFile $destination 

# Start the installation
Write-Verbose "Install 7-Zip Version $Version" -Verbose

$UnattendedArgs='/S'
$File='"' + $workdir + '\7-zip.exe"'

(Start-Process $File $UnattendedArgs -Wait -Passthru).ExitCode

# Remove the installer

Write-Verbose "Delete Working Directory" -Verbose

Remove-Item $workdir -Recurse -Force 
