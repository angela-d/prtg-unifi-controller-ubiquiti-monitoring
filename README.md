# Ubiquiti Unifi Monitoring with PRTG
Scripts I use to monitor Ubiquiti/Unifi equipment with PRTG.

- [Access Point Monitoring](ap-monitoring-prtg)


***

### Ubiquiti MIBs for SNMP Monitoring
I ended up not using Ubiquiti's MIBs in favor of [utilizing the API](ap-monitoring-prtg/README.md), but going to note what I did to get them going, incase it may be useful for someone else.

### Import Ubiquiti MIBs to PRTG
1. Download [Paessler's MIB importer tool](https://www.paessler.com/tools/mibimporter)
2. Obtain the Ubiquiti MIBs, I found them on [Ubiquiti's forum](https://community.ui.com/questions/SNMP-MIBs-for-UniFi-series-/b0f9d22c-b70c-47b9-93ba-2595fe726d55)
    - Some release notes have MIBs linked, too
3. The files have no details, instructions or file extension.  You need to rename them so the MIB importer tool can read them
    - Rename to **UBNT-UniFi-MIB.mib** and **UBNT-MIB.mib**
    - Note that both of the files need to remain in the same directory, together, when using the MIB importer tool (as noted by [Luciano Lingnau](https://kb.paessler.com/en/topic/80178-ubiquiti-unifi-wi-fi-controller-mib))
4. In the MIB importer tool: File > Import MIB File
5. Select the **two** MIBs you obtained from Ubiquiti's site > click Open
  
  
      ```text
    Import successful!


    Report for C:\Users\angela\Desktop\UBNT-MIB.mib:
    Sucessfully included files: 3 of 3
    Sucessfully imported OIDs: 2 of 2
    OIDs that were useful for PRTG: 2

    Report for C:\Users\angela\Desktop\UBNT-UniFi-MIB.mib:
    Sucessfully included files: 4 of 4
    Sucessfully imported OIDs: 52 of 52
    OIDs that were useful for PRTG: 52
    ```
  
  
6. Expand the carats to get a general idea of the channels available from these MIBs
    - None of the values have "friendly names," so adjust accordingly by modifying the **name** field (they're identical to the API values, so if you poked around in that, this stuff will be familiar)
    - Adjust **unit** accordingly, as well
7. Once you've made all of your customizations, select File > Save for PRTG Network Monitor
    - Save to `C:\Program Files (x86)\PRTG Network Monitor\snmplibs` (should default to there in the popup)
    - File extension *.oidlib
    - Save
8. Restart the PRTG application server (host server/Windows does not need to be restarted)


### Built a Sensor Using the Ubiquiti OID Library
1. Go to the **Device** you'd like to add your Ubiquiti access point under > Add Sensor
2. On the preceeding page, search for `SNMP Library`
3. Scroll down and select `Ubiquiti.oidlib` > Click OK
