# Re-create the VMkernel port group to address a weird MAC address conflict that might arise between
# the port group and physical NICs in the infrastructure.
# re-creating the port group assigns a VMware MAC address
# Use at your own risk!

$SnapinTest = Get-PSSnapin | Select-String "vmware"
if ($SnapinTest -eq $null) { Add-PSSnapin *vm* }

#which VCenter are we connectin to?
$vCenterServer = Read-Host "Which vCenter are we Connecting To?"

#Get Hosts to work on
Connect-VIserver $vCenterServer
$vmhosts = Get-VMHost
$vmhosts = $vmhosts | % {$_.Name -replace "-m.wharton.private", ""} | sort-object
Disconnect-VIServer $vCenterServer -confirm:$false

#DNS Lookup FUnction
Function forward_dns
{
    $cmd = "nslookup " + $args[0] + " " + $ns
    $result = Invoke-Expression ($cmd)
    trap
    {
        $global:controlladns = $true
        $global:solved_ip = "No record found"
    continue
    }
        $global:controlladns = $false
        $global:solved_ip = $result.SyncRoot[4]
    if (-not $global:controlladns)
    {
        $leng = $global:solved_ip.Length -10
        $global:solved_ip =
        $global:solved_ip.substring(10,$leng)
    }
}

$root_pwd = ""
$placeholderIP = '10.0.1.6'

$vmhosts | % {

    $lowerstring = $_.ToLower()
     
    $first=$lowerstring[0]
    $length=$lowerstring.length
    $last=$lowerstring[($length-1)]
    $lastletter=$length-1

    $hostname = $lowerstring + "-m"
    forward_dns $hostname
    $OriginalHostIP = $solved_IP
    $password = $root_pwd + $lowerstring[0] + $lowerstring[$lastletter] + $length
    
    Connect-VIServer $hostname -user root -password $password
    
    #Create Placeholder vmKernel network
    $vmhost = Get-VMHost $hostname
    $vswitch = Get-VirtualSwitch -VMHost $vmhost -Name vSwitch0
    
    New-VMHostNetworkAdapter -vmhost $vmhost -PortGroup "VMkernel Placeholder" -VirtualSwitch $vswitch -VMotionEnabled $true -IP $placeholderIP -SubnetMask 255.255.248.0 -ManagementTrafficEnabled $true
    Get-VirtualPortGroup -VMHost $vmhost -Name "VMkernel Placeholder" | Set-VirtualPortGroup -VLanId 4
    
    #remove original bogus vmKernel network
    $vkernelAdapter = Get-VMHostNetworkAdapter | ? {$_.IP -like $OriginalHostIP}
    Remove-VMHostNetworkAdapter $vkernelAdapter -confirm:$false
    
    #connect to Placeholder IP address
    Disconnect-VIServer $hostname -confirm:$false
    Connect-VIServer $placeholderIP -user root -password $password
    
    #Remove old Port Group
    Get-VirtualPortGroup| ? {$_.Name -eq 'VMkernel Management'} | Remove-VirtualPortGroup  -confirm:$false
    
    #Re-create original vmKernel network
    $vmhost = Get-VMHost $placeholderIP
    $vswitch = Get-VirtualSwitch -VMHost $vmhost -Name vSwitch0
    
    New-VMHostNetworkAdapter -vmhost $vmhost -PortGroup "VMkernel Management" -VirtualSwitch $vswitch -VMotionEnabled $true -IP $OriginalHostIP -SubnetMask 255.255.248.0 -ManagementTrafficEnabled $true
    Get-VirtualPortGroup -VMHost $vmhost -Name "VMkernel Management" | Set-VirtualPortGroup -VLanId 4
    
    #remove placeholder vmKernel network
    $vkernelAdapter = Get-VMHostNetworkAdapter | ? {$_.IP -like $placeholderIP}
    Remove-VMHostNetworkAdapter $vkernelAdapter -confirm:$false
        
    #Close connections
    Disconnect-VIServer $placeholderIP -confirm:$false
    Connect-VIServer $hostname -user root -password $password
    
    #remove old Port Group
    Get-VirtualPortGroup| ? {$_.Name -eq 'VMkernel Placeholder'} | Remove-VirtualPortGroup -confirm:$false
    
    Disconnect-VIServer $hostname -confirm:$false
}