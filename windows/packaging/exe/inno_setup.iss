[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{APP_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={autopf}\{{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64 arm64
ArchitecturesInstallIn64BitMode=x64 arm64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {{DESKTOP_ICON_FLAGS}}
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{{DISPLAY_NAME}}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {{LAUNCH_AT_STARTUP_FLAGS}}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
; Auto-start: no Startup-folder shortcut — the app registers the Run-key entry itself on first launch (see [Run] --enable-autostart), keeping a single channel in sync with the in-app toggle.
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Parameters: "{code:GetLaunchParams}"; Flags: {{RUN_FLAGS}} nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Classes\clash"; ValueType: string; ValueName: ""; ValueData: "URL:Singcast Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\clash"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\clash\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\clash\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\\{{EXECUTABLE_NAME}}"" ""%1"""

[UninstallRun]
Filename: "{app}\\singcast-core.exe"; Parameters: "service uninstall"; Flags: runhidden
; Remove the autostart Run-key entry the app registered; /f + runhidden = silent even if absent.
Filename: "{cmd}"; Parameters: "/c reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v Singcast /f"; Flags: runhidden

[Code]
// postinstall launch params: pass --enable-autostart when launchAtStartup is
// selected, so the app registers the Run-key autostart entry itself — a single
// channel that stays in sync with the in-app toggle (no Startup shortcut).
function GetLaunchParams(Value: string): string;
begin
  if IsTaskSelected('launchAtStartup') then
    Result := '--enable-autostart'
  else
    Result := '';
end;
