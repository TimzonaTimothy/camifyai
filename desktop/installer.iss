[Setup]
AppName=camifyai
AppVersion=1.0.0
DefaultDirName={autopf}\camifyai
DefaultGroupName=camifyai
OutputDir=installer_output
OutputBaseFilename=camifyai-Setup-1.0.0
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "installer\VC_redist.x64.exe"; \
    DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\camifyai"; Filename: "{app}\streamai.exe"
Name: "{commondesktop}\camifyai"; Filename: "{app}\streamai.exe"

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Visual C++ Runtime..."; \
    Flags: waituntilterminated
Filename: "{app}\streamai.exe"; \
    Description: "Launch camifyai"; Flags: nowait postinstall skipifsilent