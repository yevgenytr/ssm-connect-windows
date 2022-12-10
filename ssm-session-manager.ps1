# AWS Session Managenr connection with AWS CLI for Windows

# Check if the script is running in an elevated session or not
Write-Host "Checking for elevated permissions..."
if (-not([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
 {
    Write-Warning "Insufficient permissions to run this script. Open the PowerShell console as an administrator and run this script again."
    Break
}
else {
    Write-Host "Code is running as administrator. Go on executing the script..." -ForegroundColor Green
}

function awsPrereq {
    if (-not(Test-Path -Path $env:PROGRAMFILES\Amazon\AWSCLIV2\)) {
        Write-Host "Unable to find AWS CLI directory." -ForegroundColor Red
        Write-Host "Going to install AWS CLI." -ForegroundColor Green
        Write-Host "Downloading and installing AWS CLI..."
        $command = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
        Invoke-Expression $command
        try {
            Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -Outfile $env:TMP\AWSCLIV2.msi
            $arguments = "/i `"$env:TMP\AWSCLIV2.msi`" /quiet"
            Start-Process msiexec.exe -ArgumentList $arguments -Wait
        }
        catch {
            Write-Host "AWS CLI install failed!" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }

    }
    else {
        Write-Host "AWS CLI installed."
    }
}

function ssmpPrereq {
    Write-Host "Checking if Session Manager plugin exist..."
    if (-not(Test-Path -Path $env:PROGRAMFILES\Amazon\SessionManagerPlugin))
    {
        Write-Host "Session Manager plugin not found!" -ForegroundColor Red
        Write-Host "Installing Session Manager plugin for AWS CLI..." -ForegroundColor Green
        $command = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
        Invoke-Expression $command
        Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPlugin.zip" -Outfile $env:TMP\SessionManagerPlugin.zip
        Expand-Archive -Path $env:TMP\SessionManagerPlugin.zip -DestinationPath $env:TMP\smp
        Expand-Archive -Path $env:TMP\smp\package.zip -DestinationPath $env:PROGRAMFILES\Amazon\SessionManagerPlugin
        Write-Host "Registering SessionManager service..."
        New-Service -Name "session-manager-plugin" -BinaryPathName '"C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe"' -DisplayName "AWS Session Manager" -Description "Allows AWS CLI to create new sessions for remote conneciton." -StartupType Automatic
        # Using SC Because we can't do this in a PS cmdlet!
        sc.exe failure session-manager-plugin reset= 86400 actions= restart/1000/restart/1000
        #Start-Service 'session-manager-plugin'
    }
    else {
        Write-Host "Variables file found."
    }

}

function ssmpEnv {
    Write-Host "Checking if Session Maanager plugin exist in PATH environment variable..."
    if (($env:path).split(';') | Select-String -Pattern SessionManagerPlugin) {
        Write-Host "Variable exist."
        }
    else {
        Write-Host "Variable doesn't exist. Setting variable." -ForegroundColor Red
        $smpPath = "$env:PROGRAMFILES\Amazon\SessionManagerPlugin\bin\";
        $arrPath = $env:Path -split ';';
        $env:Path = ($arrPath + $smpPath) -join ';'
        }
}

# Run pre-requisites functions to determine what is missing
awsPrereq
ssmpPrereq
ssmpEnv

# Launch remote connection session wiuth variable from an external file
# Make sure that the file exist in the same path and include the right details.
Write-Host "Checking if variables files exist..."
if (-not(Test-Path -Path .\variables.ps1 -PathType Leaf))
    {
        Throw "Variables file not found!"
        Break
    }
    else {
        Write-Host "Variables file found."
    }

# Source the required env variable for AWS CLI from external file.
. ".\variables.ps1"

Write-Host "Connecting with Session Manager..."
# Next powershell session will going to have AWS CLI in the PATH environment variable. Now we run a full path.
Push-Location $env:PROGRAMFILES\Amazon\AWSCLIV2
.\aws.exe configure set aws_access_key_id $AWS_ACCESS_KEY_ID
.\aws.exe configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
.\aws.exe configure set default.region $AWS_DEFAULT_REGION
start-job -ScriptBlock {
    Start-Sleep -Seconds 5
    mstsc /v:localhost:3390 /f
}
.\aws.exe ssm start-session --target $SSM_TARGET --document-name AWS-StartPortForwardingSession --parameters portNumber="3389",localPortNumber="3390"
Pop-Location
