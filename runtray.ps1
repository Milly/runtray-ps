<#PSScriptInfo
.VERSION 1.4.0
.GUID f5662bbc-52ce-4a38-8bf5-20897ed3b048
.AUTHOR Milly
.COPYRIGHT 2022 Milly
.LICENSEURI https://github.com/Milly/runtray-ps/blob/master/LICENSE
.PROJECTURI https://github.com/Milly/runtray-ps
#>

#Requires -Version 3

<#
.SYNOPSIS
Run any console program in the notification area.

.DESCRIPTION
A long-running console program can be run in the notification area.
Specify the execution program path and arguments in the JSON configuration file.

.PARAMETER Command
Sub command.
    start      Start the executable from shortcut.
    stop       Stop the service.
    restart    Stop and start the service.
    install    Install shortcut to the startup folder.
    uninstall  Remove shortcut from the startup folder.
    run        Start the executable in current terminal.

.PARAMETER ConfigPath
JSON configuration file path.
Default is the same name as this script with .json extension.

.PARAMETER GUI
Enable GUI mode.

.PARAMETER PassThru
Returns a System.Diagnostics.Process if the Command parameter is 'start'.
Returns a shortcut ComObject (System.MarshalByRefObject) if the Command parameter is 'install'.
Otherwise this parameter does nothing.

.INPUTS
None. You can't pipe input to runtray.ps1.

.OUTPUTS
None, String, System.Diagnostics.Process, System.MarshalByRefObject.
Returns a System.Diagnostics.Process if the Command parameter is 'start' and the PassThru parameter is specified.
Returns a shortcut ComObject (System.MarshalByRefObject) if the Command parameter is 'install' and the PassThru parameter is specified.
Returns a string messages from the executable if the Command parameter is 'run'.
Otherwise runtray.ps1 doesn't generate any output.

.LINK
https://github.com/Milly/runtray-ps

.NOTES
MIT License

Copyright (c) 2022 Milly

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>
Param(
    [Parameter(Position=0)]
    [ValidateSet(
        'start',
        'stop',
        'restart',
        'install',
        'uninstall',
        'run',
        'version',
        'help',
        IgnoreCase)]
    [string] $Command = 'help',
    [Alias('c')]
    [string] $ConfigPath,
    [switch] $GUI,
    [switch] $PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:Command = $Command
$script:ConfigPath = $ConfigPath
$script:GUI = $GUI
$script:PassThru = $PassThru

$script:UUID = 'f5662bbc-52ce-4a38-8bf5-20897ed3b048'
$script:scriptPath = $PSCommandPath
$script:appName = (Split-Path -Path $script:scriptPath -Leaf) -replace '.ps1', ''
$script:config = $null
$script:mainHWnd = (Get-Process -PID $PID).MainWindowHandle
$script:serviceProcess = $null
$script:autoRestart = $false

$script:configSchema = @{
    type=[PSObject]
    required=@(
        'executable'
    )
    properties=@{
        name=@{
            type=[string]
            default=""
        }
        description=@{
            type=[string]
            default=""
        }
        executable=@{
            type=[string]
        }
        arguments=@{
            type=[array]
            items=@{
                type=[string]
            }
            default=@()
        }
        workingdirectory=@{
            type=[string]
            default="."
        }
        shutdownwait=@{
            type=[int]
            default=2000
        }
        autorestart=@{
            type=[bool]
            default=$false
        }
    }
}

function Start-CLI() {
    try {
        Start-Main
    } catch {
        if ($script:GUI) {
            Show-Window
            Show-MessageBox "$_" -iconType 'Error'
        }
        throw
    }
}

function Start-Main() {
    # Execute early because it is used for error display.
    $script:appName = Get-AppName

    if ($script:GUI) {
        Hide-Window
    }

    $script:config = Get-Config -Path $script:ConfigPath
    $script:autoRestart = $script:config.autorestart
    $script:appName = Get-AppName
    "Service name: ${script:appName}" | Write-Verbose

    switch ($script:Command) {
        'start' { Start-FromShortcut -PassThru:($script:PassThru) }
        'stop' { Stop-ServiceProcess }
        'restart' { Restart-ServiceProcess }
        'install' { Install-Shortcut -PassThru:($script:PassThru) }
        'uninstall' { Uninstall-Shortcut }
        'run' { Start-GUI }
        'version' { Get-Version }
        default { Get-Help $script:scriptPath }
    }
}

function Get-Version() {
    (Test-ScriptFileInfo $PSCommandPath).Version
}

function Get-Config([string]$Path) {
    function parse($obj, $defs, $current) {
        if (-Not ($obj -Is $defs.type)) {
            throw "Property type is not [$($defs.type)]: $current"
        }
        if ($obj -Is [PSObject]) {
            $props = $obj.PSObject.Properties
            foreach ($name in $defs.required) {
                if (-Not ($props.Name -contains $name)) {
                    throw "Required property not exists: $current.$name"
                }
            }
            foreach ($propDef in $defs.properties.GetEnumerator()) {
                if ($props.Name -contains $propDef.Key) {
                    $prop = $props[$propDef.Key]
                    parse $prop.Value $propDef.Value "$current.$($propDef.Key)"
                } else {
                    $obj | Add-Member -NotePropertyName $propDef.Key -NotePropertyValue $propDef.Value.default
                }
            }
        } elseif ($obj -Is [array]) {
            for ($i = 0; $i -lt $obj.Count; $i++) {
                parse $obj[$i] $defs.items "$current[$i]"
            }
        }
    }

    if (-Not $Path) {
        $Path = "$(Remove-Extension $script:scriptPath).json"
    }
    $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
    try {
        parse $config $script:configSchema '$'
    } catch {
        "Configuration file is invalid: $Path`n  $_" | Write-Error -Category InvalidData -CategoryReason "$_"
    }
    $config
}

function Get-AppName() {
    if ($script:config -And $script:config.name) {
        $script:config.name
    } elseif ($script:ConfigPath) {
        Remove-Extension (Split-Path -Path $script:ConfigPath -Leaf)
    } else {
        Remove-Extension (Split-Path -Path $script:scriptPath -Leaf)
    }
}

function Get-Identifier() {
    "${script:UUID}#${script:appName}"
}

function Get-WorkingDirectory() {
    Push-Location
    try {
        if ($script:ConfigPath) {
            $configDir = Split-Path -Path $script:ConfigPath -Parent
            if ($configDir) {
                Set-Location -LiteralPath $configDir
            }
        }
        $workDir = $script:config.workingdirectory | ConvertFrom-CmdEnvVar
        Resolve-Path -LiteralPath $workDir
    } finally {
        Pop-Location
    }
}

function Get-ExecutableCommand() {
    $executable = ConvertFrom-CmdEnvVar $script:config.executable
    Push-Location
    try {
        Set-Location -LiteralPath (Get-WorkingDirectory)
        Get-Command $executable
    } finally {
        Pop-Location
    }
}

function Get-ExecutableArgumentList() {
    $script:config.arguments | ConvertFrom-CmdEnvVar | ConvertTo-EscapedArg
}

function Start-FromShortcut([switch]$PassThru) {
    $shortcutPath = Get-ShortcutPath
    "Start shortcut: $shortcutPath" | Write-Verbose
    Start-Process $shortcutPath -PassThru:$PassThru
}

function Stop-ServiceProcess() {
    Send-NamedPipeMessage (Get-Identifier) -message 'stop'
}

function Restart-ServiceProcess() {
    Send-NamedPipeMessage (Get-Identifier) -message 'restart'
}

function Install-Shortcut([switch]$PassThru) {
    $shortcutPath = Get-ShortcutPath
    "Install shortcut: $shortcutPath" | Write-Verbose

    $shellExecutable = (Get-Process -PID $pid).Path
    $workDir = Split-Path -Path $script:scriptPath -Parent
    $scriptName = Split-Path -Path $script:scriptPath -Leaf
    $executable = (Get-ExecutableCommand).Path

    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        ".\$scriptName", 'run', '-GUI'
    )
    if ($script:ConfigPath) {
        $configPath = Resolve-Path -LiteralPath $script:ConfigPath
        $arguments += @('-ConfigPath', $configPath)
    }
    $arguments = ($arguments | ConvertTo-EscapedArg) -join ' '

    if (Test-Path -Path $shortcutPath -PathType Leaf) {
        Remove-Item -Path $shortcutPath
    }

    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($shortcutPath)
    $shortcut.Description = $script:config.description
    $shortcut.TargetPath = $shellExecutable
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $workDir
    $shortcut.WindowStyle = 7  # Minimize
    $shortcut.IconLocation = "${executable},0"
    $shortcut.Save()

    if ($PassThru) {
        return $shortcut
    }
}

function Uninstall-Shortcut() {
    $shortcutPath = Get-ShortcutPath

    if (Test-Path -Path $shortcutPath -PathType Leaf) {
        "Uninstall shortcut: $shortcutPath" | Write-Verbose
        Remove-Item -Path $shortcutPath
    }
}

function Start-GUI() {
    Invoke-InMutex -name (Get-Identifier) -block {
        $lastError = $null
        Disable-CtrlC
        Disable-CloseButton
        try {
            Start-AppContext
        } catch {
            $lastError = $_
        } finally {
            $exitCode = 0
            if ($script:serviceProcess) {
                Stop-ProcessGracefully $script:serviceProcess
                $exitCode = $script:serviceProcess.ExitCode
                $script:serviceProcess.Close()
                "Service exit code: $exitCode" | Write-Verbose
            }
            if ($lastError) {
                throw $lastError
            }
            exit $exitCode
        }
    } -elseBlock {
        "Already running: ${script:appName}" | Write-Warning
        exit 1
    }
}

function Start-Executable([switch]$PassThru) {
    $workDir = Get-WorkingDirectory
    $executable = (Get-ExecutableCommand).Path
    $arguments = Get-ExecutableArgumentList

    "Set working directory: $workDir" | Write-Verbose
    "Start executable: `"$executable`" $arguments" | Write-Verbose

    $processParams = @{
        FilePath=$executable
        WorkingDirectory=$workDir
        NoNewWindow=$true
        PassThru=$PassThru
    }
    if ($arguments) {
        $processParams.ArgumentList = $arguments
    }
    Start-Process @processParams
}

function Invoke-InMutex([string]$name, [scriptblock]$block, [scriptblock]$elseBlock) {
    $mutex = New-Object System.Threading.Mutex($false, $name)
    try {
        if ($mutex.WaitOne(0, $false)) {
            & $block
        } elseif ($elseBlock) {
            & $elseBlock
        }
    } finally {
        $mutex.Close()
    }
}

function Start-AppContext() {
    $executable = (Get-ExecutableCommand).Path
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($executable)
    $appContext = New-Object RunTray.SyncApplicationContext
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $serviceExitedHandler = {
        $appContext.ExitThread()
    }

    $restartService = {
        $service = $script:serviceProcess
        if ($service) {
            $service.remove_Exited($serviceExitedHandler)
            Stop-ProcessGracefully $service
            $service.Close()
        }

        $service = Start-Executable -PassThru
        $service.EnableRaisingEvents = $true
        $service.SynchronizingObject = $appContext
        $service.add_Exited($serviceExitedHandler)
        $script:serviceProcess = $service
    }
    $appContext.add_Ready($restartService)

    $exitApp = {
        $script:autoRestart = $false
        $appContext.ExitThread()
    }

    $pipeMessage = {
        switch ($_.message) {
            'restart' { & $restartService }
            'stop' { & $exitApp }
        }
    }
    $appContext.add_PipeMessage($pipeMessage)

    $consoleMenu = [System.Windows.Forms.ToolStripMenuItem]@{
        Text = 'Show &console'
        Checked = -Not $script:GUI
    }
    $consoleMenu.add_Click({
        $consoleMenu.Checked = -Not $consoleMenu.Checked
        if ($consoleMenu.Checked) {
            Show-Window
        } else {
            Hide-Window
        }
    })
    [void]$contextMenu.Items.Add($consoleMenu)

    $restartMenu = [System.Windows.Forms.ToolStripMenuItem]@{
        Text = '&Restart service'
    }
    $restartMenu.add_Click({
        $msg = 'Are you sure you want to restart the service?'
        $res = Show-MessageBox $msg -buttonType YesNo -iconType Question -defaultButton button2
        if ($res -eq 'Yes') {
            & $restartService
        }
    })
    [void]$contextMenu.Items.Add($restartMenu)

    $autoRestartMenu = [System.Windows.Forms.ToolStripMenuItem]@{
        Text = '&Auto restart'
    }
    $autoRestartMenu.Checked = $script:autoRestart
    $autoRestartMenu.add_Click({
        $autoRestartMenu.Checked = -Not $autoRestartMenu.Checked
        $script:autoRestart = $autoRestartMenu.Checked
    })
    [void]$contextMenu.Items.Add($autoRestartMenu)

    [void]$contextMenu.Items.Add('-')  # Separator

    $exitMenu = [System.Windows.Forms.ToolStripMenuItem]@{
        Text = 'E&xit'
    }
    $exitMenu.add_Click({
        $msg = 'Are you sure you want to stop the service?'
        $res = Show-MessageBox $msg -buttonType YesNo -iconType Question -defaultButton button2
        if ($res -eq 'Yes') {
            & $exitApp
        }
    })
    [void]$contextMenu.Items.Add($exitMenu)

    $notify = [System.Windows.Forms.NotifyIcon]@{
        Icon = $icon
        Text = $script:appName
        Visible = $true
        ContextMenuStrip = $contextMenu
    }

    try {
        $appContext.CreatePipe((Get-Identifier))
        do {
            $appContext.Run()
        } while ($script:autoRestart)
    } finally {
        if ($script:serviceProcess) {
            $script:serviceProcess.remove_Exited($serviceExitedHandler)
        }
        $appContext.Dispose()
        $notify.Dispose()
    }
}

function Send-NamedPipeMessage([string]$pipeName, [string]$message, $timeout=100) {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, 'Out')
    try {
        $pipe.Connect($timeout)
        $buf = [System.Text.Encoding]::Unicode.GetBytes($message)
        $pipe.Write($buf, 0, $buf.Length)
    } catch {
        if ($_.FullyQualifiedErrorId -eq 'TimeoutException') {
            "Service not available: ${script:appName}" | Write-Error -Category ResourceUnavailable -CategoryReason "$_"

        } else {
            throw
        }
    } finally {
        $pipe.Close()
    }
}

function Get-ShortcutPath() {
    $ws = New-Object -ComObject WScript.Shell
    Join-Path $ws.SpecialFolders['Startup'] "${script:appName}.lnk"
}

function Show-MessageBox([string]$message, $buttonType='OK', $iconType='None', $defaultButton='button1'){
    $form = New-Object System.Windows.Forms.Form
    $form.TopMost = $true
    try {
        [System.Windows.Forms.MessageBox]::Show($form, $message, $script:appName, $buttonType, $iconType, $defaultButton)
    } finally {
        $form.Dispose()
    }
}

function Remove-Extension([string]$name) {
    $name.Substring(0, $name.LastIndexOf('.'))
}

filter ConvertTo-EscapedArg() {
    param([Parameter(Mandatory, ValueFromPipeline)] [string]$string)
    if ($string -Match '[ "]' -And $string -NotLike '"*"') {
        return '"' + $string.Replace('"', '""') + '"'
    }
    $string
}

filter ConvertFrom-CmdEnvVar {
    param([Parameter(Mandatory, ValueFromPipeline)] [string]$string)
    [regex]::Replace($string, '%(\w*)%', {
        $name = $args.groups[1].value
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ($null -eq $value) {
            $args.groups[0].value
        } else {
            $value
        }
    })
}

function Show-Window() {
    $SW_RESTORE = 9
    [void][RunTray.Win32API]::ShowWindowAsync($script:mainHWnd, $SW_RESTORE)
}

function Hide-Window() {
    $SW_HIDE = 0
    [void][RunTray.Win32API]::ShowWindowAsync($script:mainHWnd, $SW_HIDE)
}

function Send-CtrlC([System.Diagnostics.Process]$process, [int]$wait) {
    [RunTray.Win32API]::SendCtrlC($process, $wait)
}

function Disable-CtrlC() {
    [void][RunTray.Win32API]::SetConsoleCtrlHandler($null, $true)
}

function Disable-CloseButton() {
    [RunTray.Win32API]::DisableCloseButton($script:mainHWnd)
}

function Stop-ProcessGracefully([System.Diagnostics.Process]$process) {
    if (-Not $process.HasExited) {
        "Send Ctrl-C to process: $($process.Id)" | Write-Verbose
        $exited = Send-CtrlC $process -wait $script:config.shutdownwait
        if (-Not $exited) {
            "Force stop process: $($process.Id)" | Write-Verbose
            Stop-ProcessTree $process.Id
        }
    }
}

function Stop-ProcessTree([int]$ppid) {
    Get-CimInstance Win32_Process `
        | Where-Object { $_.ParentProcessId -eq $ppid } `
        | ForEach-Object { Stop-ProcessTree $_.ProcessId }
    try {
        Stop-Process -Id $ppid
    } catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        # pass
        [void]$null
    }
}

Add-Type -ReferencedAssemblies @(
    'System.ComponentModel.Primitives'
    'System.Diagnostics.Process'
    'System.IO.Pipes'
    'System.Windows.Forms'
) -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace RunTray {

    public static class Win32API {
        private const uint CTRL_C_EVENT = 0;
        private const int SC_CLOSE = 0xf060;
        private const uint MF_DISABLED = 2;

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleCtrlHandler(ConsoleCtrlHandler HandlerRoutine, bool Add);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

        [DllImport("user32.dll")]
        private static extern bool EnableMenuItem(IntPtr hMenu, uint uIDEnableItem, uint uEnable);

        public delegate bool ConsoleCtrlHandler(uint dwCtrlEvent);

        public static bool SendCtrlC(Process process, int wait) {
            // Disable Ctrl-C handling
            SetConsoleCtrlHandler(null, true);

            try {
                GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0);

                // Must wait here. If we don't and re-enable Ctrl-C
                // handling below too fast, we might terminate ourselves.
                return process.WaitForExit(wait != 0 ? wait : 10);
            } finally {
                // Re-enable Ctrl-C handling
                SetConsoleCtrlHandler(null, false);
            }
        }

        public static void DisableCloseButton(IntPtr hWnd) {
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            EnableMenuItem(hMenu, SC_CLOSE, MF_DISABLED);
        }
    }

    public class SyncApplicationContext : ApplicationContext, ISynchronizeInvoke {
        private TaskScheduler taskScheduler;
        private const int PIPE_IN_BUFFER_SIZE = 1024;
        private NamedPipeServerStream pipeServerStream;

        public event EventHandler Ready;
        public event EventHandler<PipeMessageArgs> PipeMessage;

        public SyncApplicationContext() {
        }

        protected override void Dispose(bool disposing) {
            if (disposing) {
                if (this.pipeServerStream != null) {
                    this.pipeServerStream.Dispose();
                }
            }
            base.Dispose(disposing);
        }

        public void Run() {
            Application.Idle += this.OnApplicationIdle;
            Application.Run(this);
        }

        public void CreatePipe(string pipeName) {
            RunPipeServer(pipeName);
        }

        protected void OnReady(EventArgs e) {
            if (this.Ready != null) {
                Ready(this, e);
            }
        }

        protected void OnPipeMessage(PipeMessageArgs e) {
            if (this.PipeMessage != null) {
                PipeMessage(this, e);
            }
        }

        private void OnApplicationIdle(object sender, EventArgs e) {
            Application.Idle -= this.OnApplicationIdle;
            this.taskScheduler = TaskScheduler.FromCurrentSynchronizationContext();
            OnReady(e);
        }

        private async void RunPipeServer(string pipeName) {
            while (true) {
                var server = this.pipeServerStream = new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.In,
                    /* maxServerInstances */ 1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous,
                    PIPE_IN_BUFFER_SIZE,
                    /* outBufferSize */ 0
                );
                using (server) {
                    await server.WaitForConnectionAsync();
                    byte[] buffer = new byte[PIPE_IN_BUFFER_SIZE];
                    int bytesRead;
                    while ((bytesRead = await server.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                        var message = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                        OnPipeMessage(new PipeMessageArgs(message));
                    }
                }
            }
        }

        // #region ISynchronizeInvoke

        public bool InvokeRequired {
            get {
                return this.taskScheduler != null &&
                    this.taskScheduler.Id != TaskScheduler.Current.Id;
            }
        }

        public IAsyncResult BeginInvoke(Delegate method, object[] args) {
            return Task.Factory.StartNew<object>(
                () => method.DynamicInvoke(args),
                CancellationToken.None,
                TaskCreationOptions.None,
                this.taskScheduler
            );
        }

        public object EndInvoke(IAsyncResult result) {
            var task = (Task<object>)result;
            task.Wait();
            return task.Result;
        }

        public object Invoke(Delegate method, object[] args) {
            if (this.InvokeRequired) {
                return EndInvoke(BeginInvoke(method, args));
            } else {
                return method.DynamicInvoke(args);
            }
        }

        // #endregion
    }

    public class PipeMessageArgs : EventArgs
    {
        public string Message { get; private set; }

        public PipeMessageArgs(string message) {
            Message = message;
        }
    }
}
'@

# Determine script has been dot-sourced
if (-Not $MyInvocation.line.TrimStart().StartsWith('. ')) {
    Start-CLI
}
