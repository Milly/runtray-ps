# Fix the culture of exception messages
[Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'

Describe 'runtray' {

    BeforeAll {
        # load test target
        $testRoot = Split-Path -Parent $PSScriptRoot
        $testSut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.ps1$', '.ps1'
        . "$testRoot\$testSut"

        # save $script:* vars
        $testSavedScriptVars = Get-Variable -Scope Script | Where-Object {
            $_.Name -match '^[a-z]' -And
                -Not $_.Options.HasFlag([System.Management.Automation.ScopedItemOptions]::Constant) -And
                -Not $_.Options.HasFlag([System.Management.Automation.ScopedItemOptions]::ReadOnly)
        } | ForEach-Object { @{Name=$_.Name; Value=$_.Value} }

        # helper functions

        function Merge-Config($obj1, $obj2) {
            $newObj = @{} + $obj1
            foreach ($key in $obj2.Keys) {
                $newObj[$key] = $obj2[$key]
            }
            $newObj
        }
    }

    BeforeEach {
        # resote $script:* vars
        foreach ($var in $testSavedScriptVars) {
            Set-Variable -Name $var.Name -Value $var.Value -Scope Script
        }
    }

    Describe 'Start-Main' {
        BeforeEach {
            $testConfig = ConvertFrom-Json `
                '{"name": "foobar", "executable": "TestDrive:\foo\file"}'
            Mock Get-AppName { 'my-foo-app' }
            Mock Get-Config { $testConfig }
            Mock Hide-Window {}
            Mock Start-FromShortcut {}
            Mock Install-Shortcut {}
            Mock Uninstall-Shortcut {}
            Mock Start-GUI {}
            Mock Get-Help {}
            $script:Command = 'help'
        }

        It 'should change $script:appName with the return value of Get-AppName' {
            Start-Main

            $script:appName | Should -BeExactly 'my-foo-app'
        }

        It 'should change $script:config with the return value of Get-Config' {
            Start-Main

            $script:config | Should -Be $testConfig
        }

        It "should call Start-FromShortcut if `$script:Command is 'start'" {
            $script:Command = 'start'

            Start-Main

            Should -Invoke Start-FromShortcut -Exactly 1 -ParameterFilter { -Not $PassThru }
        }

        It "should call Start-FromShortcut -PassThru if `$script:Command is 'start'" {
            $script:Command = 'start'
            $script:PassThru = $true

            Start-Main

            Should -Invoke Start-FromShortcut -Exactly 1 -ParameterFilter { $PassThru }
        }

        It "should call Install-Shortcut if `$script:Command is 'install'" {
            $script:Command = 'install'

            Start-Main

            Should -Invoke Install-Shortcut -Exactly 1 -ParameterFilter { -Not $PassThru }
        }

        It "should call Install-Shortcut -PassThru if `$script:Command is 'install'" {
            $script:Command = 'install'
            $script:PassThru = $true

            Start-Main

            Should -Invoke Install-Shortcut -Exactly 1 -ParameterFilter { $PassThru }
        }

        It "should call Uninstall-Shortcut if `$script:Command is 'uninstall'" {
            $script:Command = 'uninstall'

            Start-Main

            Should -Invoke Uninstall-Shortcut -Exactly 1
        }

        It "should call Start-GUI if `$script:Command is 'run'" {
            $script:Command = 'run'

            Start-Main

            Should -Invoke Start-GUI -Exactly 1
        }

        It 'should call Get-Help if $script:Command is default' {
            Start-Main

            Should -Invoke Get-Help -Exactly 1 -ParameterFilter { $Name -eq $script:scriptPath }
        }
    }

    Describe 'Get-Config' {
        BeforeEach {
            $testJsonFile = 'TestDrive:\my-app.json'
            $validMinimumConfig = @{
                executable='TestDrive:\foo\file.ext'
            }
        }

        AfterEach {
            if (Test-Path $testJsonFile) {
                Remove-Item $testJsonFile
            }
        }

        Context 'configuration file does not exist' {
            It 'should throws an exception' {
                {
                    Get-Config $testJsonFile
                } | Should -Throw "Cannot find path '$testJsonFile'*"
            }
        }

        Context 'configuration file with the same name as the script exists' {
            BeforeEach {
                ConvertTo-Json (Merge-Config $validMinimumConfig @{
                    name='my-foo-app'
                }) > $testJsonFile
                $script:scriptPath = 'TestDrive:\my-app.ps1'
            }

            It 'reads the configuration file with the same name as the script if no file is specified' {
                $actual = Get-Config
                $actual.name | Should -BeExactly 'my-foo-app'
            }
        }

        Context 'required property exist' {
            BeforeEach {
                ConvertTo-Json $validMinimumConfig > $testJsonFile
            }

            It 'should not throws an exception' {
                {
                    Get-Config $testJsonFile
                } | Should -Not -Throw
            }
        }

        Context 'required property does not exist' {
            BeforeEach {
                ConvertTo-Json @{
                    name='my-app'
                } > $testJsonFile
            }

            It 'should throws an exception with JSONPath' {
                {
                    Get-Config $testJsonFile
                } | Should -Throw '*Required property not exists: $.executable'
            }

            It 'should throws an exception with filepath' {
                {
                    Get-Config $testJsonFile
                } | Should -Throw "Configuration file is invalid: $testJsonFile*"
            }
        }

        Context 'additional unknown property exist' {
            BeforeEach {
                ConvertTo-Json (Merge-Config $validMinimumConfig @{
                    unknownFooBar=42
                }) > $testJsonFile
            }

            It 'should not throws an exception' {
                {
                    Get-Config $testJsonFile
                } | Should -Not -Throw
            }
        }

        Context 'wrong type property exist' {
            $testCases = @(
                @{
                    Config=@{name=42}
                    ExpectedType='string'
                    ExpectedJSONPath='$.name'
                }
                @{
                    Config=@{description=42}
                    ExpectedType='string'
                    ExpectedJSONPath='$.description'
                }
                @{
                    Config=@{executable=42}
                    ExpectedType='string'
                    ExpectedJSONPath='$.executable'
                }
                @{
                    Config=@{arguments=42}
                    ExpectedType='array'
                    ExpectedJSONPath='$.arguments'
                }
                @{
                    Config=@{workingdirectory=42}
                    ExpectedType='string'
                    ExpectedJSONPath='$.workingdirectory'
                }
                @{
                    Config=@{shutdownwait='42'}
                    ExpectedType='int'
                    ExpectedJSONPath='$.shutdownwait'
                }
            )
            It 'should throws an exception with JSONPath' -TestCases $testCases {
                Param($Config, $ExpectedType, $ExpectedJSONPath)
                ConvertTo-Json (Merge-Config $validMinimumConfig $Config) > $testJsonFile

                {
                    Get-Config $testJsonFile
                } | Should -Throw "*Property type is not ``[$ExpectedType``]: $ExpectedJSONPath"
            }
        }

        Context 'optional property does not exist' {
            BeforeEach {
                ConvertTo-Json $validMinimumConfig > $testJsonFile
            }

            $testCases = @(
                @{Prop='name'; Expected=''}
                @{Prop='description'; Expected=''}
                @{Prop='workingdirectory'; Expected='.'}
                @{Prop='arguments'; Expected=@()}
                @{Prop='shutdownwait'; Expected=2000}
            )
            It 'should insert a default value' -TestCases $testCases {
                Param($Prop, $Expected)
                $actual = Get-Config $testJsonFile

                $actual.$Prop | Should -Be $Expected
            }
        }
    }

    Describe 'Get-AppName' {
        BeforeEach {
            $script:config = @{
                name='app-foo'
            }
            $script:ConfigPath = 'C:\foo\bar\baz.ext'
            $script:scriptPath = 'C:\bar\baz\my-script.ps1'
        }

        Context '$config.name is not empty' {
            It 'returns $config.name' {
                Get-AppName | Should -BeExactly 'app-foo'
            }
        }

        Context '$config.name is empty' {
            BeforeEach {
                $script:config.name = $null
            }

            It 'returns base-name of $ConfigPath' {
                Get-AppName | Should -BeExactly 'baz'
            }

            Context '$ConfigPath is empty' {
                BeforeEach {
                    $script:ConfigPath = $null
                }

                It 'returns base-name of $scriptPath' {
                    Get-AppName | Should -BeExactly 'my-script'
                }
            }
        }
    }

    Describe 'Get-WorkingDirectory' {
        BeforeEach {
            $testSavedLocation = Get-Location

            $script:config = @{
                workingdirectory='relative\to'
            }
            $script:ConfigPath = Join-Path $TestDrive 'foo\my-app.json'

            $testDirectory = Join-Path $TestDrive 'foo\relative\to'
            New-Item $testDirectory -ItemType Directory -Force

            $testPWD = Join-Path $TestDrive 'bar'
            New-Item $testPWD -ItemType Directory -Force
            Set-Location $testPWD
        }

        AfterEach {
            Set-Location $testSavedLocation
        }

        Context '$config.workingdirectory is absolute path' {
            BeforeEach {
                $testDirectory = Join-Path $TestDrive 'baz\qux'
                $script:config = @{
                    workingdirectory=$testDirectory
                }
                New-Item $testDirectory -ItemType Directory -Force
            }

            It 'returns the absolute path spacified' {
                Get-WorkingDirectory | Should -Be $testDirectory
                Get-Location | Should -Be $testPWD
            }
        }

        Context '$config.workingdirectory is relative path' {
            It 'returns an absolute path relative to $ConfigPath' {
                Get-WorkingDirectory | Should -Be $testDirectory
                Get-Location | Should -Be $testPWD
            }

            Context '$ConfigPath is empty' {
                BeforeEach {
                    $testDirectory = Join-Path $testPWD 'relative\to'
                    New-Item $testDirectory -ItemType Directory -Force
                    $script:ConfigPath = $null
                }

                It 'returns an absolute path relative to the current directory' {
                    Get-WorkingDirectory | Should -Be $testDirectory
                    Get-Location | Should -Be $testPWD
                }
            }
        }

        Context '$config.workingdirectory contains environment variable replacement patterns' {
            BeforeEach {
                $env:foobar = 'XYZ'
                $script:config = @{
                    workingdirectory='bar\%foobar%'
                }
                $testDirectory = Join-Path $TestDrive 'foo\bar\XYZ'
                New-Item $testDirectory -ItemType Directory -Force
            }

            AfterEach {
                $env:foobar = $null
            }

            It 'returns the absolute path replaced with the value of the environment variable' {
                Get-WorkingDirectory | Should -Be $testDirectory
                Get-Location | Should -Be $testPWD
            }
        }

        Context 'resolved path does not exist' {
            BeforeEach {
                $script:config = @{
                    workingdirectory='does\not\exist'
                }
            }

            It 'should throws an exception' {
                {
                    Get-WorkingDirectory
                } | Should -Throw
                Get-Location | Should -Be $testPWD
            }
        }
    }

    Describe 'Get-ExecutablePath' {
        BeforeEach {
            $script:config = @{
                executable='relative\to\file'
            }

            $testDirectory = Join-Path $TestDrive 'foo'
            mock Get-WorkingDirectory { $testDirectory }

            $testFile = Join-Path $testDirectory 'relative\to\file'
            New-Item $testFile -ItemType File -Force
        }

        Context '$config.executable is absolute path' {
            BeforeEach {
                $testFile = Join-Path $TestDrive 'bar\baz\file'
                New-Item $testFile -ItemType File -Force

                $script:config = @{
                    executable=$testFile
                }
            }

            It 'returns the absolute path spacified' {
                Get-ExecutablePath | Should -Be $testFile
            }
        }

        Context '$config.executable is relative path' {
            It 'returns an absolute path relative to WorkingDirectory' {
                Get-ExecutablePath | Should -Be $testFile
            }
        }

        Context '$config.executable contains environment variable replacement patterns' {
            BeforeEach {
                $env:foobar = 'XYZ'
                $script:config = @{
                    executable='bar\%foobar%\file'
                }

                $testFile = Join-Path $testDirectory 'bar\XYZ\file'
                New-Item $testFile -ItemType File -Force
            }

            AfterEach {
                $env:foobar = $null
            }

            It 'returns the absolute path replaced with the value of the environment variable' {
                Get-ExecutablePath | Should -Be $testFile
            }
        }

        Context 'resolved path does not exist' {
            BeforeEach {
                $script:config = @{
                    executable='does\not\exist'
                }
            }

            It 'should throws an exception' {
                {
                    Get-ExecutablePath
                } | Should -Throw
            }
        }
    }

    Describe 'Get-ExecutableArgumentList' {
        BeforeEach {
            $script:config = @{
                arguments='relative\to\file'
            }

            $testDirectory = Join-Path $TestDrive 'foo'
            mock Get-WorkingDirectory { $testDirectory }

            $testFile = Join-Path $testDirectory 'relative\to\file'
            New-Item $testFile -ItemType File -Force
        }

        Context '$config.arguments is empty' {
            BeforeEach {
                $script:config = @{
                    arguments=@()
                }
            }

            It 'returns an empty array' {
                Get-ExecutableArgumentList | Should -BeNullOrEmpty
            }
        }

        Context '$config.arguments contains spaces' {
            BeforeEach {
                $script:config = @{
                    arguments=('foo ', 'bar')
                }
            }

            It 'returns the quoted element' {
                Get-ExecutableArgumentList | Should -Be ('"foo "', 'bar')
            }
        }

        Context '$config.arguments contains environment variable replacement patterns' {
            BeforeEach {
                $env:foo = 'XYZ'
                $script:config = @{
                    arguments=('%foo%bar', 'foobar')
                }
            }

            AfterEach {
                $env:foo = $null
            }

            It 'returns the element replaced with the value of the environment variable' {
                Get-ExecutableArgumentList | Should -Be ('XYZbar', 'foobar')
            }

            Context 'environment variable contains spaces' {
                BeforeEach {
                    $env:foo = 'ABC XYZ'
                }

                It 'returns the quoted element replaced with the value of the environment variable' {
                    Get-ExecutableArgumentList | Should -Be ('"ABC XYZbar"', 'foobar')
                }
            }
        }
    }

    Describe 'Start-FromShortcut' {
        BeforeEach {
            $testShortcutPath = Join-Path $TestDrive 'foo.lnk'
            Mock Get-ShortcutPath { $testShortcutPath }
            Mock Start-Process { if ($PassThru) { 'process-data' } }
        }

        It 'should calls Start-Process' {
            $actual = Start-FromShortcut

            Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                $FilePath -eq $testShortcutPath -And -Not $PassThru }
            $actual | Should -BeNullOrEmpty
        }

        Context 'with -PassThru' {
            It 'returns process' {
                $actual = Start-FromShortcut -PassThru

                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                    $FilePath -eq $testShortcutPath -And $PassThru }
                $actual | Should -BeExactly 'process-data'
            }
        }
    }

    Describe 'Install-Shortcut' {
        BeforeEach {
            $testShellExecutablePath = (Get-Process -Id $pid).Path

            $testShortcutPath = Join-Path $TestDrive 'foo.lnk'
            Mock Get-ShortcutPath { $testShortcutPath }

            $testExecutablePath = (Get-Command notepad.exe).Path
            Mock Get-ExecutablePath { $testExecutablePath }

            $script:config = @{
                name='baz'
                description='about foobar'
                executable=$testExecutablePath
            }

            $script:ConfigPath = Join-Path $TestDrive 'bar.json'
            $script:config | ConvertTo-Json > $script:ConfigPath
        }

        AfterEach {
            if (Test-Path $testShortcutPath) {
                Remove-Item $testShortcutPath
            }
        }

        It 'should create a shortcut file' {
            Install-Shortcut

            Test-Path $testShortcutPath | Should -BeTrue
        }

        Context 'the shortcut file already exist' {
            BeforeEach {
                "foo" > $testShortcutPath
            }

            It 'should create a shortcut file by overwritng' {
                Install-Shortcut

                Test-Path $testShortcutPath | Should -BeTrue -ErrorAction Stop
                Get-Content $testShortcutPath -Raw | Should -Not -BeLike "foo*"
            }
        }

        Context 'with -PassThru' {
            It 'returns a COM object' {
                $exptectedArgumentsLike = if ($script:ConfigPath.Contains(' ')) {
                    "* -ConfigPath ""$script:ConfigPath""*"
                } else {
                    "* -ConfigPath $script:ConfigPath*"
                }

                $actual = Install-Shortcut -PassThru

                $actual | Should -Not -BeNullOrEmpty -ErrorAction Stop

                $actual.Arguments | Should -BeLike "* .\$testSut run *"
                $actual.Arguments | Should -BeLike $exptectedArgumentsLike
                $actual.Description | Should -BeExactly 'about foobar'
                $actual.FullName | Should -Be $testShortcutPath
                $actual.Hotkey | Should -BeNullOrEmpty
                $actual.IconLocation | Should -Be "$testExecutablePath,0"
                $actual.TargetPath | Should -Be $testShellExecutablePath
                $actual.WindowStyle | Should -Be 7
                $actual.WorkingDirectory | Should -Be $testRoot
            }
        }
    }

    Describe 'Uninstall-Shortcut' {
        BeforeEach {
            $testShortcutPath = Join-Path $TestDrive 'foo.lnk'
            Mock Get-ShortcutPath { $testShortcutPath }
        }

        AfterEach {
            if (Test-Path $testShortcutPath) {
                Remove-Item $testShortcutPath
            }
        }

        Context 'the shortcut file exist' {
            BeforeEach {
                "foo" > $testShortcutPath
            }

            It 'removes the shortcut file' {
                Uninstall-Shortcut

                Test-Path $testShortcutPath | Should -BeFalse
            }
        }

        Context 'the shortcut file does not exist' {
            It 'does nothing' {
                {
                    Uninstall-Shortcut
                } | Should -Not -Throw

                Test-Path $testShortcutPath | Should -BeFalse
            }
        }
    }

    Describe 'Start-Executable' {
        BeforeEach {
            Mock Get-WorkingDirectory { 'TestDrive:\foo' }
            Mock Get-ExecutablePath { 'TestDrive:\bar\file.ext' }
            Mock Get-ExecutableArgumentList { @('ab', '-c') }
            Mock Start-Process { if ($PassThru) { 'process-data' } }
        }

        It 'should calls Start-Process' {
            $actual = Start-Executable

            Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                    $FilePath -eq 'TestDrive:\bar\file.ext' -And
                    -Not (Compare-Object $ArgumentList @('ab', '-c')) -And
                    $WorkingDirectory -eq 'TestDrive:\foo' -And
                    -Not $PassThru
                }
            $actual | Should -BeNullOrEmpty
        }

        Context 'with empty arguments' {
            BeforeEach {
                Mock Get-ExecutableArgumentList { @() }
            }

            It 'should calls Start-Process' {
                $actual = Start-Executable

                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                        $FilePath -eq 'TestDrive:\bar\file.ext' -And
                        -Not $ArgumentList -And
                        $WorkingDirectory -eq 'TestDrive:\foo' -And
                        -Not $PassThru
                    }
                $actual | Should -BeNullOrEmpty
            }
        }

        Context 'with -PassThru' {
            It 'returns process' {
                $actual = Start-Executable -PassThru

                Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                        $FilePath -eq 'TestDrive:\bar\file.ext' -And
                        -Not (Compare-Object $ArgumentList @('ab', '-c')) -And
                        $WorkingDirectory -eq 'TestDrive:\foo' -And
                        $PassThru
                    }
                $actual | Should -BeExactly 'process-data'
            }
        }
    }

    Describe 'Invoke-InMutex' -Tags slow {
        BeforeEach {
            $testMutexId = 'bc2cb8cf-a69d-40f1-b7ed-756aa4a1f177:foo'
        }

        Context 'the mutex does not exist' {
            It 'should invokes block' {
                $actual = Invoke-InMutex -name $testMutexId {
                    'bar'
                }

                $actual | Should -BeExactly 'bar'
            }

            It 'should not invokes else-block' {
                $vars = @{ elseBlockInvoked=$false }

                $actual = Invoke-InMutex -name $testMutexId {
                    'bar'
                } -elseBlock {
                    $vars.elseBlockInvoked = $true
                    'baz'
                }

                $actual | Should -BeExactly 'bar'
                $vars.elseBlockInvoked | Should -BeFalse
            }
        }

        Context 'the mutex already exist' {
            BeforeEach {
                $testJob = Start-Job {
                    Param($scriptPath, $testMutexId)
                    . $scriptPath
                    'job started'
                    Invoke-InMutex -name $testMutexId {
                        Start-Sleep 5
                    }
                } -ArgumentList ("$testRoot\$testSut", $testMutexId)

                # wait job started
                while ($true) {
                    $output = Receive-Job -Job $testJob
                    if ($output -eq 'job started') {
                        break
                    }
                    if (Wait-Job -Job $testJob -Timeout 1) {
                        $jobError = $null
                        try {
                            $output += Receive-Job -Job $testJob
                        } catch {
                            $jobError = $_
                        }
                        throw "Test job is stopped: Output=$output Error=$jobError"
                    }
                }
            }

            AfterEach {
                Stop-Job -Job $testJob
                Remove-Job -Job $testJob
            }

            It 'should not invokes block' {
                $vars = @{ blockInvoked=$false }

                $actual = Invoke-InMutex -name $testMutexId {
                    $vars.blockInvoked = $true
                    'bar'
                }

                $actual | Should -BeNullOrEmpty
                $vars.blockInvoked | Should -BeFalse
            }

            It 'should invokes else-block' {
                $vars = @{ blockInvoked=$false }

                $actual = Invoke-InMutex -name $testMutexId {
                    $vars.blockInvoked = $true
                    'bar'
                } -elseBlock {
                    'baz'
                }

                $actual | Should -BeExactly 'baz'
                $vars.blockInvoked | Should -BeFalse
            }
        }
    }

    Describe 'Get-ShortcutPath' {
        BeforeEach {
            $script:appName = 'app-foo'
        }

        It 'returns valid path' {
            $actual = Get-ShortcutPath
            $actual | Should -BeLikeExactly '*\Startup\app-foo.lnk'
        }
    }

    Describe 'ConvertTo-EscapedArg' {
        Context 'input string does not contains spaces or double-quotes' {
            It 'returns same string' {
                $actual = 'foo' | ConvertTo-EscapedArg
                $actual | Should -BeExactly 'foo'
            }
        }

        Context 'input string is quoted' {
            It 'returns same string' {
                $actual = '"foo"' | ConvertTo-EscapedArg
                $actual | Should -BeExactly '"foo"'
            }
        }

        Context 'input string contains spaces' {
            It 'returns quoted string' {
                $actual = 'foo bar' | ConvertTo-EscapedArg
                $actual | Should -BeExactly '"foo bar"'
            }
        }

        Context 'input string contains double-quotes' {
            It 'returns escaped and quoted string' {
                $actual = 'foo"bar' | ConvertTo-EscapedArg
                $actual | Should -BeExactly '"foo""bar"'
            }
        }

        Context "input string is '""'" {
            It 'returns escaped and quoted string' {
                $actual = '"' | ConvertTo-EscapedArg
                $actual | Should -BeExactly '""""'
            }
        }

        It 'should available as a function' {
            $actual = ConvertTo-EscapedArg 'foo '
            $actual | Should -BeExactly '"foo "'
        }

        It 'should available as a filter' {
            $actual = 'foo ', 'bar' | ConvertTo-EscapedArg
            $actual | Should -BeExactly ('"foo "', 'bar')
        }
    }

    Describe 'ConvertFrom-CmdEnvVar' {
        BeforeEach {
            $env:foo = 'ABC'
            $env:bar = 'XYZ'
            $env:baz = $null
        }

        AfterEach {
            $env:foo = $null
            $env:bar = $null
        }

        Context "input string contains environment variable name like '%name%'" {
            It 'should be replaced with the value of the specified name' {
                $actual = 'foo%bar%baz' | ConvertFrom-CmdEnvVar
                $actual | Should -BeExactly 'fooXYZbaz'
            }

            It 'should be replaced with the value of all the names specified' {
                $actual = '%foo%%bar%baz' | ConvertFrom-CmdEnvVar
                $actual | Should -BeExactly 'ABCXYZbaz'
            }
        }

        Context 'an environment variable with the specified name does not exist' {
            It 'returns same string' {
                $actual = 'foobar%baz%' | ConvertFrom-CmdEnvVar
                $actual | Should -BeExactly 'foobar%baz%'
            }
        }

        Context "input string contains '%%'" {
            It "returns same string'" {
                $actual = 'foobar%%' | ConvertFrom-CmdEnvVar
                $actual | Should -BeExactly 'foobar%%'
            }
        }

        It 'should available as a function' {
            $actual = ConvertFrom-CmdEnvVar 'foo%bar%'
            $actual | Should -BeExactly 'fooXYZ'
        }

        It 'should available as a filter' {
            $actual = '%foo%', '%bar%' | ConvertFrom-CmdEnvVar
            $actual | Should -BeExactly ('ABC', 'XYZ')
        }
    }

} # Describe 'runtray'
