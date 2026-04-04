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