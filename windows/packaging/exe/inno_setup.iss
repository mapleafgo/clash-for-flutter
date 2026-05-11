[Setup]
AppId={{{app_id}}
AppName={{{display_name}}
AppVersion={{{version}}
AppPublisher={{{publisher}}
AppPublisherURL={{{publisher_url}}}
AppSupportURL={{{publisher_url}}}
AppUpdatesURL={{{publisher_url}}}
DefaultDirName={autopf}\{{{install_dir_name}}}
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
PrivilegesRequired=lowest
OutputBaseFilename=singcast
SetupIconFile=..\..\..\assets\icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: ".\bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Icons]
Name: "{autoprograms}\{{{display_name}}}"; Filename: "{app}\singcast.exe"
Name: "{autodesktop}\{{{display_name}}}"; Filename: "{app}\singcast.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\singcast.exe"; Description: "{cm:LaunchProgram,{#StringChange({{{display_name}}}, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
