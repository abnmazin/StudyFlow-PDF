[Setup]
AppName=StudyFlow PDF Reader
AppVersion=1.0.0
AppPublisher=StudyFlow
AppComments=تم برمجة التطبيق بتاريخ 2 أبريل 2026 بواسطة Hassan Mazin
AppCopyright=© 2026 Hassan Mazin. جميع الحقوق محفوظة.
DefaultDirName={autopf}\StudyFlow PDF Reader
DefaultGroupName=StudyFlow PDF Reader
OutputBaseFilename=StudyFlowPDF_Setup
OutputDir=build\installer
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
ChangesAssociations=no

[Messages]
WelcomeLabel1=مرحباً بك في معالج تثبيت StudyFlow PDF Reader
WelcomeLabel2=هذا المعالج سيساعدك على تثبيت StudyFlow PDF Reader على جهازك. تم برمجة التطبيق بتاريخ 2 أبريل 2026 بواسطة Hassan Mazin.

[Tasks]
Name: "desktopicon"; Description: "إنشاء اختصار على سطح المكتب"; GroupDescription: "اختيارات إضافية"; Flags: unchecked
Name: "assocpdf"; Description: "جعل التطبيق المشغل الافتراضي لملفات PDF"; GroupDescription: "اختيارات إضافية"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs
Source: "pdf_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\StudyFlow PDF Reader"; Filename: "{app}\StudyFlowPDF.exe"
Name: "{commondesktop}\StudyFlow PDF Reader"; Filename: "{app}\StudyFlowPDF.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\StudyFlowPDF.exe"; Description: "Launch StudyFlow PDF Reader"; Flags: postinstall nowait

[Registry]
Root: HKCR; Subkey: ".pdf"; ValueType: string; ValueName: ""; ValueData: "StudyFlowPDF"; Flags: uninsdeletevalue; Tasks: assocpdf
Root: HKCR; Subkey: "StudyFlowPDF"; ValueType: string; ValueName: ""; ValueData: "StudyFlow PDF Document"; Flags: uninsdeletekey; Tasks: assocpdf
Root: HKCR; Subkey: "StudyFlowPDF\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pdf_icon.ico"; Tasks: assocpdf
Root: HKCR; Subkey: "StudyFlowPDF\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\StudyFlowPDF.exe"" ""%1"""; Tasks: assocpdf