function Get-TargetResource
{
	param
	(
        [parameter(Mandatory = $true)]
	    [System.String]
	    $InstanceName,

        [parameter(Mandatory = $true)]
	    [System.String]
	    $OptimizationType
	)

    $OptimizationType = $OptimizationType.ToUpper()

    $bConfigured = Test-SqlInstanceOptimization -InstanceName $InstanceName -OptimizationType $OptimizationType

    $retVal = @{
        InstanceName = $InstanceName
        OptimizationType = $OptimizationType
        Configured = $bConfigured
    }

    $retVal
}

function Set-TargetResource
{
    param
	(
        [parameter(Mandatory = $true)]
	    [System.String]
	    $InstanceName,

        [parameter(Mandatory = $true)]
	    [System.String]
	    $OptimizationType
    )

    try
    {
        Set-SqlInstanceOptimization -InstanceName $InstanceName -OptimizationType $OptimizationType
    }
    catch
    {
        Write-Error "Error configuring storage optimization"
        throw $_
    }
}

function Test-TargetResource
{
    param
	(
        [parameter(Mandatory = $true)]
	    [System.String]
	    $InstanceName,

        [parameter(Mandatory = $true)]
	    [System.String]
	    $OptimizationType
	)
    
    $result = Test-SqlInstanceOptimization -InstanceName $InstanceName -OptimizationType $OptimizationType

    $result
}

function Test-SqlInstanceOptimization([string]$InstanceName, [string]$OptimizationType)
{
    if($OptimizationType -eq "OLTP")
    {
        $result1 = Test-SqlInstanceParameter -InstanceName $InstanceName -StartupParameter '-T1117' 
        $result2 = Test-SqlInstanceParameter -InstanceName $InstanceName -StartupParameter '-T1118'

        if($result1 -and $result2)
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' is already set."
            return $result1 -and $result2
        }
    }
    elseif($OptimizationType -eq "DW")
    {
        $result1 = Test-SqlInstanceParameter -InstanceName $InstanceName -StartupParameter '-T1117' 
        $result2 = Test-SqlInstanceParameter -InstanceName $InstanceName -StartupParameter '-T610'

        if($result1 -and $result2)
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' is already set."
            return $result1 -and $result2
        }
    }
    elseif($OptimizationType -eq "GENERAL")
    {
        return $true
    }
    
    $false
}

function Set-SqlInstanceOptimization([string]$InstanceName, [string]$OptimizationType)
{
    if($OptimizationType -eq "OLTP")
    {
        Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' ..."

        $result1 = Add-SqlInstanceParameter -InstanceName $InstanceName -StartupParameters @('-T1117','-T1118') 

        if($result1)
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' is set."
            return true;
        }
        else
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' failed to be set."
        }
    }
    elseif($OptimizationType -eq "DW")
    {
        $result1 = Add-SqlInstanceParameter -InstanceName $InstanceName -StartupParameter @('-T1117','-T610')

        if($result1)
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' is set."
            return true;
        }
        else
        {
            Write-Verbose -Message "Settings storage optimization option '$($OptimizationType)' failed to be set."
        }
    }
    elseif($OptimizationType -eq "GENERAL")
    {
        return $true
    }
    else
    {
        throw [System.ArgumentOutOfRangeException] "Storage optimization type $OptimizationType settings failed"
    }    
}

function Test-SqlInstanceParameter([string]$InstanceName, [string]$StartupParameter)
{
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env.ComputerName)

    $regKey= $reg.OpenSubKey("SOFTWARE\\Microsoft\\Microsoft SQL Server\\Instance Names\\SQL" )

    foreach($instance in $regkey.GetValueNames())
    {    
        if($instance -eq $InstanceName)
        { 
            $instanceRegName =  $regKey.GetValue($instance)

            $parametersKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceRegName\MSSQLServer\Parameters"

            $props = Get-ItemProperty $parametersKey

            $params = $props.psobject.properties | ?{$_.Name -like 'SQLArg*'} | select Name, Value

            
            foreach ($param in $params)
            {
                if($param.Value -eq $StartupParameter)
                {
                    return $true
                }
            }
        }
    }

    $false;
}


function Add-SqlInstanceParameter([string]$InstanceName, [string[]]$StartupParameters)
{
    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $env.ComputerName)

    $regKey= $reg.OpenSubKey("SOFTWARE\\Microsoft\\Microsoft SQL Server\\Instance Names\\SQL" )

    foreach($instance in $regkey.GetValueNames())
    {    
        if($instance -eq $InstanceName)
        { 
            $instanceRegName =  $regKey.GetValue($instance)
            
            $parametersKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceRegName\MSSQLServer\Parameters"

            $props = (Get-Item $parametersKey).GetValueNames()

            $argNumber = $props.Count

            foreach($param in $StartupParameters)
            {
                Write-Host "Adding Startup Argument:$argNumber"

                $newRegProp = "SQLArg"+($argNumber) 
            
                Set-ItemProperty -Path $parametersKey -Name $newRegProp -Value $param

                $argNumber = $argNumber + 1
            }
        }
    }
}

Export-ModuleMember -Function *-TargetResource