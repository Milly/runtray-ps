# runtray-ps

A long-running console program can be run in the notification area.

Configure detailed settings in the [JSON configuration file](#json-configuration-file).

## Supported platforms

`runtray.ps1` can run on Windows platforms with PowerShell 3.0 and .NET Framework 4.5 or later versions installed.

[Windows PowerShell system requirements](https://learn.microsoft.com/powershell/scripting/windows-powershell/install/windows-powershell-system-requirements)
Preinstalled since Windows 8.

## Installation

### Unblock downloaded file

Users should unblock files downloaded from the Internet so that Windows does not block access to the files.

1. Download `runtray.ps1`.
2. Right-click the file and select **Properties** from the context menu.
3. On the **General** tab of the file properties dialog, check the **Unblock** option.

### Use `runtray.ps1` as bundle

1. Download `runtray.ps1` and [Unblock](unblock-downloaded-file).
2. Copy the ps1 file and write a [JSON configuration file](#json-configuration-file) with the same name to the same folder.

       C:\my\app\my-application.ps1
       C:\my\app\my-application.json

3. Run install command.

       powershell -NoProfile -ExecutionPolicy RemoteSigned C:\my\app\my-application.ps1 install

### Use `runtray.ps1` as global

1. Download `runtray.ps1` to any folder and [Unblock](unblock-downloaded-file).

       C:\my\program\runtray.ps1

2. Write a [JSON configuration file](#json-configuration-file) and put it in any folder.

       C:\my\app\my-application.json

3. Run install command.

       powershell -NoProfile -ExecutionPolicy RemoteSigned C:\my\program\runtray.ps1 install -ConfigPath C:\my\app\my-application.json

## Start application

The shortcut is installed to the Startup folder, so it will automatically start when you log on to Windows.

Alternatively, you can launch it with the script `start` command.

## Usage

### Command line

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned .\runtray.ps1 <Command> [Option ...]
```

| Command   | Description
| -------   | -----------
| start     | Start the executable from shortcut.
| install   | Install shortcut to the startup folder.
| uninstall | Remove shortcut from the startup folder.
| run       | Start the executable in current terminal. For internal or debug.

| Option             | Description
| ------             | -----------
| -ConfigPath `file` | JSON configuration file path.
| -GUI               | Enable GUI mode.
| -PassThru          | Returns an object in some command.

### JSON configuration file

Note that backslashes must be escaped within the JSON string.

Example::
```json
{
    "name": "ping-local",
    "description": "Pinging localhost continuously.",
    "executable": "%WinDir%\\System32\\ping.exe",
    "arguments": ["-t", "127.0.0.1"],
    "workingdirectory": "%USERPROFILE%",
    "shutdownwait": 2000
}
```

| Element           | Required | Type     | Default | Description
| -------           | -------- | ----     | ------- | -----------
| .name             | No       | string   |         | Used for the shortcut filename and the program title.
| .description      | No       | string   | `""`    | Written in the description field of the shortcut.
| .executable       | Yes      | string   |         | Path to the executable.
| .arguments        | No       | string[] | `[]`    | Arguments of the executable.
| .workingdirectory | No       | string   | `"."`   | Path to the working directory.
| .shutdownwait     | No       | int      | `2000`  | Wait time in milliseconds after sending <kbd>Ctrl-C</kbd>.
