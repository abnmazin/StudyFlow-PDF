import pandas as pd

file_name = 'data.xlsx'
search_number = 1234567

# قراءة كل الصفحات ودمجها في جدول واحد ضخم
all_sheets = pd.read_excel(file_name, sheet_name=None, header=None)
df_combined = pd.concat(all_sheets.values(), ignore_index=True)

# بحث واحد سريع في الجدول المدمج
result = df_combined[df_combined.apply(lambda row: row.astype(str).str.contains(str(search_number)).any(), axis=1)]

if not result.empty:
    print(f"✅ تم العثور على الرقم {search_number} في {len(result)} موقع")
    print(result)
else:
    print("❌ لم يتم العثور على الرقم")