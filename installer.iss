[Setup]
AppName=StudyFlow PDF Reader
; Stable identity for the app, not for one install: Windows and Inno keep an
; upgrade coupled to the *same* AppId. Without it Inno derives one from AppName,
; and any later change to AppName (or a second copy installed under a different
; name) would be treated as a different program — two entries in Add/Remove, and
; a silent update that installs beside the old build instead of over it.
AppId={{9F2C4E7A-6B31-4D8E-9A57-1C0B7F3E6D24}
; The version this installer carries. `tools/publish_release.ps1` passes it from
; `pubspec.yaml` (`/DAppVersion=1.2.0`), so the number in Add/Remove Programs
; cannot drift from the build inside; the line below is the fallback for a
; hand-run ISCC.
#ifndef AppVersion
  #define AppVersion "2.1.0"
#endif
AppVersion={#AppVersion}
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
; The updater starts Setup while the reader's own copy is still in the folder it
; is about to overwrite. `/CLOSEAPPLICATIONS` (see
; `update_service.dart::silentInstallArgs`) only has an effect because these are
; on: Inno finds the running `StudyFlowPDF.exe` by its path under `{app}`, closes
; it without asking, and then the file copy can succeed.
CloseApplications=yes
; Deliberately `no`, though Inno's default is `yes`. The only launch of the new
; build is the `[Run]` entry below, which silent mode still honours; letting Inno
; also restart the copy it closed would start two — and the second one finds port
; 45678 taken and shows the "another instance is running" screen. The app is
; already gone by the time Setup runs, so nothing is lost by turning this off.
RestartApplications=no

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

[Code]
// هذه الدالة تقوم بمسح المجلدات والملفات مع استثناءات محددة
procedure CleanOldFiles(Path: String);
var
	FindRec: TFindRec;
	FilePath: String;
begin
	if FindFirst(Path + '\*', FindRec) then
	begin
		try
			repeat
				if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
				begin
					FilePath := Path + '\' + FindRec.Name;

					// ⚠️ هنا نضع أسماء المجلدات أو الملفات التي نريد الحفاظ عليها (الاستثناءات)
					// مثلاً إذا كانت قاعدة بياناتك في مجلد اسمه "data" أو ملف اسمه "default.isar"
					if (LowerCase(FindRec.Name) <> 'data') and
						 (LowerCase(FindRec.Name) <> 'default.isar') and
						 (LowerCase(FindRec.Name) <> 'pdfs_storage') then // أضف أي مجلد تريد حمايته هنا
					begin
						if FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0 then
						begin
							// إذا كان مجلداً، ادخل وامسح محتوياته أولاً
							CleanOldFiles(FilePath);
							RemoveDir(FilePath);
						end
						else
						begin
							// إذا كان ملفاً، قم بحذفه
							DeleteFile(FilePath);
						end;
					end;
				end;
			until not FindNext(FindRec);
		finally
			FindClose(FindRec);
		end;
	end;
end;

// هذه الدالة المبنية في Inno Setup تعمل تلقائياً قبل بدء نسخ الملفات الجديدة
procedure CurStepChanged(CurStep: TSetupStep);
begin
	if CurStep = ssInstall then
	begin
		// إذا كان المجلد موجوداً (يعني هذا تحديث وليس تنصيب جديد)
		if DirExists(ExpandConstant('{app}')) then
		begin
			// استدعاء دالة التنظيف
			CleanOldFiles(ExpandConstant('{app}'));
		end;
	end;
end;