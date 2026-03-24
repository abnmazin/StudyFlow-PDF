[Setup]
AppName=StudyFlow PDF Reader
AppVersion=1.0.0
AppPublisher=StudyFlow
DefaultDirName={autopf}\StudyFlow PDF Reader
DefaultGroupName=StudyFlow PDF Reader
OutputBaseFilename=StudyFlow_PDFReader_Setup
OutputDir=build\installer
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
ChangesAssociations=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\StudyFlow PDF Reader"; Filename: "{app}\pdfreader.exe"
Name: "{commondesktop}\StudyFlow PDF Reader"; Filename: "{app}\pdfreader.exe"

[Run]
Filename: "{app}\pdfreader.exe"; Description: "Launch StudyFlow PDF Reader"; Flags: postinstall nowait

[Registry]
Root: HKCR; Subkey: ".pdf"; ValueType: string; ValueName: ""; ValueData: "StudyFlowPDF"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "StudyFlowPDF"; ValueType: string; ValueName: ""; ValueData: "StudyFlow PDF Document"; Flags: uninsdeletekey
Root: HKCR; Subkey: "StudyFlowPDF\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pdfreader.exe,0"
Root: HKCR; Subkey: "StudyFlowPDF\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pdfreader.exe"" ""%1"""