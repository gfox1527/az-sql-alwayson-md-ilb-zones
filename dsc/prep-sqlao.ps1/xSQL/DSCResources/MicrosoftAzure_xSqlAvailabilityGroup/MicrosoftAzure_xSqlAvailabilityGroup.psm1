﻿#
# xSqlAvailabilityGroup: DSC resource to configure a SQL AlwaysOn Availability Group.
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $ClusterName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [ValidateRange(1000,9999)]
        [UInt32] $PortNumber = 5022,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $bConfigured = Test-TargetResource -Name $Name -ClusterName $ClusterName -InstanceName $InstanceName -PortNumber $PortNumber -DomainCredential $DomainCredential -SqlAdministratorCredential $SqlAdministratorCredential

    $returnValue = @{
        Name = $Name
        ClusterName = $ClusterName
        InstanceName = $InstanceName
        PortNumber = $PortNumber
        DomainCredential = $DomainCredential.UserName
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
        Configured = $bConfigured
    }

    $returnValue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $ClusterName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [ValidateRange(1000,9999)]
        [UInt32] $PortNumber = 5022,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $computerInfo = Get-WmiObject Win32_ComputerSystem
    if (($computerInfo -eq $null) -or ($computerInfo.Domain -eq $null))
    {
        throw "Can't find node's domain name."
    }
    $domain = $ComputerInfo.Domain

    # Use the enumeration of cluster nodes as the replicas to add to the availability group.
    Write-Verbose -Message "Enumerating nodes in cluster '$($ClusterName)' ..."
    $nodes = Get-ClusterNode -Cluster $ClusterName
    Write-Verbose -Message "Found $(($nodes).Count) nodes."
   
    # Find an existing availability group with the same name and look up its primary replica.
    Write-Verbose -Message "Checking if SQL AG '$($Name)' exists ..."
    $bAGExist = $false
    foreach ($node in $nodes.Name)
    {
        $s = Get-SqlServer -InstanceName $node -Credential $SqlAdministratorCredential
        $group = Get-SqlAvailabilityGroup -Name $Name -Server $s
        if ($group)
        {
            Write-Verbose -Message "Found SQL AG '$($Name)' on instance '$($node)'."
            $bAGExist = $true

            $primaryReplica = Get-SqlAvailabilityGroupPrimaryReplica -Name $Name -Server $s
            if ($primaryReplica -eq $env:COMPUTERNAME)
            {
                Write-Verbose -Message "Instance '$($node)' is the primary replica in SQL AG '$($Name)'"
            }
        }
    }

    # Create the availability group and primary replica.
    if (!$bAGExist)
    {
        try
        {
            Write-Verbose -Message "Creating SQL AG '$($Name)' ..."
            $s = Get-SqlServer -InstanceName $InstanceName -Credential $SqlAdministratorCredential

            $newAG = New-Object -Type Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $s,$Name
            $newAG.AutomatedBackupPreference = 'Secondary'

            $newPrimaryReplica = New-Object -Type Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $newAG,$s.NetName
            $newPrimaryReplica.EndpointUrl = "TCP://$($s.NetName).$($domain):$PortNumber"
            $newPrimaryReplica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::SynchronousCommit
            $newPrimaryReplica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::Automatic
            $newAG.AvailabilityReplicas.Add($newPrimaryReplica)

            $s.AvailabilityGroups.Add($newAG)
            $newAG.Create()

            $primaryReplica = $s.NetName
        }
        catch
        {
            Write-Error "Error creating availability group '$($Name)'."
            throw $_
        }
    }

    # Create the secondary replicas and join them to the availability group.
    $nodeIndex = 0
    foreach ($node in $nodes.Name)
    {
        if ($node -eq $primaryReplica)
        {
            continue
        }

        $nodeIndex++

        Write-Verbose -Message "Adding replica '$($node)' to SQL AG '$($Name)' ..."

        Write-Verbose -Message "Getting primary replica"
        $s = Get-SqlServer -InstanceName $primaryReplica -Credential $SqlAdministratorCredential
        $group = Get-SqlAvailabilityGroup -Name $Name -Server $s

        # Ensure the replica is not currently in the availability group.
        $localReplica = Get-SqlAvailabilityGroupReplicas -Name $Name -Server $s | where { $_.Name -eq $node }
        if ($localReplica)
        {
            Write-Verbose -Message "Found replica '$($node)' in SQL AG '$($Name)', removing ..."
            $localReplica.Drop()
        }

        # Automatic failover can be specified for up to two secondary availability replicas.
        if ($nodeIndex -le 2)
        {
            $failoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::Automatic
        }
        else
        {
            $failoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::Manual
        }

        # Synchronous commit can be specified for up to two secondary availability replicas.
        if ($nodeIndex -le 2)
        {
            $availabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::SynchronousCommit
        }
        else
        {
            $availabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::AsynchronousCommit
        }

        Write-Verbose -Message "Add the replica to the availability group"
        $newReplica = New-Object -Type Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $group,$node
        $newReplica.EndpointUrl = "TCP://$($node).$($domain):$PortNumber"
        $newReplica.AvailabilityMode = $availabilityMode
        $newReplica.FailoverMode = $failoverMode
        $group.AvailabilityReplicas.Add($newReplica)
        $newReplica.Create()
        $group.Alter()

        Write-Verbose -Message "Join the replica to the availability group"
        $s = Get-SqlServer -InstanceName $node -Credential $SqlAdministratorCredential
        $s.JoinAvailabilityGroup($group.Name)
        $s.Alter()
    }
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $ClusterName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [ValidateRange(1000,9999)]
        [UInt32] $PortNumber = 5022,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Write-Verbose -Message "Checking if SQL AG '$($Name)' exists on instance '$($InstanceName) ..."

    $s = Get-SqlServer -InstanceName $InstanceName -Credential $SqlAdministratorCredential
    $group = Get-SqlAvailabilityGroup -Name $Name -Server $s

    if ($group)
    {
        Write-Verbose -Message "SQL AG '$($Name)' found."
        $true
    }
    else
    {
        Write-Verbose -Message "SQL AG '$($Name)' NOT found."
        $false
    }

    # TODO: add additional tests for AG membership, port, etc.
}


function Get-SqlAvailabilityGroup([string]$Name, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    $s.AvailabilityGroups | where { $_.Name -eq $Name }
}

function Get-SqlAvailabilityGroupPrimaryReplica([string]$Name, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    $s.AvailabilityGroups | where { $_.Name -eq $Name } | select -ExpandProperty 'PrimaryReplicaServerName'
}

function Get-SqlAvailabilityGroupReplicas([string]$Name, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    $s.AvailabilityGroups | where { $_.Name -eq $Name } | select -ExpandProperty 'AvailabilityReplicas'
}

function Get-SqlServer
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceName
    )
    
    $LoginCreationRetry = 0

    While ($true) {
        
        try {

            $list = $InstanceName.Split("\")
            if ($list.Count -gt 1 -and $list[1] -eq "MSSQLSERVER")
            {
                $ServerInstance = $list[0]
            }
            else
            {
                $ServerInstance = $InstanceName
            }
            
            [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

            $s = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance 
            
            if ($s.Information.Version) {
            
                $s.Refresh()
            
                Write-Verbose "SQL Management Object Created Successfully, Version : '$($s.Information.Version)' "   
            
            }
            else
            {
                throw "SQL Management Object Creation Failed"
            }
            
            return $s

        }
        catch [System.Exception] 
        {
            $LoginCreationRetry = $LoginCreationRetry + 1
            
            if ($_.Exception.InnerException) {                   
             $ErrorMSG = "Error occured: '$($_.Exception.Message)',InnerException: '$($_.Exception.InnerException.Message)',  failed after '$($LoginCreationRetry)' times"
            } 
            else 
            {               
             $ErrorMSG = "Error occured: '$($_.Exception.Message)', failed after '$($LoginCreationRetry)' times"
            }
            
            if ($LoginCreationRetry -eq 30) 
            {
                Write-Verbose "Error occured: $ErrorMSG, reach the maximum re-try: '$($LoginCreationRetry)' times, exiting...."

                Throw $ErrorMSG
            }

            start-sleep -seconds 60

            Write-Verbose "Error occured: $ErrorMSG, retry for '$($LoginCreationRetry)' times"
        }
    }
}

function Get-SqlInstanceName([string]$Node, [string]$InstanceName)
{
    $pureInstanceName = Get-PureSqlInstanceName -InstanceName $InstanceName
    if ("MSSQLSERVER" -eq $pureInstanceName)
    {
        $Node
    }
    else
    {
        $Node + "\" + $pureInstanceName
    }
}

function Get-PureSqlInstanceName([string]$InstanceName)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1)
    {
        $list[1]
    }
    else
    {
        "MSSQLSERVER"
    }
}

Export-ModuleMember -Function *-TargetResource
