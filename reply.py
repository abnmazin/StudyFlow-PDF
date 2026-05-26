from telebot.types import *
def dev():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('شرح استخدام البوت',callback_data='help'))
    hk.add(InlineKeyboardButton('Abn Mazin',url='t.me/ffff_6'))
    return hk

def dev2():
    return InlineKeyboardMarkup().add(InlineKeyboardButton('Abn Mazin',url='t.me/ffff_6'))

def runn():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('ايقاف',callback_data='stop'))
    #hk.add(InlineKeyboardButton('تشغيل',callback_data='run'))
    return hk

def back():
    return InlineKeyboardMarkup().add(InlineKeyboardButton("رجوع",callback_data='back'))

def report():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('Spam - سبام',callback_data='spam'))
    hk.add(InlineKeyboardButton('Donst like - لايعجبني',callback_data='dontlike'))
    hk.add(InlineKeyboardButton('Self - سيلف',callback_data='self'))
    hk.add(InlineKeyboardButton('Drugs * مخدرات',callback_data='drugs'))
    hk.add(InlineKeyboardButton('Sex * اباحي',callback_data='sex'))
    hk.add(InlineKeyboardButton('Hate - كراهية',callback_data='hate'))
    hk.add(InlineKeyboardButton('Violence * عنف',callback_data='violence'))
    hk.add(InlineKeyboardButton('Bullying * ازعاج',callback_data='bullying'))
   # hk.add(InlineKeyboardButton('Scam - خداع',callback_data='scam'))
    hk.add(InlineKeyboardButton('Info - ملومات مزيفة',callback_data='info'))
    return hk

def ddrug():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('Fake health - مرض',callback_data='health'))
    hk.add(InlineKeyboardButton(' Drugs - مخدرات',callback_data='drugs2'))
    hk.add(InlineKeyboardButton('Guns - اسلحة',callback_data='guns'))
    hk.add(InlineKeyboardButton('Animals - حيوانات',callback_data='animals'))
    hk.add(InlineKeyboardButton('رجوع',callback_data='Back'))
    return hk

def sexy():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('Nudity - اباحي',callback_data='nudity'))
    hk.add(InlineKeyboardButton('Sexual - استغلال جنسي',callback_data='sexual'))
    hk.add(InlineKeyboardButton('Pri photo - صور خاصة',callback_data='pri'))
    hk.add(InlineKeyboardButton('sex child - اباحي طفل',callback_data='chaild'))
    hk.add(InlineKeyboardButton('رجوع',callback_data='Back'))
    return hk

def vol():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('Violence - عنف',callback_data='violence2'))
    hk.add(InlineKeyboardButton('Animal - عنف حيوان',callback_data='animalvo'))
    hk.add(InlineKeyboardButton('Death - موت',callback_data='death'))
    hk.add(InlineKeyboardButton('Individual - ارهاب',callback_data='dassh'))
    hk.add(InlineKeyboardButton('رجوع',callback_data='Back'))
    return hk

def bullying():
    hk=InlineKeyboardMarkup()
    hk.add(InlineKeyboardButton('Me - يزعجني',callback_data='me'))
    hk.add(InlineKeyboardButton('Someone i know - شخص اعرفه',callback_data='someone'))
    hk.add(InlineKeyboardButton('Someone else - شخص اخر',callback_data='someoneelse'))
    hk.add(InlineKeyboardButton('رجوع',callback_data='Back'))

    return hk
