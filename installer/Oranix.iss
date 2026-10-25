; Oranix installer (Inno Setup 6). Build with ..\build.ps1 -Installer
; Installs Oranix Player + Oranix Web for the current user (no admin needed), with Start menu entries,
; video file registration, and an uninstaller in Settings > Apps.

#define AppVersion "1.1.0"

[Setup]
AppId={{6B1E8F3A-2C4D-4E7A-9B5F-3A8D1C2E7F90}
AppName=Oranix
AppVersion={#AppVersion}
AppVerName=Oranix {#AppVersion}
AppPublisher=Oranix
AppComments=Play More. Worry Less.
; Outside AppData on purpose: the live-edit tools (..\live.ps1) can update it directly.
DefaultDirName={%USERPROFILE}\Oranix
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=OranixSetup
SetupIconFile=..\player\launcher\oranix-player.ico
UninstallDisplayIcon={app}\Player\Oranix Player.exe
UninstallDisplayName=Oranix (Player + Web)
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
CloseApplications=yes

[Tasks]
Name: desktopicon; Description: "Create desktop shortcuts"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: assoc; Description: "Offer Oranix Player for video files (.mkv, .mp4, ...)"; GroupDescription: "Video files:"

[InstallDelete]
; Leftovers from the earlier hand-made setup
Type: files; Name: "{userprograms}\Oranix.lnk"
Type: files; Name: "{localappdata}\Oranix\Oranix.exe"
Type: files; Name: "{localappdata}\Oranix\oranix.ico"

[Files]
Source: "..\dist\Player\*"; DestDir: "{app}\Player"; Flags: recursesubdirs ignoreversion
Source: "..\dist\Web\*"; DestDir: "{app}\Web"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userprograms}\Oranix Player"; Filename: "{app}\Player\Oranix Player.exe"; Comment: "Play videos on this PC"
Name: "{userprograms}\Oranix Web"; Filename: "{app}\Web\Oranix Web.exe"; Comment: "Watch web video with Oranix controls"
Name: "{userdesktop}\Oranix Player"; Filename: "{app}\Player\Oranix Player.exe"; Tasks: desktopicon
Name: "{userdesktop}\Oranix Web"; Filename: "{app}\Web\Oranix Web.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\Oranix.video"; ValueType: string; ValueData: "Oranix Player video"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\Oranix.video\DefaultIcon"; ValueType: string; ValueData: """{app}\Player\Oranix Player.exe"",0"; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\Oranix.video\shell\open\command"; ValueType: string; ValueData: """{app}\Player\Oranix Player.exe"" ""%1"""; Tasks: assoc
Root: HKCU; Subkey: "Software\Oranix\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Oranix Player"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Oranix\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Play More. Worry Less."; Tasks: assoc
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Oranix"; ValueData: "Software\Oranix\Capabilities"; Flags: uninsdeletevalue; Tasks: assoc
#define Assoc(Ext) \
  'Root: HKCU; Subkey: "Software\Oranix\Capabilities\FileAssociations"; ValueType: string; ValueName: "' + Ext + '"; ValueData: "Oranix.video"; Tasks: assoc' + NewLine + \
  'Root: HKCU; Subkey: "Software\Classes\' + Ext + '\OpenWithProgids"; ValueType: none; ValueName: "Oranix.video"; Flags: uninsdeletevalue; Tasks: assoc' + NewLine
#emit Assoc(".mkv") + Assoc(".mp4") + Assoc(".avi") + Assoc(".webm") + Assoc(".mov") + Assoc(".m4v") + Assoc(".wmv") + Assoc(".flv") + Assoc(".ts")

[Run]
Filename: "ms-settings:defaultapps?registeredAppUser=Oranix"; Description: "Choose Oranix Player as the default for video files"; Flags: postinstall shellexec skipifsilent unchecked; Tasks: assoc
Filename: "{app}\Web\Oranix Web.exe"; Description: "Open Oranix Web"; Flags: postinstall nowait skipifsilent unchecked
Filename: "{app}\Player\Oranix Player.exe"; Description: "Open Oranix Player"; Flags: postinstall nowait skipifsilent
