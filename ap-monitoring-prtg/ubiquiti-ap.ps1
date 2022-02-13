# Fork of Monitor the Status of AP's on Unfi Controller in PRTG v0.8 27/06/2017
# Originally Published Here: https://kb.paessler.com/en/topic/71263
# modifications by angela-d licensed under GPL3
#
# Parameters in PRTG are: Controller's URI, Port, Site, Username and Password. Example without placeholders:
# -server 'unifi.domain.tld' -port '8443' -site 'default' -user 'admin' -password 'somepassword' -apip '172.16.5.1'
#
# -server '%host' -port '8443' -site 'default' -user '%windowsuser' -password '%windowspassword' -apip '172.16.5.1'
# This second option requires the device's address in PRTG to be the controller's address, the credentials for windows devices
# must also match the log-in/password from the controller. This way you don't leave the password exposed in the sensor's settings.
#
# It's recommended to use larger scanning intervals for exe/xml scripts. Please also mind the 50 exe/script sensor's recommendation per probe.
# The sensor will generate SOME alerts by default; after creating your sensor, define limits accordingly.
# This sensor is to be considered experimental. The Ubnt's API documentation isn't completely disclosed.
#
#   Source(s):
#   http://community.ubnt.com/t5/UniFi-Wireless/little-php-class-for-unifi-api/m-p/603051
#   https://github.com/fbagnol/class.unifi.php
#   https://www.ubnt.com/downloads/unifi/5.3.8/unifi_sh_api
#   https://github.com/malle-pietje/UniFi-API-browser/blob/master/phpapi/class.unifi.php
#   https://ubntwiki.com/products/software/unifi-controller/api
param(
  [string]$server,
  [string]$port,
  [string]$site,
  [string]$user,
  [string]$password,
  [string]$apip,
  [string]$cacheLife = '-300'
)

# set a cache path
# this is in anticipation of a LOT of access points - reset the cache every 300s
# for any ap that checks in within that window, they can pull the static file, rather than making continuous network requests
# to get essentially the same data concurrently
[string]$logPath = ((Get-ItemProperty -Path "hklm:SOFTWARE\Wow6432Node\Paessler\PRTG Network Monitor\Server\Core" -Name "Datapath").DataPath) + "Logs (Sensors)\"
$cacheFile = $logPath + "unifi-api-cache.json"

#Ignore SSL Errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
#Define supported Protocols
[System.Net.ServicePointManager]::SecurityProtocol = @("Tls12","Tls11")
# Confirm Powershell Version.
if ($PSVersionTable.PSVersion.Major -lt 3) {
	Write-Output "<prtg>"
	Write-Output "<error>1</error>"
	Write-Output "<text>Powershell Version is $($PSVersionTable.PSVersion.Major) Requires at least 3. </text>"
	Write-Output "</prtg>"
	Exit
}
# Create $controller and $credential using multiple variables/parameters.
[string]$controller = "https://" + $server + ":" + $port
[string]$credential = "`{`"username`":`"$user`",`"password`":`"$password`"`}"

function controllerLogin(){

  # Perform the authentication and store the token to myWebSession
  try {
    $null = Invoke-Restmethod -Uri "$controller/api/login" -method post -body $credential -ContentType "application/json; charset=utf-8"  -SessionVariable myWebSession
  }catch{
  	Write-Output "<prtg>"
  	Write-Output "<error>1</error>"
  	Write-Output "<text>Authentication Failed: $($_.Exception.Message)</text>"
  	Write-Output "</prtg>"
  	Exit
  }

  #Query API providing token from first query.
  try {
    $jsonresultat = Invoke-Restmethod -Uri "$controller/api/s/$site/stat/device/" -WebSession $myWebSession
  }catch{

  	Write-Output "<prtg>"
  	Write-Output "<error>1</error>"
  	Write-Output "<text>API Query Failed: $($_.Exception.Message)</text>"
  	Write-Output "</prtg>"
  	exit
  }

  # create a cache - default depth in ps is 2, so we won't get a whole lot of interesting stuff without adding more depth
  # 100 is max, so this ensures we get -everything- possible; downside is a 11mb+ cache, but that's the beauty of caching it
  $jsonresultat | ConvertTo-Json -depth 100 | Out-File $cacheFile

}

# see if a cache exists, yet
if (Test-Path $cacheFile) {

  # cache is NOT older than $cacheLife (seconds ago), so use it
  if (!(Test-Path $cacheFile -OlderThan (Get-Date).AddSeconds($cacheLife))) {
    $jsonresultat = Get-Content -Raw -Path $cacheFile | ConvertFrom-Json
  } else {
    # stale cache.. obtain a new one
    controllerLogin
  }

} elseif (!(Test-Path $cacheFile)) {
  # cache does not yet exist
  controllerLogin
}


# Iterate jsonresultat
write-host "<prtg>"
# pull the ap info based on the ip address passed by the prtg params
foreach ($ap in ($jsonresultat.data | where-object { $_.ip -eq $apip})){

  # put some potentially useful info in the default message
  $defaultMessage = $ap.name + " - " + $ap.ip

  # if using ubiquiti switches, pop that data in there, too
  if ($ap.uplink.uplink_device_name) {
    $defaultMessage = "SSID: " + $ap.vap_table.essid + " " + $defaultMessage + "; Uplink: " + $ap.uplink.uplink_device_name
  }

  if ($ap.uplink.uplink_device_name -and $ap.uplink.uplink_remote_port) {
    $defaultMessage = $defaultMessage + ", Port: " + $ap.uplink.uplink_remote_port
  }

  Write-Host "<text>$($defaultMessage)</text>"

  # experience returns -1 if the ap isn't being used, so push that to 101 so prtg doesn't send false alerts for matching below the threshold
  # 101 so we have an indicator no one's on, 100 is 100 (good)
  if ($ap.satisfaction -eq '-1') {
    $satisfaction = '101'
  } else {
    $satisfaction = $ap.satisfaction
  }
  Write-Host "<result>"
  Write-Host "<channel>Experience</channel>"
  Write-Host "<value>$($satisfaction)</value>"
  Write-Host "<unit>Percent</unit>"
  Write-Host "<showChart>1</showChart>"
  Write-Host "<showTable>1</showTable>"
  Write-Host "<LimitMode>1</LimitMode>"
  Write-Host "<LimitMinError>89</LimitMinError>"
  Write-Host "<LimitMinErrorMsg>Wifi experience likely poor</LimitMinErrorMsg>"
  Write-Host "<LimitMinWarning>93</LimitMinWarning>"
  Write-Host "<LimitWarningMsg>Wifi experience not optiminal</LimitWarningMsg>"
  Write-Host "</result>"

  # differentiate between 5g and 2g radios
  $i = 0;
  foreach ($vap in ($ap.vap_table)){
    # ssid gets turded up when there's only 1 in use, so some duct taping is necessary
    if ($i -eq 0 -and $ap.vap_table.essid[$i].length -eq 1) {
      $ssid = $ap.vap_table.essid
    } else {
      $ssid = $ap.vap_table.essid[$i]
    }
    Write-Host "<result>"
    Write-Host "<channel>$($ssid) Channel</channel>"
    Write-Host "<value>$($ap.vap_table.channel[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>channel #</customUnit>"
    Write-Host "<showChart>0</showChart>"
    Write-Host "<showTable>0</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) High Wifi Retries</channel>"
    Write-Host "<value>$($ap.vap_table.anomalies_bar_chart.high_wifi_retries[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>retries</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "<LimitMode>1</LimitMode>"
    Write-Host "<LimitMaxWarning>10</LimitMaxWarning>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) Avg. Client Signal</channel>"
    Write-Host "<value>$($ap.vap_table.avg_client_signal[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>RSSI</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "<LimitMode>1</LimitMode>"
    Write-Host "<LimitMinError>-70</LimitMinError>"
    Write-Host "<LimitMinErrorMsg>High Avg. RSSI; consider reducing TX strength</LimitMinErrorMsg>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) DNS Latency</channel>"
    Write-Host "<value>$($ap.vap_table.dns_avg_latency[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>avg</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "<LimitMode>1</LimitMode>"
    Write-Host "<LimitMaxWarning>119</LimitMaxWarning>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) RX Bytes</channel>"
    Write-Host "<value>$($ap.vap_table.rx_bytes[$i])</value>"
    Write-Host "<unit>BytesBandwidth</unit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) RX Packets</channel>"
    Write-Host "<value>$($ap.vap_table.rx_packets[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>packets</customUnit>"
    Write-Host "<showChart>0</showChart>"
    Write-Host "<showTable>0</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) RX Dropped</channel>"
    Write-Host "<value>$($ap.vap_table.rx_dropped[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>dropped</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) RX Errors</channel>"
    Write-Host "<value>$($ap.vap_table.rx_errors[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>errors</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "<LimitMode>1</LimitMode>"
    Write-Host "<LimitMaxWarning>4000</LimitMaxWarning>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TX Bytes</channel>"
    Write-Host "<value>$($ap.vap_table.tx_bytes[$i])</value>"
    Write-Host "<unit>BytesBandwidth</unit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TX Packets</channel>"
    Write-Host "<value>$($ap.vap_table.tx_packets[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>packets</customUnit>"
    Write-Host "<showChart>0</showChart>"
    Write-Host "<showTable>0</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TX Dropped</channel>"
    Write-Host "<value>$($ap.vap_table.tx_dropped[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>dropped</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TX Errors</channel>"
    Write-Host "<value>$($ap.vap_table.tx_errors[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>errors</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TX Retries</channel>"
    Write-Host "<value>$($ap.vap_table.tx_retries[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>retries</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "</result>"

    Write-Host "<result>"
    Write-Host "<channel>$($ssid) TCP Stalls</channel>"
    Write-Host "<value>$($ap.vap_table.tx_tcp_stats.stalls[$i])</value>"
    Write-Host "<unit>Custom</unit>"
    Write-Host "<customUnit>stalls</customUnit>"
    Write-Host "<showChart>1</showChart>"
    Write-Host "<showTable>1</showTable>"
    Write-Host "<LimitMode>1</LimitMode>"
    Write-Host "<LimitMaxError>1</LimitMaxError>"
    Write-Host "</result>"
  $i++
  }

  Write-Host "<result>"
  Write-Host "<channel>Connected Users</channel>"
  Write-Host "<value>$($ap.num_sta)</value>"
  Write-Host "<unit>Custom</unit>"
  Write-Host "<customUnit>users</customUnit>"
  Write-Host "<showChart>1</showChart>"
  Write-Host "<showTable>1</showTable>"
  Write-Host "</result>"

  Write-Host "<result>"
  Write-Host "<channel>EOL Status</channel>"
  Write-Host "<ValueLookup>prtg.standardlookups.boolean.statefalseok</ValueLookup>"
  Write-Host "<value>$($ap.model_in_eol)</value>"
  Write-Host "<showChart>0</showChart>"
  Write-Host "<showTable>0</showTable>"
  Write-Host "</result>"
}
  Write-Host "</prtg>"

exit 0
