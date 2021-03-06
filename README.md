# Create a SQL Server AlwaysOn Availability Group in an existing Azure VNET and Active Directory domain across Availability Zones using an Internal Load Balancer - 2021 Version

*Tests executed on 16/02/2021 show this template is working fine on Azure Public. You need to provision an AD domain and a virtual network with correct DNS resolution for domain names.*

This template will create a SQL Server AlwaysOn Availability Group using the PowerShell DSC Extension in an existing Azure Virtual Network and Active Directory environment. Both SQL Server 2016 and SQL Server 2017 are supported by this template. The SQL Server VMs will be provisioned across multiple Azure Availability Zones and requests will be directed to the Listener using the Internal Load Balancer (ILB) Standard.    
The provisioning process takes approximately 30 mins end to end.

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAaronSaikovski%2Faz-sql-alwayson-md-ilb-zones%2Fmain%2Fazuredeploy.json)  

## Deploying  Templates

You can deploy this sample directly through the Azure Portal or by using the scripts supplied in the root of the repo.

To deploy a sample using the Azure Portal, click the **Deploy to Azure** button found in the README.md of each sample.

To deploy the sample via the command line (using [Azure PowerShell or the Azure CLI](https://azure.microsoft.com/en-us/downloads/)) you can use the scripts.

Simple execute the script and pass in the folder name of the sample you want to deploy.  For example:

```PowerShell
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'australiaeast' -ArtifactsStagingDirectory '[foldername]'
```
```bash
azure-group-deploy.sh -a [foldername] -l eastus2 -u
```
If the sample has artifacts that need to be "staged" for deployment (Configuration Scripts, Nested Templates, DSC Packages) then set the upload switch on the command.
You can optionally specify a storage account to use, if so the storage account must already exist within the subscription.  If you don't want to specify a storage account
one will be created by the script or reused if it already exists (think of this as "temp" storage for AzureRM).

```PowerShell
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'australiaeast' -ArtifactsStagingDirectory 'az-sql-alwayson-md-ilb-zones' -UploadArtifacts 
```
```bash
azure-group-deploy.sh -a '301-sql-alwayson-md-ilb-zones' -l australiaeast -u
```
Tags: ``cluster, ha, sql, sql server 2016, sql server 2017, alwayson, availability zones``


