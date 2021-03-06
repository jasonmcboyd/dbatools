﻿function Add-DbaPfDataCollectorCounter {
    <#
        .SYNOPSIS
            Adds a Performance Data Collector Counter.

        .DESCRIPTION
            Adds a Performance Data Collector Counter.

        .PARAMETER ComputerName
            The target computer. Defaults to localhost.

        .PARAMETER Credential
            Allows you to login to $ComputerName using alternative credentials. To use:

            $cred = Get-Credential, then pass $cred object to the -Credential parameter.
    
        .PARAMETER CollectorSet
            The Collector Set name.

        .PARAMETER Collector
            The Collector name.
    
        .PARAMETER Counter
            The Counter name. This must be in the form of '\Processor(_Total)\% Processor Time'.
    
        .PARAMETER InputObject
            Accepts the object output by Get-DbaPfDataCollector via the pipeline.
    
        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
                   
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
        .NOTES
            Tags: PerfMon
            Author: Chrissy LeMaire (@cl), netnerds.net
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT
    
        .LINK
            https://dbatools.io/Add-DbaPfDataCollectorCounter

        .EXAMPLE
            Add-DbaPfDataCollectorCounter -ComputerName sql2017 -CollectorSet 'System Correlation' -Collector DataCollector01  -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
    
            Adds the '\LogicalDisk(*)\Avg. Disk Queue Length' counter within the DataCollector01 collector within the System Correlation collector set on sql2017.
    
        .EXAMPLE
            Get-DbaPfDataCollector | Out-GridView -PassThru | Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' -Confirm
    
            Allows you to select which Data Collector you'd like to add the counter '\LogicalDisk(*)\Avg. Disk Queue Length' on localhost and prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [Alias("DataCollector")]
        [string[]]$Collector,
        [Alias("Name")]
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [object[]]$Counter,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $setscript = {
            $setname = $args[0]; $Addxml = $args[1]
            $set = New-Object -ComObject Pla.DataCollectorSet
            $set.SetXml($Addxml)
            $set.Commit($setname, $null, 0x0003) #add or modify.
            $set.Query($setname, $Null)
        }
    }
    process {
        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }
        
        if (($InputObject | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count -le 3 -and $InputObject.ComputerName -and $InputObject.Name) {
            # it's coming from Get-DbaPfAvailableCounter
            $ComputerName = $InputObject.ComputerName
            $Counter = $InputObject.Name
            $InputObject = $null
        }
        
        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollector -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector
            }
        }
        
        if ($InputObject) {
            if (-not $InputObject.DataCollectorObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollector or Get-DbaPfAvailableCounter."
                return
            }
        }
        
        foreach ($object in $InputObject) {
            $computer = $InputObject.ComputerName
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            $setname = $InputObject.DataCollectorSet
            $collectorname = $InputObject.Name
            $xml = [xml]($InputObject.DataCollectorSetXml)
            
            foreach ($countername in $counter) {
                $node = $xml.SelectSingleNode("//Name[.='$collectorname']")
                $newitem = $xml.CreateElement('Counter')
                $null = $newitem.PsBase.InnerText = $countername
                $null = $node.ParentNode.AppendChild($newitem)
                $newitem = $xml.CreateElement('CounterDisplayName')
                $null = $newitem.PsBase.InnerText = $countername
                $null = $node.ParentNode.AppendChild($newitem)
            }
            $plainxml = $xml.OuterXml
            
            if ($Pscmdlet.ShouldProcess("$computer", "Adding $counters to $collectorname with the $setname collection set")) {
                try {
                    $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $plainxml -ErrorAction Stop
                    Write-Message -Level Verbose -Message " $results"
                    Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential -CollectorSet $setname -Collector $collectorname -Counter $counter
                }
                catch {
                    Stop-Function -Message "Failure importing $Countername to $computer." -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}