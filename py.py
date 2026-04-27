import pandas as pd

file_name = 'data.xlsx'
search_number = 7702996800

# قراءة ملف الإكسيل، نحدد الصفحة المطلوبة فقط
df = pd.read_excel(file_name, sheet_name='محافضات', header=None)

# التأكد من وجود عمود D (الفهرس 3 لأن العد يبدأ من 0)
if df.shape[1] > 3:
    # البحث في العمود D فقط
    column_d = df[3].astype(str)  # العمود D هو الفهرس رقم 3
    mask = column_d.str.contains(str(search_number), na=False)
    result = df[mask]
    
    if not result.empty:
        print(f"✅ تم العثور على الرقم {search_number} في {len(result)} موقع")
        print(result)
    else:
        print("❌ لم يتم العثور على الرقم")
else:
    print("⚠️ الملف لا يحتوي على عمود D")

