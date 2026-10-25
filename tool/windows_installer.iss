; SARCADE Windows installer (Inno Setup 6.3+), built by the CI from the
; release build. Per-user or per-machine install, French and English.
; Unsigned until the code signing certificate is placed in the GitHub
; secrets (WINDOWS_CERT_PFX, WINDOWS_CERT_PASSWORD): the CI then signs it.
#define AppVersion GetEnv("SARCADE_VERSION")
#if AppVersion == ""
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{5F0E7C2A-1B8D-4C3E-9A6F-2D4B8E1C7A90}
AppName=SARCADE
AppVersion={#AppVersion}
AppVerName=SARCADE {#AppVersion}
AppPublisher=ADRASEC
DefaultDirName={autopf}\SARCADE
DefaultGroupName=SARCADE
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=sarcade-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
UninstallDisplayIcon={app}\sarcade_app.exe
; An update closes the running client before replacing its files.
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\SARCADE"; Filename: "{app}\sarcade_app.exe"
Name: "{autodesktop}\SARCADE"; Filename: "{app}\sarcade_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sarcade_app.exe"; Description: "{cm:LaunchProgram,SARCADE}"; Flags: nowait postinstall skipifsilent
