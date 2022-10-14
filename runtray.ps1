<#
.SYNOPSIS
Run any console program in the notification area.

.DESCRIPTION
A long-running console program can be run in the notification area.
Specify the execution program path and arguments in the JSON configuration file.

.PARAMETER Command
Sub command.
    start      Start the executable from shortcut.
    install    Install shortcut to the startup folder.
    uninstall  Remove shortcut from the startup folder.
    run        Start the executable in current terminal.

.PARAMETER ConfigPath
JSON configuration file path.
Default is the same name as this script with .json extension.

.PARAMETER GUI
Enable GUI mode.

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
#Requires -Version 3

Param(
    [Parameter(Position=0)]
    [ValidateSet('start', 'install', 'uninstall', 'run', 'help', IgnoreCase)]
    [string] $Command = 'help',
    [string] $ConfigPath,
    [switch] $GUI
)

$ErrorActionPreference = 'Stop'
$UUID = 'f5662bbc-52ce-4a38-8bf5-20897ed3b048'
$appName = 'runtray'
$config = $false
$startupWait = 500
$shutdownWait = 2000
$mainHWnd = (Get-Process -PID $PID).MainWindowHandle

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

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
    $script:appName = Remove-Extension(Split-Path -Path $PSCommandPath -Leaf)

    if ($script:GUI) {
        Hide-Window
    }

    if (-Not $script:ConfigPath) {
        $ConfigPath = "$(Remove-Extension $PSCommandPath).json"
    }
    $script:config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    if ($script:config.name) {
        $script:appName = $script:config.name
    }

    switch ($script:Command) {
        'start' { Start-FromShortcut }
        'install' { Install-Shortcut }
        'uninstall' { Uninstall-Shortcut }
        'run' { Start-Executable }
        default { Get-Help $PSCommandPath }
    }
}

function Start-FromShortcut() {
    $shortcutPath = Get-ShortcutPath
    "Start shortcut: $shortcutPath" | Write-Verbose
    Start-Process $shortcutPath
}

function Install-Shortcut() {
    $shortcutPath = Get-ShortcutPath
    "Install shortcut: $shortcutPath" | Write-Verbose

    $workDir = Split-Path -Path $PSCommandPath -Parent
    $scriptName = Split-Path -Path $PSCommandPath -Leaf
    $executable = Resolve-Path -LiteralPath $script:config.executable

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
    $shortcut.TargetPath = 'powershell.exe'
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $workDir
    $shortcut.WindowStyle = 7  # Minimize
    $shortcut.IconLocation = "${executable},0"
    $shortcut.Save()

    return $shortcut
}

function Uninstall-Shortcut() {
    $shortcutPath = Get-ShortcutPath

    if (Test-Path -Path $shortcutPath -PathType Leaf) {
        "Uninstall shortcut: $shortcutPath" | Write-Verbose
        Remove-Item -Path $shortcutPath
    }
}

function Start-Executable() {
    $executable = $script:config.executable

    $arguments = if ($script:config.arguments -is [array]) {
        ($script:config.arguments |
         ConvertFrom-CmdEnvVars | ConvertTo-EscapedArg) -join ' '
    } else {
        $script:config.arguments | ConvertFrom-CmdEnvVars
    }

    $workDir = if ($script:config.workingdirectory) {
        $script:config.workingdirectory | ConvertFrom-CmdEnvVars
    } else {
        '.'
    }

    $shutdownWait = if ($script:config.shutdownwait -is [int]) {
        $script:config.shutdownwait
    } else {
        $script:shutdownWait
    }

    $mutexName = "${script:UUID}:${script:appName}"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try {
        if ($mutex.WaitOne(0, $false)) {
            "Set working directory: $workDir" | Write-Verbose
            "Start executable: $executable $arguments" | Write-Verbose
            $child = Start-Process $executable $arguments `
                -WorkingDirectory $workDir -NoNewWindow -PassThru
            try {
                Start-AppContext $child
            } finally {
                if (-Not $child.HasExited) {
                    "Send Ctrl-C to process: $($child.Id)" | Write-Verbose
                    $exited = Send-CtrlC $child -wait $shutdownWait
                    if (-Not $exited) {
                        "Force stop process: $($child.Id)" | Write-Verbose
                        Stop-ProcessTree $child.Id
                    }
                }
                "Exit code: $($child.ExitCode)" | Write-Verbose
                exit $child.ExitCode
            }
        } else {
            "Mutex already exists: $mutexName" | Write-Warning
            exit 1
        }
    } finally {
        $mutex.Close()
    }
}

function Start-AppContext([System.Diagnostics.Process]$child) {
    $appContext = New-Object RunTray.ExitApplicationContext
    $appContext.ApplyExitedHandler($child)

    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:config.executable)
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = $icon
    $notify.Text = $script:appName
    $notify.Visible = $true
    $notify.ContextMenu = New-Object System.Windows.Forms.ContextMenu

    $consoleMenu = New-Object System.Windows.Forms.MenuItem
    $consoleMenu.Text = 'Show console'
    $consoleMenu.Checked = -Not $script:GUI
    $consoleMenu.add_Click({
        $consoleMenu.Checked = -Not $consoleMenu.Checked
        if ($consoleMenu.Checked) {
            Show-Window
        } else {
            Hide-Window
        }
    })

    $exitMenu = New-Object System.Windows.Forms.MenuItem
    $exitMenu.Text = 'Exit'
    $exitMenu.add_Click({
        $appContext.ExitThread()
    })

    $notify.ContextMenu.MenuItems.AddRange(@($consoleMenu, $exitMenu))

    try {
        if (-Not $child.WaitForExit($script:startupWait)) {
            Disable-CloseButton
            [void][System.Windows.Forms.Application]::Run($appContext)
        }
    } finally {
        $notify.Visible = $false
    }
}

function Get-ShortcutPath() {
    $ws = New-Object -ComObject WScript.Shell
    Join-Path $ws.SpecialFolders['Startup'] "${appName}.lnk"
}

function Show-MessageBox([string]$message, $buttonType='OK', $iconType='None', $defaultButton='button1'){
    $form = New-Object System.Windows.Forms.form
    $form.TopMost = $true
    [System.Windows.Forms.MessageBox]::Show($form, $message, $script:appName, $buttonType, $iconType, $defaultButton)
}

function Remove-Extension([string]$name) {
    $name.Substring(0, $name.LastIndexOf('.'))
}

filter ConvertTo-EscapedArg() {
    $s = "$_"
    if ($s.Contains(' ') -And -Not ($s.Length -ge 2 -And $s.StartsWith('"') -And $s.EndsWith('"'))) {
        $s = """$($s.Replace('"', '""'))"""
    }
    return $s
}

filter ConvertFrom-CmdEnvVars() {
    [regex]::Replace("$_", '%(\w*)%', {
        $name = $args.groups[1].value
        if ($name.Length -eq 0) {
            '%%'
        } else {
            [System.Environment]::GetEnvironmentVariable($name)
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

function Disable-CloseButton() {
    [RunTray.Win32API]::DisableCloseButton($script:mainHWnd)
}

function Stop-ProcessTree([int]$ppid) {
    Get-CimInstance Win32_Process `
        | Where-Object { $_.ParentProcessId -eq $ppid } `
        | ForEach-Object { Stop-ProcessTree $_.ProcessId }
    try {
        Stop-Process -Id $ppid
    } catch [ObjectNotFound] {
        # pass
    }
}

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RunTray {

    public static class Win32API {
        private const uint CTRL_C_EVENT = 0;
        private const int SC_CLOSE = 0xf060;
        private const uint MF_DISABLED = 2;

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleCtrlHandler(ConsoleCtrlHandler HandlerRoutine, bool Add);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

        [DllImport("user32.dll")]
        private static extern bool EnableMenuItem(IntPtr hMenu, uint uIDEnableItem, uint uEnable);

        private delegate bool ConsoleCtrlHandler(uint dwCtrlEvent);

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

    public class ExitApplicationContext : ApplicationContext {
        public void OnExited(object sender, EventArgs e) {
            ExitThread();
        }

        public void ApplyExitedHandler(Process process) {
            process.EnableRaisingEvents = true;
            process.Exited += this.OnExited;
        }
    }

}
'@

Start-CLI
