[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', 'task', Justification = 'Invoke-Build is alias only')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingCmdletAliases', 'assert', Justification = 'Invoke-Build is alias only')]
Param(
    [string] $AnalysePath = './',
    [string] $AnalyseSetting = './settings/ScriptAnalyzerSettings.psd1',
    [string] $TestPath = './tests',
    [switch] $Fix = $false
)

$script:AnalysePath = $AnalysePath
$script:AnalyseSetting = $AnalyseSetting
$script:TestPath = $TestPath
$script:Fix = $Fix
$script:RequiredModules = @(
    'PSScriptAnalyzer'
    'Pester'
)

task Init {
    $installParams = @{
        Confirm = $false
        Force = $true
        Name = $script:RequiredModules
    }
    Install-Module @installparams
}

task Analyse {
    Import-Module -Name PSScriptAnalyzer -MinimumVersion 1.0 -ErrorAction Stop
    $analyzerParams = @{
        Path = $script:AnalysePath
        Settings = $script:AnalyseSetting
        Fix = $script:Fix
    }
    $res = Invoke-ScriptAnalyzer @analyzerParams
    $res | Format-Table -Wrap -AutoSize
    assert (-not $res)
}

task Test {
    Import-Module -Name Pester -MinimumVersion 5.0 -ErrorAction Stop
    $pesterParams = @{
        Path = $script:TestPath
        CI = $true
    }
    Invoke-Pester @pesterParams
}

task . Analyse, Test
