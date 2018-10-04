#
# Based on the script take from this website: http://www.isolation.se/change-mac-address-with-powershell-of-a-wireless-adapter/
#
class WirelessNetworkAdapterManager {
    [string]$CurrentSSID
    [string]$CurrentMacAddress
    [System.Net.IPAddress]$Ip
    [bool]$IsConnectionWorking = $false
    [bool]$IsConnected = $false
    [System.Object]$NetAdapter

    WirelessNetworkAdapterManager(){
        $this.UpdateNetadapterConfiguration()
        $this.UpdateSSID()
    }
    [void] UpdateNetadapterConfiguration () {
        $this.CurrentMacAddress = (Get-NetAdapter | Where-Object MediaType -EQ "Native 802.11").MacAddress
        $this.NetAdapter = (Get-NetAdapter | Where-Object MediaType -EQ "Native 802.11")
        $this.SetMediaConnectionState()
    }
    [Object] GetWifiNetworkAdapter() {
        return $this.NetAdapter;
    }
    [string] GetSSID()
    {
        return $this.CurrentSSID;
    }
    [void] UpdateSSID(){
        $this.CurrentSSID = (& netsh wlan show interfaces | Select-String ' SSID' | Foreach-Object { $_.ToString() -replace '.*SSID.*: ',''} );
    }
    [void]SetMediaConnectionState()
    {
        $state = (Get-NetAdapter | Where-Object MediaType -EQ "Native 802.11" | Select-Object -Property MediaConnectionState).MediaConnectionState
        if($state -eq "Connected") {
            $this.IsConnected = $true;
        }
        else {
            $this.IsConnected = $false;
        }
    }
    [string] SelectSSID() {
        $networkList = New-Object System.Collections.ArrayList;

        Write-Host "Currently not connected to a network. Choose one from the list: "
        (& netsh wlan show networks) | Foreach-Object { 
            $network = Select-String -InputObject $_.ToString() -pattern 'SSID';
            if($null -ne $network) {
                if($network.ToString().Length -eq 9) {
                    Write-Host $network.ToString()"Hidden-network";
                    $networkList.Add($network.ToString()) > $null;
                }
                else {
                    Write-Host $network;
                    $networkList.Add($network.ToString())  > $null;
                }
            }
        }

        Try {
            $NumberInListOfNetworks = Read-Host "Choose a SSID from the list. SSID [number] "
            while(("" -eq $NumberInListOfNetworks) -or ([int]$NumberInListOfNetworks -lt $networkList.Count )){
                Write-Host "That selection does not exist, try again."
                $NumberInListOfNetworks = Read-Host "Choose a SSID from the list. SSID [number] "
            }
            $SelectedNetwork = [int]$NumberInListOfNetworks;
            return ($networkList[$SelectedNetwork-1] -replace ".* ",'')
        }
        Catch{
            Write-Host "An error occured during the selection of a network.";
            Write-Host "Error message: " $_.exception.message
        }
        return ("")
    }

    [void] TestWifi ($probe)
    {
        if (Test-NetConnection -ComputerName $probe -CommonTCPPort HTTP -InformationLevel Detailed) { 
            $this.IsConnectionWorking = $true;
            Write-Host "Connection is working!"
        } 
        else { 
            $this.IsConnectionWorking = $false;
            Write-Host "Connection is not working..."
        }
    }
    [void] disconnectWifi() 
    {
        Write-Host "Disconnecting from: " $this.GetSSID()  -ForegroundColor Yellow
        (& netsh wlan disconnect | Out-Null)
        # Make sure the Release have happened, else it give it 2 sec extra. 
        $this.SetMediaConnectionState()
        $MaximumNumberOfTries=5;
        for($i=0; ($i -ne $MaximumNumberOfTries) -and ($true -eq $this.IsConnected);$i++)
        {
            Write-Output ("Disconnect had not completed, waiting 4 Seconds") -ForegroundColor Yellow
            Start-Sleep -Seconds 4
            $this.SetMediaConnectionState()
            if($i -eq 5){
                Write-Host "Unable to disconnect from " $this.GetSSID()
            }
        }
        $this.UpdateSSID();
    }

    [void] Connect() {
        $SSID = $this.SelectSSID()
        $this.Connect($SSID)
    }
    [void] Connect($pSsid) {
        $SSID = $pSsid;
        #Attempt to connect to the ssid provided as parameter.
        #
        #netsh wlan show interfaces:
        #Outputs multiple rows of connection configuration.
        #Current SSID is returned when the connection is completed.
        Write-Host "Connecting to wireless network " $SSID
        (& netsh wlan connect name=$SSID profile=$SSID)

        #Waiting for the connection process to finish
        Write-Host "Waiting for a connection.."
        Start-Sleep -Seconds 2

        $this.SetMediaConnectionState();
        $LimitWaitTime = 5
        for($i=0;($i -lt $LimitWaitTime) -and ($false -eq $this.IsConnected);$i++){
            Write-Host "Waiting for a connection to: " $SSID -ForegroundColor Yellow
            Start-Sleep -Seconds 4
            $this.SetMediaConnectionState();
        }
    }
    [string] RandomMac() {
        $mac = "02"
        $newmac = ""
        while ($mac.length -lt 12) 
        {
            $mac += "{0:X}" -f $(get-random -min 0 -max 16) 
        }

        $Delimiter = "-"
            for ($i = 0 ; $i -le 10 ; $i += 2) { 
                $newmac += $mac.substring($i,2) + $Delimiter 
            }
            $setmac = $newmac.substring(0,$($newmac.length - $Delimiter.length)) 
        return $setmac
    }
    [void] SetRandomMac()
    {
        if($this.IsConnected){
            Write-Host "You're still connected to a network. Do you wish to disconnect?"
            Write-Host "Yes: 1"
            Write-Host "No: 2"
            $WishToDisconnect = Read-Host "Disconnect? "
            if($WishToDisconnect -eq "1"){
                $this.disconnectWifi()
            }
            elseif($WishToDisconnect -eq "2"){
                Write-Host "Unable to proceed, exiting"
                Exit-PSHostProcess
            }
            return ;
        }
        $NewRandomMac = $this.RandomMac()

        Write-Output "New MAC Address to set: $NewRandomMac"

        $oldmac = $this.GetWifiNetworkAdapter().MACAddress
        Write-Output "OLD MAC Address: $oldmac"

        while ($oldmac -like $NewRandomMac)
        {
            Write-Host "Old MAC and New MAC are identical, generating a new MAC Address" -ForegroundColor Red
            $NewRandomMac = randomMac
            Write-Output "New MAC Address to set: $NewRandomMac"
        }

        $WifiAdapter = $this.GetWifiNetworkAdapter();
        try {
            Write-Host "Attempting to assign the new mac adress to the NetAdapter.."
            ($WifiAdapter | Set-NetAdapter -MacAddress $NewRandomMac -Confirm:$false)
            ($WifiAdapter | Disable-NetAdapter -Confirm:$false)
            ($WifiAdapter | Enable-NetAdapter -Confirm:$false)
            Write-Host "Successfully set a new mac adress: " $WifiAdapter.MacAddress
        }
        catch {
            Write-Host "An error occured during the process of setting a new random MacAddress to NetAdapter " $WifiAdapter.ifDesc
            Write-Host "Error message: " 
            Write-Host $_.exception.message;
        }
    }
    #End of class
}

function HasAdminPrivileges()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        $UserInput = ""
        Write-Host "Current instance of powershell is not running with admin privileges, would you like us to escalate them for you?"
        Write-Host "1: Yes" -ForegroundColor Green
        Write-Host "2: No(Default)" -ForegroundColor Red
        $UserInput = Read-Host "Answer: "
        if($UserInput -eq "1"){
            Write-Host $MyInvocation.MyCommand.Path
            # Start-Process powershell.exe "-File",('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
            Start-Process powershell.exe "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; 
            # Read-Host "Exit?"
            Exit;
        }
        elseif($UserInput -eq "2") {
            Write-Host "Unable to proceed, exiting."
            Exit;
        }
        else {
            Write-Host "No such option exists, exiting..."
            Exit;
        }
    }
}


#
#
#
#
# Script start
#
#
#
#

#
# Script need admin privileges in order to set interface parameters
#
HasAdminPrivileges

$WirelessAdapter = [WirelessNetworkAdapterManager]::new()

if(!$WirelessAdapter.IsConnected)
{
    $WirelessAdapter.SetRandomMac();
    Write-Host "Would you like to connect to a network?"
    Write-Host "Yes: 1"
    Write-Host "No: 2"
    $WouldLikeToConnect = Read-Host "Connect? "
    if($WouldLikeToConnect -eq "1"){
        $WirelessAdapter.Connect()
        $WirelessAdapter.TestWifi("www.msftncsi.com")
    }
}
else
{
    $PreviousSSID = $WirelessAdapter.GetSSID()
    $WirelessAdapter.disconnectWifi()
    $WirelessAdapter.SetRandomMac()
    $WirelessAdapter.Connect($PreviousSSID);
    $WirelessAdapter.TestWifi("www.msftncsi.com")
}