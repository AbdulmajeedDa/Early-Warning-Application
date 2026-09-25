// ═══════════════════════════════════════════════════════════════════════════
//  Early Warning App  —  نظام الإنذار المبكر
//  Flutter 3.x  |  Dart 3.x  |  v3 Bug-fixed & Image-ready
//
//  SETUP:
//   1. mkdir -p assets/images
//   2. Copy logo PNG → assets/images/logo.png
//   3. flutter pub get && flutter run
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'push_notifications.dart';
import 'google_auth.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // Restore the last saved theme/language before the first frame, so the
  // app doesn't flash the hardcoded defaults before switching.
  final prefs = await SharedPreferences.getInstance();
  appTheme.value = prefs.getString('app_theme') ?? appTheme.value;
  appLang.value = prefs.getString('app_lang') ?? appLang.value;
  runApp(const EarlyWarningApp());
}

// ── Global notifiers ───────────────────────────────────────────────────────
final ValueNotifier<String> appTheme = ValueNotifier('dark');
final ValueNotifier<String> appLang = ValueNotifier('ar');

// Persists a theme/language choice so it survives a full app restart —
// used by ThemesScreen/LanguageScreen right after they update the
// ValueNotifier above.
Future<void> savePrefChoice(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}
// Bumped by _handleForegroundAlert whenever a push arrives while the app is
// open, so the home screen's notification list/badge/stats/banner refresh
// immediately instead of waiting for the next full screen load.
final ValueNotifier<int> homeRefreshSignal = ValueNotifier(0);

// ── Translations ───────────────────────────────────────────────────────────
const Map<String, Map<String, String>> _tr = {
  'system_sub': {'ar': 'نظام الإنذار المبكر', 'en': 'Early Warning System'},
  'app_desc': {
    'ar':
        'نظام متكامل للإنذار المبكر من الزلازل والكوارث الطبيعية، يعمل على مدار الساعة لحمايتك وحماية عائلتك',
    'en':
        'A complete early warning system for earthquakes and natural disasters, operating 24/7 to protect you and your family'
  },
  'agree_terms': {
    'ar': 'أوافق على اتفاقية المستخدم وسياسة الخصوصية',
    'en': 'I agree to the Terms of Service & Privacy Policy'
  },
  'view_agreement_btn': {'ar': 'عرض الاتفاقية', 'en': 'View Agreement'},
  'terms_screen_title': {
    'ar': 'اتفاقية المستخدم وسياسة الخصوصية',
    'en': 'Terms of Service & Privacy Policy'
  },
  'terms_intro': {
    'ar':
        'يوضّح هذا المستند البيانات التي يجمعها تطبيق الإنذار المبكر منك، وصلاحيات الهاتف التي يطلبها، وكيفية استخدام هذه المعلومات. باستخدامك للتطبيق، فإنك توافق على ما يلي:',
    'en':
        'This document explains what data the Early Warning app collects from you, which phone permissions it requests, and how this information is used. By using the app, you agree to the following:'
  },
  'terms_data_title': {'ar': 'البيانات التي نجمعها', 'en': 'Data We Collect'},
  'terms_perms_title': {'ar': 'صلاحيات الهاتف', 'en': 'Device Permissions'},
  'terms_usage_title': {
    'ar': 'كيف نستخدم بياناتك',
    'en': 'How We Use Your Data'
  },
  'terms_sharing_title': {
    'ar': 'مشاركة البيانات مع أطراف خارجية',
    'en': 'Third-Party Data Sharing'
  },
  'terms_security_title': {'ar': 'أمان بياناتك', 'en': 'Data Security'},
  'terms_rights_title': {'ar': 'حقوقك', 'en': 'Your Rights'},
  'terms_changes_title': {
    'ar': 'التعديلات على هذه الاتفاقية',
    'en': 'Changes to This Agreement'
  },
  'must_agree': {
    'ar': 'يجب الموافقة على الشروط للمتابعة',
    'en': 'You must agree to the terms to continue'
  },
  'start_now': {'ar': 'ابدأ الآن', 'en': 'Get Started'},
  'login_title': {'ar': 'تسجيل الدخول', 'en': 'Login'},
  'login_sub': {
    'ar': 'أدخل بيانات حسابك للمتابعة',
    'en': 'Enter your account details to continue'
  },
  'gmail_hint': {'ar': 'أدخل حسابك (Gmail)', 'en': 'Enter your Gmail account'},
  'login_btn': {'ar': 'Login', 'en': 'Login'},
  'create_link': {'ar': 'Create a New Account', 'en': 'Create a New Account'},
  'or': {'ar': 'أو', 'en': 'or'},
  'google_btn': {'ar': 'تسجيل الدخول بـ Google', 'en': 'Sign in with Google'},
  'google_error': {
    'ar': 'تعذّر تسجيل الدخول عبر Google. حاول مرة أخرى',
    'en': 'Could not sign in with Google. Please try again'
  },
  'pass_hint': {'ar': 'أدخل كلمة مرورك', 'en': 'Enter your password'},
  'forgot_pass': {'ar': 'نسيت كلمة المرور؟', 'en': 'Forgot password?'},
  'wrong_pass': {'ar': 'كلمة المرور غير صحيحة', 'en': 'Incorrect password'},
  'need_email_first': {
    'ar': 'يرجى إدخال بريدك الإلكتروني أولاً',
    'en': 'Please enter your email first'
  },
  'reset_verify_title': {
    'ar': 'التحقق من البريد الإلكتروني',
    'en': 'Verify Email'
  },
  'reset_code_sent': {
    'ar': 'تم إرسال رمز التحقق إلى بريدك الإلكتروني',
    'en': 'A verification code has been sent to your email'
  },
  'reset_pass_title': {'ar': 'تعيين كلمة مرور جديدة', 'en': 'Set New Password'},
  'reset_pass_desc': {
    'ar': 'أدخل كلمة المرور الجديدة لحسابك',
    'en': 'Enter a new password for your account'
  },
  'new_pass_hint': {'ar': 'كلمة المرور الجديدة', 'en': 'New password'},
  'conf_new_pass_hint': {
    'ar': 'تأكيد كلمة المرور الجديدة',
    'en': 'Confirm new password'
  },
  'reset_pass_btn': {'ar': 'تغيير كلمة المرور', 'en': 'Change Password'},
  'change_pass_menu': {'ar': 'تغيير كلمة السر', 'en': 'Change Password'},
  'change_pass_title': {'ar': 'تغيير كلمة السر', 'en': 'Change Password'},
  'change_pass_desc': {
    'ar': 'أدخل كلمة السر الحالية وكلمة سر جديدة',
    'en': 'Enter your current password and a new one'
  },
  'current_pass_hint': {'ar': 'كلمة السر الحالية', 'en': 'Current password'},
  'change_pass_success': {
    'ar': 'تم تغيير كلمة السر بنجاح',
    'en': 'Password changed successfully'
  },
  'reset_pass_success': {
    'ar': 'تم تغيير كلمة المرور بنجاح',
    'en': 'Password changed successfully'
  },
  'acc_not_found': {
    'ar': 'الحساب غير موجود',
    'en': 'This account does not exist'
  },
  'welcome_back': {'ar': 'مرحباً بعودتك', 'en': 'Welcome Back'},
  'login_action': {'ar': 'تسجيل الدخول', 'en': 'Log In'},
  'reg_title': {'ar': 'إنشاء حساب جديد', 'en': 'Create New Account'},
  'step1': {
    'ar': 'الخطوة 1 من 2 — المعلومات الشخصية',
    'en': 'Step 1 of 2 — Personal Info'
  },
  'step2': {
    'ar': 'الخطوة 2 من 2 — بيانات الحساب',
    'en': 'Step 2 of 2 — Account Details'
  },
  'fn_hint': {'ar': 'أدخل الاسم الأول', 'en': 'Enter first name'},
  'ln_hint': {'ar': 'أدخل الاسم الثاني', 'en': 'Enter last name'},
  'city_hint': {'ar': 'أدخل مدينة الإقامة', 'en': 'Enter city of residence'},
  'change_photo': {
    'ar': 'تغيير صورة الملف الشخصي',
    'en': 'Change Profile Photo'
  },
  'pick_gallery': {'ar': 'اختيار من المعرض', 'en': 'Choose from Gallery'},
  'pick_camera': {'ar': 'التقاط صورة جديدة', 'en': 'Take a New Photo'},
  'street_lbl': {'ar': 'اسم الشارع', 'en': 'Street Name'},
  'street_hint': {
    'ar': 'أدخل اسم شارع الإقامة',
    'en': 'Enter your street name'
  },
  'building_lbl': {'ar': 'رقم محضر البناء', 'en': 'Building Permit No.'},
  'building_hint': {
    'ar': 'أدخل رقم محضر البناء',
    'en': 'Enter building permit number'
  },
  'city_err': {
    'ar': 'يرجى اختيار مدينة من القائمة',
    'en': 'Please select a city from the list'
  },
  'next_btn': {'ar': 'التالي', 'en': 'Next'},
  'continue_btn': {'ar': 'متابعة', 'en': 'Continue'},
  'complete_profile_title': {'ar': 'أكمل بياناتك', 'en': 'Complete your profile'},
  'complete_profile_sub': {
    'ar': 'تبقّت خطوة واحدة فقط قبل أن تصبح جاهزاً',
    'en': 'One more step before you\'re ready'
  },
  'optional_pass_hint': {
    'ar': 'كلمة مرور (اختياري)',
    'en': 'Password (optional)'
  },
  'optional_pass_note': {
    'ar': 'يمكنك إضافتها لاحقاً من الملف الشخصي أيضاً',
    'en': 'You can also add this later from your profile'
  },
  'email_hint': {'ar': 'أدخل بريدك الإلكتروني', 'en': 'Enter your email'},
  'newpass_hint': {'ar': 'أدخل كلمة مرورك', 'en': 'Enter your password'},
  'conf_hint': {'ar': 'تأكيد كلمة المرور', 'en': 'Confirm password'},
  'pass_short': {
    'ar':
        'كلمة المرور يجب أن تكون بين 8 و24 محرفًا إنكليزيًا (حروف وأرقام فقط)، وتحتوي على حرف واحد ورقم واحد على الأقل',
    'en':
        'Password must be 8 to 24 English letters and digits only, and include at least one letter and one number'
  },
  'create_btn': {'ar': 'إنشاء الحساب', 'en': 'Create Account'},
  'verify_title': {'ar': 'تأكيد الحساب', 'en': 'Verify Account'},
  'code_sent': {
    'ar': 'تم إرسال رمز التأكيد إلى حسابك',
    'en': 'Verification code sent to your account'
  },
  'no_code': {'ar': 'لم يصلك الرمز؟ ', 'en': "Didn't receive code? "},
  'resend': {'ar': 'أعد الإرسال', 'en': 'Resend'},
  'confirm_btn': {'ar': 'تأكيد', 'en': 'Confirm'},
  'acc_done': {
    'ar': 'تم إنشاء حسابك بنجاح!',
    'en': 'Account created successfully!'
  },
  'redirecting': {
    'ar': 'جاري الانتقال للواجهة الرئيسية...',
    'en': 'Redirecting to main screen...'
  },
  'welcome_msg': {'ar': 'أهلاً وسهلاً!', 'en': 'Welcome!'},
  'welcome_b2': {'ar': 'Welcome back', 'en': 'Welcome back'},
  'act_warning': {'ar': 'تحذير نشط', 'en': 'Active Warning'},
  'today_eq': {'ar': 'زلازل اليوم', 'en': "Today's Quakes"},
  'weat_warn': {'ar': 'تحذيرات جوية', 'en': 'Weather Alerts'},
  'floods': {'ar': 'فيضانات', 'en': 'Floods'},
  'emsc': {'ar': 'EMSC · قراءة مباشرة', 'en': 'EMSC · Live Feed'},
  'live_lbl': {'ar': '● مباشر', 'en': '● Live'},
  'richter_lbl': {
    'ar': 'مقياس ريختر — النشاط الزلزالي الراهن في سوريا',
    'en': 'Richter — Current seismic activity in Syria'
  },
  'last_eq': {'ar': 'آخر زلزال مُسجَّل', 'en': 'Last Recorded Earthquake'},
  'eq_mag': {'ar': 'الشدة', 'en': 'Magnitude'},
  'eq_depth': {'ar': 'العمق', 'en': 'Depth'},
  'eq_loc': {'ar': 'الموقع', 'en': 'Location'},
  'eq_km': {'ar': 'كم', 'en': 'km'},
  'recent': {'ar': 'آخر التنبيهات', 'en': 'Recent Alerts'},
  'prev_notif': {'ar': 'التنبيهات السابقة', 'en': 'Previous Notifications'},
  'menu_lbl': {'ar': 'القائمة', 'en': 'Menu'},
  'my_acc': {'ar': 'حسابي وبياناتي', 'en': 'My Account'},
  'lang_menu': {'ar': 'اللغة', 'en': 'Language'},
  'themes_menu': {'ar': 'السمات', 'en': 'Themes'},
  'reports_menu': {'ar': 'الإبلاغات', 'en': 'Reports'},
  'perms_menu': {'ar': 'الأذونات', 'en': 'Permissions'},
  'about_menu': {'ar': 'من نحن', 'en': 'About Us'},
  'dyfi_menu': {'ar': 'هل شعرت بزلزال؟', 'en': 'Did You Feel It?'},
  'dyfi_title': {'ar': 'هل شعرت بزلزال؟', 'en': 'Did You Feel It?'},
  'dyfi_reports_24h': {
    'ar': 'تقرير خلال آخر 24 ساعة',
    'en': 'reports in the last 24 hours'
  },
  'dyfi_magnitude_lbl': {'ar': 'قوة الزلزال', 'en': 'Magnitude'},
  'dyfi_location_lbl': {'ar': 'المنطقة', 'en': 'Location'},
  'dyfi_select_hint': {
    'ar': 'اختر من 1 إلى 3 مستويات تصف ما شعرت به',
    'en': 'Select 1 to 3 levels that describe what you felt'
  },
  'dyfi_submit_btn': {'ar': 'إرسال التقرير', 'en': 'Submit Report'},
  'dyfi_max_selection': {
    'ar': 'يمكنك اختيار 3 مستويات كحد أقصى',
    'en': 'You can select up to 3 levels'
  },
  'dyfi_no_city': {
    'ar': 'يرجى إكمال المحافظة في ملفك الشخصي أولاً',
    'en': 'Please complete your city in your profile first'
  },
  'dyfi_no_quake': {
    'ar': 'لا يوجد زلزال حديث بالقرب منك للإبلاغ عنه',
    'en': 'There is no recent earthquake near you to report'
  },
  'dyfi_already_reported': {
    'ar': 'شكرًا لك! لقد أرسلت تقريرك عن هذا الزلزال مسبقًا',
    'en': 'Thank you! You already submitted a report for this earthquake'
  },
  'dyfi_load_error': {
    'ar': 'تعذّر تحميل بيانات الزلزال',
    'en': 'Could not load earthquake data'
  },
  'eq_history_menu': {'ar': 'سجل الزلازل', 'en': 'Earthquake History'},
  'eq_history_title': {'ar': 'سجل الزلازل', 'en': 'Earthquake History'},
  'eq_history_load_error': {
    'ar': 'تعذّر تحميل سجل الزلازل',
    'en': 'Could not load earthquake history'
  },
  'eq_history_empty': {
    'ar': 'لا توجد زلازل مسجّلة حتى الآن',
    'en': 'No earthquakes recorded yet'
  },
  'forecast_load_error': {
    'ar': 'تعذّر تحميل توقعات الطقس',
    'en': 'Could not load the weather forecast'
  },
  'forecast_today': {'ar': 'اليوم', 'en': 'Today'},
  'load_more_btn': {'ar': 'تحميل المزيد', 'en': 'Load More'},
  'logout_menu': {'ar': 'تسجيل الخروج', 'en': 'Logout'},
  'edit_lbl': {'ar': 'تعديل', 'en': 'Edit'},
  'cancel_lbl': {'ar': 'إلغاء', 'en': 'Cancel'},
  'save_lbl': {'ar': 'حفظ التعديلات', 'en': 'Save Changes'},
  'saved_ok': {'ar': 'تم حفظ التعديلات ✓', 'en': 'Changes saved ✓'},
  'fn_lbl': {'ar': 'الاسم الأول', 'en': 'First Name'},
  'ln_lbl': {'ar': 'الاسم الثاني', 'en': 'Last Name'},
  'city_lbl': {'ar': 'المدينة', 'en': 'City'},
  'email_lbl': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
  'lang_title': {'ar': 'اللغة', 'en': 'Language'},
  'arabic': {'ar': 'العربية', 'en': 'Arabic'},
  'english': {'ar': 'الإنجليزية', 'en': 'English'},
  'themes_title': {'ar': 'السمات', 'en': 'Themes'},
  'mode_lbl': {'ar': 'مود التطبيق والألوان', 'en': 'App Mode & Colors'},
  'dark_lbl': {'ar': 'داكن', 'en': 'Dark'},
  'light_lbl': {'ar': 'ساطع', 'en': 'Light'},
  'classic_lbl': {'ar': 'كلاسيكي', 'en': 'Classic'},
  'dark_desc': {
    'ar': 'ألوان داكنة خفيفة — الافتراضي',
    'en': 'Dark subtle colors — Default'
  },
  'light_desc': {'ar': 'ألوان ساطعة زاهية', 'en': 'Bright vivid colors'},
  'classic_desc': {
    'ar': 'ألوان كلاسيكية أنيقة',
    'en': 'Classic elegant colors'
  },
  'slogan': {
    'ar': 'رأيكم يهمنا\nوالتعاون أساس التطور',
    'en': 'Your opinion matters\nCooperation drives progress'
  },
  'new_rep': {'ar': 'إبلاغ جديد', 'en': 'New Report'},
  'hist_rep': {'ar': 'سجل الإبلاغات', 'en': 'Report History'},
  'rep_hint': {
    'ar': 'اكتب إبلاغك هنا...\n(الحد الأقصى 400 حرف)',
    'en': 'Write your report here...\n(max 400 characters)'
  },
  'send_rep': {'ar': 'إرسال الإبلاغ', 'en': 'Send Report'},
  'rep_sent': {'ar': 'تم إرسال الإبلاغ', 'en': 'Report Sent'},
  'thank_you': {'ar': 'شكراً لتعاونكم', 'en': 'Thank you for your cooperation'},
  'hist_title': {'ar': 'سجل الإبلاغات', 'en': 'Report History'},
  'no_reps': {'ar': 'لا توجد بلاغات لعرضها', 'en': 'No reports to display'},
  'rep_content': {'ar': 'نص الإبلاغ', 'en': 'Report Content'},
  'team_reply': {'ar': 'رد فريق العمل', 'en': 'Team Reply'},
  'rep_pending': {
    'ar': 'لا يوجد رد من فريق العمل حتى الآن',
    'en': 'No reply from the team yet'
  },
  'reports_load_error': {
    'ar': 'تعذّر تحميل سجل الإبلاغات',
    'en': 'Could not load report history'
  },
  'prec_load_error': {
    'ar': 'تعذّر تحميل الاحتياطات',
    'en': 'Could not load precautions'
  },
  'cached_data_note': {
    'ar': 'تُعرض بيانات محفوظة مسبقاً، قد لا تكون محدّثة',
    'en': 'Showing previously saved data — may not be up to date'
  },
  'perm_title': {'ar': 'الأذونات', 'en': 'Permissions'},
  'p1_title': {'ar': 'تلقي الإشعارات', 'en': 'Receive Notifications'},
  'p1_desc': {
    'ar': 'داخل وخارج التطبيق وأثناء وضع السكون',
    'en': 'In/out of app and during sleep mode'
  },
  'p2_title': {'ar': 'تفعيل صوت الإنذار', 'en': 'Enable Alert Sound'},
  'p2_desc': {
    'ar': 'تشغيل صوت التحذير بأعلى مستوى ممكن',
    'en': 'Play warning sound at maximum volume'
  },
  'p3_title': {'ar': 'التحديث التلقائي', 'en': 'Auto Update'},
  'p3_desc': {
    'ar': 'تحديث التطبيق تلقائياً عند توفر إصدار جديد',
    'en': 'Update app automatically when a new version is available'
  },
  'about_load_error': {
    'ar': 'تعذّر تحميل محتوى هذه الصفحة',
    'en': 'Could not load this page\'s content'
  },
  'made_love': {'ar': 'صُنع بحب لسوريا', 'en': 'Made with love for Syria'},
  'fb_page': {'ar': 'صفحتنا على فيس بوك:', 'en': 'Our Facebook Page:'},
  'fb_link': {'ar': 'link', 'en': 'link'},
  'sim_btn': {'ar': 'محاكي الخطر', 'en': 'Danger Simulator'},
  'sim_title': {'ar': 'محاكي الخطر', 'en': 'Danger Simulator'},
  'sim_launch': {
    'ar': 'إطلاق عملية محاكاة الخطر',
    'en': 'Launch Danger Simulation'
  },
  'sim_stop': {'ar': 'إيقاف المحاكاة', 'en': 'Stop Simulation'},
  'sim_desc': {
    'ar':
        'تُحاكي هذه الأداة سيناريو إنذار حقيقي لاختبار جاهزيتك وسرعة استجابتك عند وقوع كارثة طبيعية',
    'en':
        'This tool simulates a real alert scenario to test your readiness and response speed during a natural disaster'
  },
  'sim_warn': {
    'ar': 'تحذير: سوف يتم تشغيل صوت إنذار مرتفع',
    'en': 'Warning: A loud alarm sound will play'
  },
  'sim_running': {'ar': 'المحاكاة جارية...', 'en': 'Simulation Running...'},
  'sim_select_type': {
    'ar': 'اختر نوع الكارثة التي تريد محاكاتها',
    'en': 'Choose a disaster type to simulate'
  },
  'sim_relief_btn': {
    'ar': 'طلب إغاثة (تدريبي)',
    'en': 'Request Relief (Training)'
  },
  'sim_relief_title': {'ar': 'تدريب', 'en': 'Training'},
  'sim_relief_body': {
    'ar':
        'لو كانت هذه حالة طوارئ حقيقية، لكان تم إرسال طلب الإغاثة التالي تلقائياً من حسابك:',
    'en':
        'If this were a real emergency, the following relief request would be sent automatically from your account:'
  },
  'sim_relief_no_data': {
    'ar': 'معاينة تدريبية فقط — لن يتم إرسال أي بيانات فعلياً',
    'en': 'Training preview only — no data will actually be sent'
  },
  'sim_critical': {'ar': 'حرج', 'en': 'Critical'},
  'precautions_menu': {
    'ar': 'التعليمات الاحترازية',
    'en': 'Safety Instructions'
  },
  'precautions_title': {
    'ar': 'التعليمات الاحترازية العامة',
    'en': 'General Safety Instructions'
  },
  'prec_phases': {'ar': 'قبل · أثناء · بعد', 'en': 'Before · During · After'},
  'prec_before': {'ar': 'قبل الكارثة', 'en': 'Before'},
  'prec_during': {'ar': 'أثناء الكارثة', 'en': 'During'},
  'prec_after': {'ar': 'بعد الكارثة', 'en': 'After'},
  'prec_eq': {
    'ar': 'التعليمات الاحترازية الخاصة بالزلازل',
    'en': 'Earthquake Safety Instructions'
  },
  'prec_torrent': {
    'ar': 'التعليمات الاحترازية الخاصة بالسيول',
    'en': 'Flash Flood Safety Instructions'
  },
  'prec_flood': {
    'ar': 'التعليمات الاحترازية الخاصة بالفيضانات',
    'en': 'Flood Safety Instructions'
  },
  'prec_severe_storm': {
    'ar': 'التعليمات الاحترازية الخاصة بالعواصف الشديدة',
    'en': 'Severe Storm Safety Instructions'
  },
  'prec_coastal_storm': {
    'ar': 'التعليمات الاحترازية الخاصة بالعواصف الساحلية الشديدة',
    'en': 'Severe Coastal Storm Safety Instructions'
  },
  'prec_tsunami': {
    'ar': 'التعليمات الاحترازية الخاصة بالتسونامي',
    'en': 'Tsunami Safety Instructions'
  },
  'logout_q': {'ar': 'هل تريد تسجيل الخروج؟', 'en': 'Do you want to logout?'},
  'yes_btn': {'ar': 'نعم', 'en': 'Yes'},
  'farewell': {'ar': 'رافقتكم السلامة', 'en': 'Stay Safe'},
  'filter_lbl': {'ar': 'فلترة التنبيهات', 'en': 'Filter Alerts'},
  'filter_type': {'ar': 'نوع التنبيه', 'en': 'Alert Type'},
  'filter_sort': {'ar': 'طريقة الترتيب', 'en': 'Sort Order'},
  'flt_all': {'ar': 'الكل', 'en': 'All'},
  'flt_weather_all': {
    'ar': 'كل التحذيرات الجوية',
    'en': 'All Weather Warnings'
  },
  'flt_eq': {'ar': 'زلازل', 'en': 'Earthquakes'},
  'flt_severe_storm': {'ar': 'عواصف شديدة', 'en': 'Severe Storms'},
  'flt_coastal_storm': {'ar': 'عواصف ساحلية', 'en': 'Coastal Storms'},
  'flt_flood': {'ar': 'فيضانات', 'en': 'Floods'},
  'flt_torrent': {'ar': 'سيول', 'en': 'Flash Floods'},
  'flt_tsunami': {'ar': 'تسونامي', 'en': 'Tsunami'},
  'sort_newest': {'ar': 'من الأحدث', 'en': 'Newest First'},
  'sort_oldest': {'ar': 'من الأقدم', 'en': 'Oldest First'},
  'done_btn': {'ar': 'تم', 'en': 'Done'},
  'no_notifs': {
    'ar': 'لا توجد تنبيهات للعرض',
    'en': 'No notifications to display'
  },
  'weather_sec': {'ar': 'الطقس في المحافظات', 'en': 'Governorate Weather'},
  'relief_btn': {'ar': 'الإغاثة', 'en': 'Relief'},
  'relief_title': {'ar': 'مركز الإغاثة', 'en': 'Relief Center'},
  'relief_ready': {
    'ar': 'فريق الإغاثة جاهز لنجدتك',
    'en': 'Relief Team Ready to Help You'
  },
  'relief_info': {
    'ar': 'يتم أخذ بياناتك المسجلة تلقائياً',
    'en': 'Your registered data is used automatically'
  },
  'relief_send': {'ar': 'إرسال طلب إغاثة', 'en': 'Send Relief Request'},
  'relief_sent': {
    'ar': 'فرق الإغاثة في طريقها إليك',
    'en': 'Relief Teams Are on Their Way'
  },
  'relief_ok': {'ar': 'حسناً', 'en': 'OK'},
  'resend_btn': {'ar': 'إعادة الإرسال', 'en': 'Resend'},
  'relief_teams': {'ar': 'فريق الإغاثة النشط', 'en': 'Active Relief Teams'},
  'active_teams': {
    'ar': 'عدد الفرق النشطة على الأرض',
    'en': 'Active Teams on the Ground'
  },
  'team_unit': {'ar': 'فريق', 'en': 'Teams'},
  'teams_load_error': {
    'ar': 'تعذّر تحميل فرق الإغاثة',
    'en': 'Could not load relief teams'
  },
  'retry_btn': {'ar': 'إعادة المحاولة', 'en': 'Retry'},
  'no_teams': {
    'ar': 'لا توجد فرق إغاثة نشطة حالياً',
    'en': 'No active relief teams right now'
  },
  'weather_load_error': {
    'ar': 'تعذّر تحميل بيانات الطقس',
    'en': 'Could not load weather data'
  },
  'no_weather': {
    'ar': 'لا توجد بيانات طقس متاحة حالياً',
    'en': 'No weather data available right now'
  },
  'notifs_load_error': {
    'ar': 'تعذّر تحميل الإشعارات',
    'en': 'Could not load notifications'
  },
};

String t(String key) => _tr[key]?[appLang.value] ?? _tr[key]?['ar'] ?? key;

// 8-24 chars, English letters + digits only, at least one letter and one
// digit — matches the backend's password validation rule exactly.
final RegExp _passwordPattern =
    RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9]{8,24}$');
bool isValidPassword(String pw) => _passwordPattern.hasMatch(pw);

String relativeTime(String? isoString) {
  if (isoString == null) return '';
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return '';
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  final ar = appLang.value == 'ar';
  if (diff.inMinutes < 1) return ar ? 'الآن' : 'just now';
  if (diff.inMinutes < 60) {
    return ar ? 'منذ ${diff.inMinutes} دقيقة' : '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) {
    if (diff.inHours == 1) return ar ? 'منذ ساعة' : '1 hour ago';
    return ar ? 'منذ ${diff.inHours} ساعة' : '${diff.inHours} hours ago';
  }
  if (diff.inDays == 1) return ar ? 'منذ يوم' : '1 day ago';
  return ar ? 'منذ ${diff.inDays} يوم' : '${diff.inDays} days ago';
}

// Reads a {"ar": ..., "en": ...} bilingual object the same way every
// other bilingual field in the app is read.
String bilingual(dynamic m) {
  if (m is Map) {
    return (appLang.value == 'ar' ? m['ar'] : m['en'])?.toString() ?? '';
  }
  return '';
}

// Splits a real instructions paragraph into sentence-level bullet points —
// the backend stores each phase as one continuous paragraph, not a list, so
// this rebuilds a bullet-list (or a single "quick tip") from it. Used by the
// Precautions detail screen and the Danger Simulator's alert dialog.
List<String> splitSentences(String? text) {
  if (text == null || text.trim().isEmpty) return [];
  return text
      .split(RegExp(r'(?<=[.!])\s+'))
      .map((s) => s.trim().replaceAll(RegExp(r'[.!]+$'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

// A labelled "icon — label — value" row, used anywhere the app shows a
// user's auto-filled profile data (the real relief request, and the Danger
// Simulator's training relief preview).
Widget infoRow(EWColors c, IconData icon, String label, String value) =>
    Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: c.primary, size: 16),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: c.textSub, fontSize: 13)),
          const Spacer(),
          Text(value.isNotEmpty ? value : '—',
              style: TextStyle(
                  color: value.isNotEmpty ? c.text : c.textSub,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]));

// Buckets a real Open-Meteo/WMO weather_code into the three visual
// categories the weather cards' design supports (sunny/cloudy/rainy) —
// shared by the home screen's weather strip and the per-city forecast
// screen so both read the exact same codes the exact same way.
String weatherCond(dynamic code) {
  final wc = code is int ? code : int.tryParse(code?.toString() ?? '') ?? -1;
  if (wc == 0 || wc == 1) return 's';
  const rainCodes = [
    51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99
  ];
  if (rainCodes.contains(wc)) return 'r';
  return 'c';
}

// Colored Richter-intensity bar. `compact` drops the floating magnitude
// badge and the label row underneath, for reuse inside a list item.
Widget richterScale(EWColors c, double mag, {bool compact = false}) {
  const segColors = [
    Color(0xFF4ADE80), // 1-2  خفيف
    Color(0xFFA3E635), // 2-3  محسوس
    Color(0xFFFBBF24), // 3-4  متوسط
    Color(0xFFF97316), // 4-5  قوي
    Color(0xFFEF4444), // 5-6  شديد
    Color(0xFF7C3AED), // 6+   مدمر
  ];
  const segLabels = ['خفيف', 'محسوس', 'متوسط', 'قوي', 'شديد', 'مدمر'];
  final int ai = (mag.clamp(1.0, 6.99) - 1.0).floor().clamp(0, 5);

  final bars = Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: List.generate(segColors.length, (i) {
      final active = i == ai;
      return Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!compact)
          if (active)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: segColors[i], borderRadius: BorderRadius.circular(5)),
              child: Text(mag.toStringAsFixed(1),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            )
          else
            const SizedBox(height: 20),
        Container(
          height: active ? (compact ? 8 : 13) : (compact ? 4 : 7),
          margin: EdgeInsets.only(left: i > 0 ? (compact ? 2 : 3) : 0),
          decoration: BoxDecoration(
            color: segColors[i].withOpacity(active ? 1.0 : 0.28),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ]));
    }),
  );

  if (compact) return bars;

  return Column(children: [
    bars,
    const SizedBox(height: 5),
    Row(
        children: List.generate(
      segColors.length,
      (i) => Expanded(
        child: Text(segLabels[i],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              fontWeight: i == ai ? FontWeight.bold : FontWeight.normal,
              color: i == ai ? segColors[i] : c.textSub,
            )),
      ),
    )),
  ]);
}

// ── Theme Colors ───────────────────────────────────────────────────────────
@immutable
class EWColors extends ThemeExtension<EWColors> {
  final Color bg,
      surface,
      input,
      primary,
      accent,
      danger,
      success,
      text,
      textSub,
      border;
  const EWColors(
      {required this.bg,
      required this.surface,
      required this.input,
      required this.primary,
      required this.accent,
      required this.danger,
      required this.success,
      required this.text,
      required this.textSub,
      required this.border});

  @override
  EWColors copyWith(
          {Color? bg,
          Color? surface,
          Color? input,
          Color? primary,
          Color? accent,
          Color? danger,
          Color? success,
          Color? text,
          Color? textSub,
          Color? border}) =>
      EWColors(
          bg: bg ?? this.bg,
          surface: surface ?? this.surface,
          input: input ?? this.input,
          primary: primary ?? this.primary,
          accent: accent ?? this.accent,
          danger: danger ?? this.danger,
          success: success ?? this.success,
          text: text ?? this.text,
          textSub: textSub ?? this.textSub,
          border: border ?? this.border);

  @override
  EWColors lerp(EWColors? other, double t) => this;

  static const dark = EWColors(
    bg: Color(0xFF080D1A),
    surface: Color(0xFF0F1628),
    input: Color(0xFF162040),
    primary: Color(0xFFF97316),
    accent: Color(0xFF0EA5E9),
    danger: Color(0xFFEF4444),
    success: Color(0xFF10B981),
    text: Color(0xFFE8EDF5),
    textSub: Color(0xFF64748B),
    border: Color(0x18FFFFFF),
  );
  static const light = EWColors(
    bg: Color(0xFFF0F4F8),
    surface: Color(0xFFFFFFFF),
    input: Color(0xFFE8EEF6),
    primary: Color(0xFFEA6C00),
    accent: Color(0xFF0284C7),
    danger: Color(0xFFDC2626),
    success: Color(0xFF059669),
    text: Color(0xFF0F172A),
    textSub: Color(0xFF64748B),
    border: Color(0x22000000),
  );
  static const classic = EWColors(
    bg: Color(0xFF1C1C2E),
    surface: Color(0xFF2A2A3E),
    input: Color(0xFF363650),
    primary: Color(0xFFD4A017),
    accent: Color(0xFF7C83FD),
    danger: Color(0xFFE05252),
    success: Color(0xFF4CAF7D),
    text: Color(0xFFF5F0E8),
    textSub: Color(0xFF9E9E9E),
    border: Color(0x20F5F0E8),
  );

  static EWColors of(String theme) {
    switch (theme) {
      case 'light':
        return light;
      case 'classic':
        return classic;
      default:
        return dark;
    }
  }
}

EWColors col(BuildContext ctx) =>
    Theme.of(ctx).extension<EWColors>() ?? EWColors.dark;

ThemeData buildTheme(String theme) {
  final c = EWColors.of(theme);
  final isDark = theme != 'light';
  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.bg,
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: c.primary, surface: c.surface, error: c.danger)
        : ColorScheme.light(
            primary: c.primary, surface: c.surface, error: c.danger),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      elevation: 0,
      iconTheme: IconThemeData(color: c.text),
      titleTextStyle:
          TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.bold),
    ),
    extensions: <ThemeExtension<dynamic>>[c],
  );
}

// ── Data ───────────────────────────────────────────────────────────────────
class SyrianCity {
  final String id, nameAr, nameEn;
  const SyrianCity(this.id, this.nameAr, this.nameEn);
  String get name => appLang.value == 'ar' ? nameAr : nameEn;
}

List<SyrianCity> cities = [];
bool _citiesLoaded = false;

const _citiesCacheKey = 'cached_cities';

Future<void> _cacheCities(List<SyrianCity> list) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
        list.map((c) => {'code': c.id, 'ar': c.nameAr, 'en': c.nameEn}).toList());
    await prefs.setString(_citiesCacheKey, encoded);
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<List<SyrianCity>?> _readCachedCities() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_citiesCacheKey);
    if (raw == null) return null;
    final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (decoded.isEmpty) return null;
    return decoded
        .map((c) => SyrianCity(
            c['code'] as String, c['ar'] as String, c['en'] as String))
        .toList();
  } catch (_) {
    return null;
  }
}

// Best-effort background prefetch, kicked off once at app startup. Screens
// that need the list (registration, profile) retry it themselves in
// initState if it's still empty by the time they open, so a slow or failed
// first attempt doesn't permanently break the city picker. The persisted
// cache means `cities` is populated immediately from a previous session
// even before this live refresh finishes (or if it fails entirely).
Future<void> loadCities() async {
  if (_citiesLoaded) return;

  if (cities.isEmpty) {
    final cached = await _readCachedCities();
    if (cached != null) cities = cached;
  }

  try {
    final res = await ApiClient.get('/cities', auth: false);
    final list = (res['cities'] as List).cast<Map<String, dynamic>>().map((c) {
      final name = c['name'] as Map<String, dynamic>;
      return SyrianCity(
          c['code'] as String, name['ar'] as String, name['en'] as String);
    }).toList();
    if (list.isNotEmpty) {
      cities = list;
      _citiesLoaded = true;
      unawaited(_cacheCities(list));
    }
  } catch (_) {
    // Not fatal — retried by whichever screen needs the list next.
  }
}

// Precaution instructions are safety-critical content that must stay
// readable even with no signal (plausible during an actual disaster), so
// the raw /disaster-types response is cached to disk on every successful
// fetch and used as a fallback when a later fetch fails.
const _disasterTypesCacheKey = 'cached_disaster_types';

const _aboutCacheKey = 'cached_about';

Future<void> _cacheAbout(Map<String, dynamic> about) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aboutCacheKey, jsonEncode(about));
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<Map<String, dynamic>?> _readCachedAbout() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aboutCacheKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> _cacheDisasterTypes(List<Map<String, dynamic>> list) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_disasterTypesCacheKey, jsonEncode(list));
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<List<Map<String, dynamic>>?> _readCachedDisasterTypes() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_disasterTypesCacheKey);
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return null;
  }
}

// Best-effort background prefetch at app startup, so the cache is already
// warm the first time a user actually needs it (see the note above).
Future<void> prefetchDisasterTypes() async {
  try {
    final res = await ApiClient.get('/disaster-types', auth: false);
    final list = (res['disaster_types'] as List).cast<Map<String, dynamic>>();
    await _cacheDisasterTypes(list);
  } catch (_) {
    // Not fatal — retried whenever a precaution screen is actually opened.
  }
}

// Same fallback idea as disaster types, but this data is personal — keyed
// by the account's email so a different user signing in on the same device
// never briefly sees the previous user's cached notifications.
Future<void> _cacheNotifications(List<Map<String, dynamic>> list) async {
  if (user.email.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'cached_notifications_${user.email}', jsonEncode(list));
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<List<Map<String, dynamic>>?> _readCachedNotifications() async {
  if (user.email.isEmpty) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_notifications_${user.email}');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return null;
  }
}

// Weather is public/shared data (same for every user), so no per-user key
// is needed here, unlike notifications above.
Future<void> _cacheWeather(List<Map<String, dynamic>> list) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_weather', jsonEncode(list));
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<List<Map<String, dynamic>>?> _readCachedWeather() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_weather');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return null;
  }
}

// Nationwide, not personal, like weather above — one shared cache key.
Future<void> _cacheSummary(Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_home_summary', jsonEncode(data));
  } catch (_) {
    // Not fatal — the live fetch already succeeded, this is just the backup.
  }
}

Future<Map<String, dynamic>?> _readCachedSummary() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_home_summary');
    if (raw == null) return null;
    return raw.isEmpty ? null : (jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

class AppUser {
  String firstName = '',
      lastName = '',
      cityId = '',
      cityName = '',
      email = '',
      streetName = '',
      buildingNumber = '';
  String? profileImageUrl; // already saved on the server
  bool isNew = true;
}

final AppUser user = AppUser();

/// Real logout: stops push for this device, revokes the token on the server,
/// then always clears the locally saved token — even if the network calls
/// fail or time out — so the app can never silently auto-login again after
/// the user chose to log out.
Future<void> performLogout() async {
  try {
    await () async {
      await PushNotifications.unregisterDeviceToken();
      await ApiClient.post('/logout', {});
    }()
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    // Best-effort only; local cleanup below is what actually matters.
  }
  await TokenStorage.clear();
  await UserCache.clear();
}

// Fills the global `user` from the `user` object returned by /register,
// /verify-otp or /login, keeping whatever local fields the response doesn't
// include (e.g. it never sends the password back). Also remembers the raw
// object locally so the app can reopen offline later (see AuthGate).
void applyUserFromJson(Map<String, dynamic> json) {
  unawaited(UserCache.save(json));
  user
    ..firstName = json['first_name'] as String? ?? user.firstName
    ..lastName = json['last_name'] as String? ?? user.lastName
    ..email = json['email'] as String? ?? user.email
    ..streetName = json['street_name'] as String? ?? user.streetName
    ..buildingNumber = json['building_number'] as String? ?? user.buildingNumber
    ..profileImageUrl = json['profile_image'] as String?;

  final city = json['city'];
  if (city is Map<String, dynamic>) {
    user.cityId = city['code'] as String? ?? user.cityId;
    final name = city['name'];
    if (name is Map<String, dynamic>) {
      user.cityName =
          (appLang.value == 'ar' ? name['ar'] : name['en']) as String? ??
              user.cityName;
    }
  }
}

// ── Root App ───────────────────────────────────────────────────────────────
class EarlyWarningApp extends StatefulWidget {
  const EarlyWarningApp({super.key});
  @override
  State<EarlyWarningApp> createState() => _AppState();
}

class _AppState extends State<EarlyWarningApp> {
  StreamSubscription<RemoteMessage>? _foregroundSub;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    appTheme.addListener(_rebuild);
    appLang.addListener(_rebuild);
    _foregroundSub = PushNotifications.foregroundMessages.listen(_handleForegroundAlert);
    loadCities();
    prefetchDisasterTypes();
  }

  @override
  void dispose() {
    appTheme.removeListener(_rebuild);
    appLang.removeListener(_rebuild);
    _foregroundSub?.cancel();
    super.dispose();
  }

  // The app is open right now, so FCM does not show a system notification
  // on its own — this is the in-app equivalent, styled like the Danger
  // Simulator's alert dialog, using the real alert content instead of a
  // static demo message.
  void _handleForegroundAlert(RemoteMessage message) {
    if (message.data['trigger_siren'] == '1') {
      PushNotifications.playSiren();
    }

    homeRefreshSignal.value++;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final c = col(ctx);

    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (dCtx) => Directionality(
        textDirection: appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: c.surface,
          title: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 64,
                height: 64,
                decoration:
                    BoxDecoration(color: c.danger.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(Icons.warning_amber_rounded, color: c.danger, size: 36)),
            const SizedBox(height: 12),
            Text(message.notification?.title ?? t('act_warning'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.text)),
          ]),
          content: Text(message.notification?.body ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSub, fontSize: 14, height: 1.5)),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dCtx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(t('relief_ok')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Early Warning',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(appTheme.value),
      builder: (ctx, child) => Directionality(
        textDirection:
            appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const AuthGate(),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

Widget buildLogo(BuildContext ctx, {double size = 88}) {
  return Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
            )),
            child: Icon(Icons.warning_rounded,
                color: Colors.white, size: size * 0.5),
          ),
        ),
      ),
    ),
    const SizedBox(height: 14),
    Text('EARLY WARNING',
        style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: col(ctx).text,
            letterSpacing: 2.5)),
    const SizedBox(height: 5),
    Text(t('system_sub'),
        style:
            TextStyle(fontSize: 13, color: col(ctx).primary, letterSpacing: 1)),
  ]);
}

// New Syrian flag (post-2024): green–white–black stripes, three red stars.
Widget newSyriaFlag({double width = 36, double height = 26}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: Colors.black12, width: 0.5),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: [
      Expanded(child: Container(color: const Color(0xFF007A3D))),
      Expanded(
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                3,
                (i) => Icon(Icons.star,
                    color: const Color(0xFFCE1126), size: height * 0.4)),
          ),
        ),
      ),
      Expanded(child: Container(color: Colors.black)),
    ]),
  );
}

class RichterPainter extends CustomPainter {
  final Color color;
  final double sw;
  RichterPainter(this.color, {this.sw = 2.0});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(0, h / 2)
          ..lineTo(w * .07, h / 2)
          ..lineTo(w * .13, h * .1)
          ..lineTo(w * .2, h * .9)
          ..lineTo(w * .27, h * .2)
          ..lineTo(w * .34, h * .8)
          ..lineTo(w * .4, h * .04)
          ..lineTo(w * .47, h * .96)
          ..lineTo(w * .53, h * .15)
          ..lineTo(w * .6, h * .85)
          ..lineTo(w * .67, h * .35)
          ..lineTo(w * .74, h * .65)
          ..lineTo(w * .8, h * .45)
          ..lineTo(w * .87, h / 2)
          ..lineTo(w, h / 2),
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

InputDecoration _ewDec(BuildContext ctx, String hint,
    {Widget? suffix, String? error}) {
  final c = col(ctx);
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.textSub, fontSize: 14),
    errorText: error,
    filled: true,
    fillColor: c.input,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.primary, width: 1.8)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger)),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger, width: 1.8)),
  );
}

Widget ewBtn(BuildContext ctx, String label,
    {VoidCallback? onTap, bool loading = false}) {
  final c = col(ctx);
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: c.primary.withOpacity(0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: onTap != null && !loading ? 2 : 0,
        shadowColor: c.primary.withOpacity(0.35),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child:
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );
}

Widget ewOutBtn(BuildContext ctx, String label, {VoidCallback? onTap}) {
  final c = col(ctx);
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.border.withOpacity(0.6)),
        foregroundColor: c.textSub,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    ),
  );
}

Widget progressBar(BuildContext ctx, int step) {
  final c = col(ctx);
  return Row(children: [
    Expanded(
        child: Container(
            height: 4,
            decoration: BoxDecoration(
                color: c.primary, borderRadius: BorderRadius.circular(2)))),
    const SizedBox(width: 4),
    Expanded(
        child: Container(
            height: 4,
            decoration: BoxDecoration(
                color: step >= 2 ? c.primary : c.input,
                borderRadius: BorderRadius.circular(2)))),
  ]);
}

Widget flabel(BuildContext ctx, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(label,
        style: TextStyle(
            color: col(ctx).textSub,
            fontSize: 12,
            fontWeight: FontWeight.w500)));

void push(BuildContext ctx, Widget w) =>
    Navigator.push(ctx, MaterialPageRoute(builder: (_) => w));
void pushOff(BuildContext ctx, Widget w) => Navigator.pushAndRemoveUntil(
    ctx, MaterialPageRoute(builder: (_) => w), (_) => false);

// ═══════════════════════════════════════════════════════════════════════════
//  0. AUTH GATE — silently checks for a saved session before showing the
//  splash/login flow, so a user with a still-valid token isn't forced to log
//  in again every time the app is reopened from a full close.
// ═══════════════════════════════════════════════════════════════════════════
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate>
    with SingleTickerProviderStateMixin {
  // Gentle pulse of the logo while the saved session is being checked; it
  // follows the native launch screen (same dark bg, same logo, same size).
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // Someone who isn't logged in has nothing to wait for, so without this the
  // pulsing logo would only flash for a few milliseconds. Keep it on screen
  // for a short minimum (counted from when the check started) before showing
  // the welcome/terms screen. Logged-in users never wait on this: they go
  // straight to the app as soon as their session check finishes.
  Future<void> _toSplash(DateTime started) async {
    final rest =
        const Duration(milliseconds: 1200) - DateTime.now().difference(started);
    if (rest > Duration.zero) await Future.delayed(rest);
    if (mounted) pushOff(context, const SplashScreen());
  }

  Future<void> _check() async {
    final started = DateTime.now();
    final token = await TokenStorage.read();
    if (token == null || token.isEmpty) {
      await _toSplash(started);
      return;
    }
    try {
      final res = await ApiClient.get('/profile');
      applyUserFromJson(res['user'] as Map<String, dynamic>);
      unawaited(PushNotifications.registerDeviceToken());
      if (mounted) pushOff(context, const MainScreen());
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // The server explicitly rejected the saved token (revoked, expired,
        // account deleted, etc.) — clear it and fall back to the normal login
        // flow instead of getting stuck.
        await TokenStorage.clear();
        await UserCache.clear();
        await _toSplash(started);
        return;
      }

      // Anything else (no connectivity, timeout, server down) says nothing
      // about whether the token is valid, so keep it and open the app with
      // the last saved account details instead of forcing a re-login —
      // being offline is exactly when someone in a disaster still needs it.
      final cached = await UserCache.read();
      if (cached != null) {
        applyUserFromJson(cached);
        if (mounted) pushOff(context, const MainScreen());
      } else {
        await _toSplash(started);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EWColors.dark.bg,
      body: Center(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.06).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Image.asset('assets/images/splash_logo.png',
              width: 88, height: 88),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  1. SPLASH
// ═══════════════════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> {
  bool _agreed = false;
  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
        body: SafeArea(
            child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(children: [
        const Spacer(),
        buildLogo(context),
        const SizedBox(height: 22),
        Text(t('app_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSub, fontSize: 13, height: 1.8)),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _agreed = !_agreed),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _agreed ? c.primary.withOpacity(0.55) : c.border,
                  width: _agreed ? 1.5 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _agreed ? c.primary : Colors.transparent,
                  border: Border.all(
                      color: _agreed ? c.primary : c.textSub, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _agreed
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(t('agree_terms'),
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(t('must_agree'),
                        style: TextStyle(color: c.textSub, fontSize: 12)),
                  ])),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => push(context, const TermsScreen()),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined, color: c.primary, size: 16),
              const SizedBox(width: 6),
              Text(t('view_agreement_btn'),
                  style: TextStyle(
                      color: c.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: c.primary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ewBtn(context, t('start_now'),
            onTap:
                _agreed ? () => pushOff(context, const LoginScreen()) : null),
        const SizedBox(height: 8),
      ]),
    )));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. LOGIN  — FIX: addListener on controller for reliable button activation
// ═══════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _ctrl = TextEditingController();
  bool _googleLoading = false;
  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_upd);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_upd);
    _ctrl.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  bool get _ok => _ctrl.text.trim().isNotEmpty;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    final result = await GoogleAuth.signIn();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (result == null) return; // user closed the Google picker
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? t('google_error'))));
      return;
    }
    unawaited(PushNotifications.registerDeviceToken());
    if (user.cityId.isEmpty) {
      pushOff(context, const CompleteGoogleProfileScreen());
    } else {
      user.isNew = false;
      pushOff(context, const WelcomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
        body: SafeArea(
            child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(children: [
        buildLogo(context, size: 70),
        const SizedBox(height: 28),
        Text(t('login_title'),
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
        const SizedBox(height: 6),
        Text(t('login_sub'), style: TextStyle(color: c.textSub, fontSize: 13)),
        const SizedBox(height: 28),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: c.text, fontSize: 15),
          textDirection: TextDirection.ltr,
          decoration: _ewDec(context, t('gmail_hint')),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: appLang.value == 'ar'
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              final email = _ctrl.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('need_email_first'))));
                return;
              }
              push(context, ForgotPasswordVerifyScreen(email: email));
            },
            child: Text(t('forgot_pass'),
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13)),
          ),
        ),
        const SizedBox(height: 10),
        ewBtn(context, t('login_btn'),
            onTap: _ok
                ? () {
                    user.email = _ctrl.text.trim();
                    push(context, PasswordScreen(email: _ctrl.text.trim()));
                  }
                : null),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => push(context, const RegisterStep1Screen()),
          child: Text(t('create_link'),
              style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF38BDF8))),
        ),
        const SizedBox(height: 30),
        Row(children: [
          Expanded(child: Divider(color: c.border)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(t('or'),
                  style: TextStyle(color: c.textSub, fontSize: 13))),
          Expanded(child: Divider(color: c.border)),
        ]),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _googleLoading ? null : _handleGoogleSignIn,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: c.border),
            foregroundColor: c.text,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            minimumSize: const Size(double.infinity, 52),
          ),
          icon: _googleLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: c.textSub))
              : const Text('G',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4285F4))),
          label: Text(t('google_btn'),
              style: TextStyle(color: c.text, fontSize: 14)),
        ),
      ]),
    )));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. PASSWORD
// ═══════════════════════════════════════════════════════════════════════════
class PasswordScreen extends StatefulWidget {
  final String email;
  const PasswordScreen({super.key, required this.email});
  @override
  State<PasswordScreen> createState() => _PwdState();
}

class _PwdState extends State<PasswordScreen> {
  final _ctrl = TextEditingController();
  bool _show = false, _err = false, _loading = false;
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('login_title'))),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
              child: Column(children: [
            const SizedBox(height: 12),
            Center(
                child: Column(children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary.withOpacity(0.15),
                    border: Border.all(color: c.primary.withOpacity(0.4))),
                child: Icon(Icons.person_outline_rounded,
                    color: c.primary, size: 32),
              ),
              const SizedBox(height: 10),
              Text(t('welcome_back'),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: c.text)),
              const SizedBox(height: 4),
              Text(widget.email,
                  style: TextStyle(color: c.textSub, fontSize: 13)),
            ])),
            const SizedBox(height: 28),
            TextField(
              controller: _ctrl,
              obscureText: !_show,
              style: TextStyle(color: c.text, fontSize: 15),
              onChanged: (_) => setState(() => _err = false),
              decoration: _ewDec(context, t('pass_hint'),
                  error: _err ? t('wrong_pass') : null,
                  suffix: IconButton(
                      icon: Icon(
                          _show
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: c.textSub,
                          size: 20),
                      onPressed: () => setState(() => _show = !_show))),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: appLang.value == 'ar'
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: TextButton(
                  onPressed: () => push(context,
                      ForgotPasswordVerifyScreen(email: widget.email)),
                  child: Text(t('forgot_pass'),
                      style: const TextStyle(
                          color: Color(0xFF38BDF8), fontSize: 13))),
            ),
            const SizedBox(height: 16),
            ewBtn(context, t('login_action'),
                loading: _loading,
                onTap: () async {
                  setState(() {
                    _err = false;
                    _loading = true;
                  });
                  try {
                    final res = await ApiClient.post(
                        '/login',
                        {'email': widget.email, 'password': _ctrl.text},
                        auth: false);
                    await TokenStorage.save(res['token'] as String);
                    applyUserFromJson(res['user'] as Map<String, dynamic>);
                    user.isNew = false;
                    unawaited(PushNotifications.registerDeviceToken());
                    if (mounted) pushOff(context, const WelcomeScreen());
                  } on ApiException catch (e) {
                    if (e.statusCode == 403) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message)));
                        push(context, VerifyScreen(email: widget.email));
                      }
                    } else {
                      if (mounted) setState(() => _err = true);
                    }
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                }),
          ]))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  3B. FORGOT PASSWORD — EMAIL VERIFICATION CODE
// ═══════════════════════════════════════════════════════════════════════════
class ForgotPasswordVerifyScreen extends StatefulWidget {
  final String email;
  const ForgotPasswordVerifyScreen({super.key, required this.email});
  @override
  State<ForgotPasswordVerifyScreen> createState() => _FPVerState();
}

class _FPVerState extends State<ForgotPasswordVerifyScreen> {
  final _ctrls = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false, _resending = false;
  bool get _done => _ctrls.every((c) => c.text.isNotEmpty);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  Future<void> _sendCode() async {
    try {
      await ApiClient.post('/forgot-password', {'email': widget.email}, auth: false);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('reset_verify_title'))),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
              builder: (context, cons) => SingleChildScrollView(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: cons.maxHeight),
                      child: IntrinsicHeight(
                          child: Column(children: [
            const SizedBox(height: 20),
            Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent.withOpacity(0.15),
                    border: Border.all(
                        color: c.accent.withOpacity(0.35), width: 1.5)),
                child: Icon(Icons.email_outlined, color: c.accent, size: 36)),
            const SizedBox(height: 16),
            Text(t('reset_verify_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 8),
            Text(t('reset_code_sent'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSub, fontSize: 14, height: 1.5)),
            const SizedBox(height: 4),
            Text(widget.email,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    color: c.text, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 32),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                    6,
                    (i) => SizedBox(
                        width: 46,
                        height: 54,
                        child: TextField(
                          controller: _ctrls[i],
                          focusNode: _nodes[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: TextStyle(
                              color: c.text,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: c.input,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: c.primary, width: 2)),
                          ),
                          onChanged: (v) {
                            setState(() {});
                            if (v.isNotEmpty && i < 5)
                              _nodes[i + 1].requestFocus();
                            if (v.isEmpty && i > 0)
                              _nodes[i - 1].requestFocus();
                          },
                        )))),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t('no_code'),
                  style: TextStyle(color: c.textSub, fontSize: 13)),
              GestureDetector(
                  onTap: _resending
                      ? null
                      : () async {
                          setState(() => _resending = true);
                          await _sendCode();
                          if (mounted) setState(() => _resending = false);
                        },
                  child: Text(t('resend'),
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
            ]),
            const Spacer(),
            ewBtn(context, t('confirm_btn'),
                loading: _verifying,
                onTap: _done
                    ? () async {
                        setState(() => _verifying = true);
                        final code = _ctrls.map((c) => c.text).join();
                        try {
                          await ApiClient.post(
                              '/verify-reset-otp',
                              {'email': widget.email, 'otp_code': code},
                              auth: false);
                          if (mounted) {
                            push(
                                context,
                                ResetPasswordScreen(
                                    email: widget.email, otpCode: code));
                          }
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _verifying = false);
                        }
                      }
                    : null),
            const SizedBox(height: 8),
          ])))))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  3C. FORGOT PASSWORD — SET NEW PASSWORD
// ═══════════════════════════════════════════════════════════════════════════
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otpCode;
  const ResetPasswordScreen({super.key, required this.email, required this.otpCode});
  @override
  State<ResetPasswordScreen> createState() => _ResetPassState();
}

class _ResetPassState extends State<ResetPasswordScreen> {
  final _pass = TextEditingController(), _conf = TextEditingController();
  bool _showPass = false, _showConf = false, _loading = false;
  @override
  void initState() {
    super.initState();
    _pass.addListener(_upd);
    _conf.addListener(_upd);
  }

  @override
  void dispose() {
    _pass.removeListener(_upd);
    _conf.removeListener(_upd);
    _pass.dispose();
    _conf.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  bool get _ok => isValidPassword(_pass.text) && _pass.text == _conf.text;

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('reset_pass_title'))),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            const SizedBox(height: 4),
            Text(t('reset_pass_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 6),
            Text(t('reset_pass_desc'),
                style: TextStyle(color: c.textSub, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
                controller: _pass,
                obscureText: !_showPass,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('new_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass)))),
            if (_pass.text.isNotEmpty && !isValidPassword(_pass.text))
              Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                  child: Text(t('pass_short'),
                      style: TextStyle(color: c.danger, fontSize: 12))),
            const SizedBox(height: 12),
            TextField(
                controller: _conf,
                obscureText: !_showConf,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('conf_new_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showConf
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showConf = !_showConf)))),
            const SizedBox(height: 28),
            ewBtn(context, t('reset_pass_btn'),
                loading: _loading,
                onTap: _ok
                    ? () async {
                        setState(() => _loading = true);
                        try {
                          await ApiClient.post(
                              '/reset-password',
                              {
                                'email': widget.email,
                                'otp_code': widget.otpCode,
                                'password': _pass.text,
                                'password_confirmation': _conf.text,
                              },
                              auth: false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(t('reset_pass_success'))));
                            pushOff(context, const LoginScreen());
                          }
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      }
                    : null),
          ]))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. REGISTER STEP 1
// ═══════════════════════════════════════════════════════════════════════════
class RegisterStep1Screen extends StatefulWidget {
  const RegisterStep1Screen({super.key});
  @override
  State<RegisterStep1Screen> createState() => _R1State();
}

class _R1State extends State<RegisterStep1Screen> {
  final _fn = TextEditingController(),
      _ln = TextEditingController(),
      _city = TextEditingController(),
      _street = TextEditingController(),
      _build = TextEditingController();
  SyrianCity? _sel;
  List<SyrianCity> _sugg = [];
  @override
  void initState() {
    super.initState();
    _fn.addListener(_upd);
    _ln.addListener(_upd);
    if (cities.isEmpty) {
      loadCities().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _fn.removeListener(_upd);
    _ln.removeListener(_upd);
    _fn.dispose();
    _ln.dispose();
    _city.dispose();
    _street.dispose();
    _build.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  bool get _ok => _fn.text.isNotEmpty && _ln.text.isNotEmpty && _sel != null;

  void _onCity(String v) => setState(() {
        _sel = null;
        _sugg = v.isEmpty
            ? []
            : cities.where((c) => c.name.contains(v)).take(6).toList();
      });

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(leading: BackButton(color: c.text)),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('reg_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 4),
            Text(t('step1'), style: TextStyle(color: c.textSub, fontSize: 13)),
            const SizedBox(height: 10),
            progressBar(context, 1),
            const SizedBox(height: 22),
            TextField(
                controller: _fn,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('fn_hint'))),
            const SizedBox(height: 12),
            TextField(
                controller: _ln,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('ln_hint'))),
            const SizedBox(height: 12),
            TextField(
                controller: _city,
                onChanged: _onCity,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('city_hint'),
                    suffix: _sel != null
                        ? Icon(Icons.check_circle_rounded,
                            color: c.success, size: 22)
                        : null)),
            if (_sugg.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border)),
                child: Column(
                    children: _sugg
                        .map((city) => InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                _city.text = city.name;
                                _sel = city;
                                _sugg = [];
                              }),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(city.name,
                                            style: TextStyle(
                                                color: c.text, fontSize: 14)),
                                        Text('ID: ${city.id}',
                                            style: TextStyle(
                                                color: c.textSub,
                                                fontSize: 11,
                                                fontFamily: 'monospace')),
                                      ])),
                            ))
                        .toList()),
              ),
            const SizedBox(height: 12),
            TextField(
                controller: _street,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('street_hint'))),
            const SizedBox(height: 12),
            TextField(
                controller: _build,
                style: TextStyle(color: c.text, fontSize: 15),
                keyboardType: TextInputType.number,
                decoration: _ewDec(context, t('building_hint'))),
            const SizedBox(height: 28),
            ewBtn(context, t('next_btn'),
                onTap: _ok
                    ? () {
                        user
                          ..firstName = _fn.text
                          ..lastName = _ln.text
                          ..cityId = _sel!.id
                          ..cityName = _sel!.name
                          ..streetName = _street.text
                          ..buildingNumber = _build.text;
                        push(context, const RegisterStep2Screen());
                      }
                    : null),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  5. REGISTER STEP 2
// ═══════════════════════════════════════════════════════════════════════════
class RegisterStep2Screen extends StatefulWidget {
  const RegisterStep2Screen({super.key});
  @override
  State<RegisterStep2Screen> createState() => _R2State();
}

class _R2State extends State<RegisterStep2Screen> {
  final _email = TextEditingController(),
      _pass = TextEditingController(),
      _conf = TextEditingController();
  bool _showPass = false, _loading = false;
  @override
  void initState() {
    super.initState();
    _email.addListener(_upd);
    _pass.addListener(_upd);
    _conf.addListener(_upd);
  }

  @override
  void dispose() {
    _email.removeListener(_upd);
    _pass.removeListener(_upd);
    _conf.removeListener(_upd);
    _email.dispose();
    _pass.dispose();
    _conf.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  bool get _emailOk => _email.text.contains('@') && _email.text.contains('.');
  bool get _passOk => _pass.text == _conf.text && isValidPassword(_pass.text);
  bool get _ok => _emailOk && _passOk;

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(leading: BackButton(color: c.text)),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('reg_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 4),
            Text(t('step2'), style: TextStyle(color: c.textSub, fontSize: 13)),
            const SizedBox(height: 10),
            progressBar(context, 2),
            const SizedBox(height: 22),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: c.text, fontSize: 15),
                onChanged: (_) => setState(() {}),
                decoration: _ewDec(context, t('email_hint'),
                    suffix: _emailOk
                        ? Icon(Icons.check_circle_rounded,
                            color: c.success, size: 22)
                        : null)),
            const SizedBox(height: 12),
            TextField(
                controller: _pass,
                obscureText: !_showPass,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('newpass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass)))),
            if (_pass.text.isNotEmpty && !isValidPassword(_pass.text))
              Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                  child: Text(t('pass_short'),
                      style: TextStyle(color: c.danger, fontSize: 12))),
            const SizedBox(height: 12),
            TextField(
                controller: _conf,
                obscureText: true,
                style: TextStyle(color: c.text, fontSize: 15),
                onChanged: (_) => setState(() {}),
                decoration: _ewDec(context, t('conf_hint'),
                    suffix: _conf.text.isNotEmpty && _passOk
                        ? Icon(Icons.check_circle_rounded,
                            color: c.success, size: 22)
                        : null)),
            const SizedBox(height: 28),
            ewBtn(context, t('create_btn'),
                loading: _loading,
                onTap: _ok
                    ? () async {
                        setState(() => _loading = true);
                        try {
                          await ApiClient.post(
                              '/register',
                              {
                                'first_name': user.firstName,
                                'last_name': user.lastName,
                                'city_code': user.cityId,
                                'street_name': user.streetName,
                                'building_number': user.buildingNumber,
                                'email': _email.text.trim(),
                                'password': _pass.text,
                                'password_confirmation': _conf.text,
                              },
                              auth: false);
                          user.email = _email.text.trim();
                          user.isNew = true;
                          if (mounted) {
                            push(context, VerifyScreen(email: user.email));
                          }
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      }
                    : null),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  6. VERIFY
// ═══════════════════════════════════════════════════════════════════════════
class VerifyScreen extends StatefulWidget {
  final String email;
  const VerifyScreen({super.key, required this.email});
  @override
  State<VerifyScreen> createState() => _VerState();
}

class _VerState extends State<VerifyScreen> {
  final _ctrls = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  bool _loading = false, _resending = false;
  bool get _done => _ctrls.every((c) => c.text.isNotEmpty);
  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(leading: BackButton(color: c.text)),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
              builder: (context, cons) => SingleChildScrollView(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: cons.maxHeight),
                      child: IntrinsicHeight(
                          child: Column(children: [
            const SizedBox(height: 20),
            Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent.withOpacity(0.15),
                    border: Border.all(
                        color: c.accent.withOpacity(0.35), width: 1.5)),
                child: Icon(Icons.email_outlined, color: c.accent, size: 36)),
            const SizedBox(height: 16),
            Text(t('verify_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 8),
            Text(t('code_sent'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSub, fontSize: 14, height: 1.5)),
            const SizedBox(height: 32),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                    6,
                    (i) => SizedBox(
                        width: 46,
                        height: 54,
                        child: TextField(
                          controller: _ctrls[i],
                          focusNode: _nodes[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: TextStyle(
                              color: c.text,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: c.input,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.border)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: c.primary, width: 2)),
                          ),
                          onChanged: (v) {
                            setState(() {});
                            if (v.isNotEmpty && i < 5)
                              _nodes[i + 1].requestFocus();
                            if (v.isEmpty && i > 0)
                              _nodes[i - 1].requestFocus();
                          },
                        )))),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t('no_code'),
                  style: TextStyle(color: c.textSub, fontSize: 13)),
              GestureDetector(
                  onTap: _resending
                      ? null
                      : () async {
                          setState(() => _resending = true);
                          try {
                            final res = await ApiClient.post(
                                '/resend-otp', {'email': widget.email},
                                auth: false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          res['message']?.toString() ??
                                              t('resend'))));
                            }
                          } on ApiException catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)));
                            }
                          } finally {
                            if (mounted) setState(() => _resending = false);
                          }
                        },
                  child: Text(t('resend'),
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
            ]),
            const Spacer(),
            ewBtn(context, t('confirm_btn'),
                loading: _loading,
                onTap: _done
                    ? () async {
                        setState(() => _loading = true);
                        try {
                          final res = await ApiClient.post(
                              '/verify-otp',
                              {
                                'email': widget.email,
                                'otp_code': _ctrls.map((c) => c.text).join(),
                              },
                              auth: false);
                          await TokenStorage.save(res['token'] as String);
                          applyUserFromJson(res['user'] as Map<String, dynamic>);
                          unawaited(PushNotifications.registerDeviceToken());
                          if (mounted) pushOff(context, const SuccessScreen());
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      }
                    : null),
            const SizedBox(height: 8),
          ])))))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  7. SUCCESS
// ═══════════════════════════════════════════════════════════════════════════
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});
  @override
  State<SuccessScreen> createState() => _SucState();
}

class _SucState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) pushOff(context, const MainScreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.success.withOpacity(0.15),
              border: Border.all(color: c.success.withOpacity(0.4), width: 2)),
          child: Icon(Icons.check_circle_outline_rounded,
              color: c.success, size: 54)),
      const SizedBox(height: 22),
      Text(t('acc_done'),
          style: TextStyle(
              fontSize: 21, fontWeight: FontWeight.bold, color: c.text)),
      const SizedBox(height: 8),
      Text(t('redirecting'), style: TextStyle(color: c.textSub, fontSize: 13)),
      const SizedBox(height: 24),
      CircularProgressIndicator(color: c.primary, strokeWidth: 2.5),
    ])));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  8. WELCOME
// ═══════════════════════════════════════════════════════════════════════════
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelState();
}

class _WelState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) pushOff(context, const MainScreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      buildLogo(context),
      const SizedBox(height: 22),
      Text(t('welcome_msg'),
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: c.text)),
      const SizedBox(height: 6),
      Text(t('welcome_b2'), style: TextStyle(color: c.textSub, fontSize: 15)),
    ])));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  8B. COMPLETE PROFILE (first-time Google sign-in only)
// ═══════════════════════════════════════════════════════════════════════════
class CompleteGoogleProfileScreen extends StatefulWidget {
  const CompleteGoogleProfileScreen({super.key});
  @override
  State<CompleteGoogleProfileScreen> createState() => _CompleteGoogleProfileState();
}

class _CompleteGoogleProfileState extends State<CompleteGoogleProfileScreen> {
  final _city = TextEditingController();
  final _street = TextEditingController();
  final _build = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  SyrianCity? _sel;
  List<SyrianCity> _sugg = [];

  @override
  void initState() {
    super.initState();
    if (cities.isEmpty) {
      loadCities().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _city.dispose();
    _street.dispose();
    _build.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _onCity(String v) => setState(() {
        _sel = null;
        _sugg = v.isEmpty
            ? []
            : cities.where((c) => c.name.contains(v)).take(6).toList();
      });

  bool get _ok =>
      _sel != null &&
      _street.text.isNotEmpty &&
      _build.text.isNotEmpty &&
      (_pass.text.isEmpty || isValidPassword(_pass.text));

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.post('/profile', {
        'city_code': _sel!.id,
        'street_name': _street.text,
        'building_number': _build.text,
      });
      applyUserFromJson(res['user'] as Map<String, dynamic>);

      if (_pass.text.isNotEmpty) {
        await ApiClient.post('/profile/change-password', {
          'password': _pass.text,
          'password_confirmation': _pass.text,
        });
      }

      if (mounted) pushOff(context, const WelcomeScreen());
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    final passTooShort = _pass.text.isNotEmpty && !isValidPassword(_pass.text);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('complete_profile_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 4),
            Text(t('complete_profile_sub'),
                style: TextStyle(color: c.textSub, fontSize: 13)),
            const SizedBox(height: 22),
            TextField(
                controller: _city,
                onChanged: _onCity,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('city_hint'),
                    suffix: _sel != null
                        ? Icon(Icons.check_circle_rounded,
                            color: c.success, size: 22)
                        : null)),
            if (_sugg.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border)),
                child: Column(
                    children: _sugg
                        .map((city) => InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                _city.text = city.name;
                                _sel = city;
                                _sugg = [];
                              }),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(city.name,
                                            style: TextStyle(
                                                color: c.text, fontSize: 14)),
                                        Text('ID: ${city.id}',
                                            style: TextStyle(
                                                color: c.textSub,
                                                fontSize: 11,
                                                fontFamily: 'monospace')),
                                      ])),
                            ))
                        .toList()),
              ),
            const SizedBox(height: 12),
            TextField(
                controller: _street,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('street_hint'))),
            const SizedBox(height: 12),
            TextField(
                controller: _build,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.text, fontSize: 15),
                keyboardType: TextInputType.number,
                decoration: _ewDec(context, t('building_hint'))),
            const SizedBox(height: 12),
            TextField(
                controller: _pass,
                obscureText: !_showPass,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('optional_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass)))),
            Padding(
                padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                child: Text(
                    passTooShort ? t('pass_short') : t('optional_pass_note'),
                    style: TextStyle(
                        color: passTooShort ? c.danger : c.textSub,
                        fontSize: 12))),
            const SizedBox(height: 24),
            ewBtn(context, t('continue_btn'),
                loading: _loading, onTap: _ok ? _submit : null),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  9. MAIN
// ═══════════════════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainState();
}

class _MainState extends State<MainScreen> {
  Timer? _timer;
  String _time = '', _date = '';
  bool _loadingWeather = true;
  String? _weatherError;
  List<Map<String, dynamic>> _weather = [];
  bool _weatherFromCache = false;
  bool _loadingNotifs = true;
  String? _notifsError;
  List<Map<String, dynamic>> _notifs = [];
  bool _notifsFromCache = false;
  bool _loadingSummary = true;
  Map<String, int> _stats = {
    'today_earthquakes': 0,
    'weather_warnings': 0,
    'floods': 0,
  };
  Map<String, dynamic>? _activeWarning;
  Map<String, dynamic>? _latestEarthquake;
  bool _summaryFromCache = false;
  void _rb() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    appTheme.addListener(_rb);
    appLang.addListener(_rb);
    homeRefreshSignal.addListener(_onHomeRefreshSignal);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadWeather();
    _loadNotifs();
    _loadSummary();
  }

  @override
  void dispose() {
    _timer?.cancel();
    appTheme.removeListener(_rb);
    appLang.removeListener(_rb);
    homeRefreshSignal.removeListener(_onHomeRefreshSignal);
    super.dispose();
  }

  // A push arrived while the app was open (see _handleForegroundAlert) —
  // refresh the notification list/badge and the banner/stats so they don't
  // sit stale until the next full screen load.
  void _onHomeRefreshSignal() {
    _loadNotifs();
    _loadSummary();
  }

  Future<void> _loadWeather() async {
    setState(() {
      _loadingWeather = true;
      _weatherError = null;
    });
    try {
      final res = await ApiClient.get('/weather', auth: false);
      final list = (res['weather'] as List).cast<Map<String, dynamic>>();
      list.sort((a, b) {
        final codeA = (a['city'] as Map<String, dynamic>?)?['code'] as String? ?? '';
        final codeB = (b['city'] as Map<String, dynamic>?)?['code'] as String? ?? '';
        return codeA.compareTo(codeB);
      });
      // Show the user's own city first, ahead of the alphabetical order.
      if (user.cityId.isNotEmpty) {
        final idx = list.indexWhere(
            (w) => (w['city'] as Map<String, dynamic>?)?['code'] == user.cityId);
        if (idx > 0) list.insert(0, list.removeAt(idx));
      }
      unawaited(_cacheWeather(list));
      if (mounted) setState(() {
        _weather = list;
        _weatherFromCache = false;
      });
    } on ApiException catch (e) {
      // No signal — fall back to the last known weather reading instead of
      // an empty/error strip.
      final cached = await _readCachedWeather();
      if (mounted) {
        if (cached != null) {
          setState(() {
            _weather = cached;
            _weatherFromCache = true;
            _weatherError = null;
          });
        } else {
          setState(() => _weatherError = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
    }
  }

  String _weatherCityName(Map<String, dynamic> w) {
    final name = (w['city'] as Map<String, dynamic>?)?['name'];
    if (name is Map) {
      return (appLang.value == 'ar' ? name['ar'] : name['en'])?.toString() ??
          '';
    }
    return '';
  }

  Future<void> _loadNotifs() async {
    setState(() {
      _loadingNotifs = true;
      _notifsError = null;
    });
    try {
      final res = await ApiClient.get('/my-alerts');
      final list = (res['notifications'] as List).cast<Map<String, dynamic>>();
      unawaited(_cacheNotifications(list));
      if (mounted) setState(() {
        _notifs = list;
        _notifsFromCache = false;
      });
    } on ApiException catch (e) {
      // No signal — fall back to the last notifications we actually
      // managed to save, instead of an empty/error feed.
      final cached = await _readCachedNotifications();
      if (mounted) {
        if (cached != null) {
          setState(() {
            _notifs = cached;
            _notifsFromCache = true;
            _notifsError = null;
          });
        } else {
          setState(() => _notifsError = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _loadingNotifs = false);
    }
  }

  Future<void> _loadSummary() async {
    setState(() => _loadingSummary = true);
    try {
      final res = await ApiClient.get('/home-summary');
      final stats = res['stats'] as Map<String, dynamic>;
      final warning = res['active_warning'] as Map<String, dynamic>?;
      final latestEq = res['latest_earthquake'] as Map<String, dynamic>?;
      unawaited(_cacheSummary(res));
      if (mounted) setState(() {
        _stats = {
          'today_earthquakes': stats['today_earthquakes'] as int? ?? 0,
          'weather_warnings': stats['weather_warnings'] as int? ?? 0,
          'floods': stats['floods'] as int? ?? 0,
        };
        _activeWarning = warning;
        _latestEarthquake = latestEq;
        _summaryFromCache = false;
      });
    } on ApiException catch (_) {
      // No signal — fall back to the last known summary instead of
      // resetting to zeros/no-warning, which would look like real good news.
      final cached = await _readCachedSummary();
      if (mounted && cached != null) {
        final stats = cached['stats'] as Map<String, dynamic>;
        setState(() {
          _stats = {
            'today_earthquakes': stats['today_earthquakes'] as int? ?? 0,
            'weather_warnings': stats['weather_warnings'] as int? ?? 0,
            'floods': stats['floods'] as int? ?? 0,
          };
          _activeWarning = cached['active_warning'] as Map<String, dynamic>?;
          _latestEarthquake = cached['latest_earthquake'] as Map<String, dynamic>?;
          _summaryFromCache = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  String? _activeWarningMessage() {
    final msg = _activeWarning?['message'];
    if (msg is Map) {
      return (appLang.value == 'ar' ? msg['ar'] : msg['en'])?.toString();
    }
    return null;
  }

  String _notifType(Map<String, dynamic> n) =>
      (n['alert']?['disaster_type']?['key'] as String?) ?? '';

  String _notifTitle(Map<String, dynamic> n) {
    final name = n['alert']?['disaster_type']?['name'];
    if (name is Map) {
      return (appLang.value == 'ar' ? name['ar'] : name['en'])?.toString() ??
          '';
    }
    return '';
  }

  String _notifSubtitle(Map<String, dynamic> n) {
    final cityName = n['alert']?['city']?['name'];
    final city = cityName is Map
        ? (appLang.value == 'ar' ? cityName['ar'] : cityName['en'])
                ?.toString() ??
            ''
        : '';
    final time = relativeTime(n['received_at'] as String?);
    return city.isNotEmpty ? '$city · $time' : time;
  }

  double _lastEqMagnitude() =>
      (_latestEarthquake?['magnitude'] as num?)?.toDouble() ?? 0;

  int _lastEqDepth() => ((_latestEarthquake?['depth_km'] as num?) ?? 0).round();

  String _lastEqLocation() {
    final city = _latestEarthquake?['city'] as Map<String, dynamic>?;
    final name = city?['name'];
    if (name is Map) {
      final picked = appLang.value == 'ar' ? name['ar'] : name['en'];
      if (picked != null && picked.toString().isNotEmpty) {
        return picked.toString();
      }
    }
    return (_latestEarthquake?['location_name'] as String?) ?? '';
  }

  List<Widget> _buildNotifPreview(EWColors c) {
    if (_loadingNotifs) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: c.primary)),
        ),
      ];
    }
    if (_notifsError != null) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border)),
          child: Column(children: [
            Text(t('notifs_load_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.danger, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadNotifs,
              child: Text(t('retry_btn'),
                  style:
                      TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ];
    }
    if (_notifs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(t('no_notifs'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSub, fontSize: 13)),
        ),
      ];
    }
    return [
      if (_cachedDataBanner(c, _notifsFromCache) != null)
        _cachedDataBanner(c, _notifsFromCache)!,
      ..._notifs
          .map((n) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border)),
              child: Row(children: [
                Container(
                    width: 4,
                    height: 44,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _notifType(n) == 'earthquake'
                            ? c.danger
                            : (_notifType(n) == 'severe_storm' ||
                                    _notifType(n) == 'coastal_storm')
                                ? c.accent
                                : Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_notifTitle(n),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(_notifSubtitle(n),
                          style: TextStyle(color: c.textSub, fontSize: 11)),
                    ])),
                Icon(
                    _notifType(n) == 'earthquake'
                        ? Icons.show_chart_rounded
                        : (_notifType(n) == 'severe_storm' ||
                                _notifType(n) == 'coastal_storm')
                            ? Icons.air_rounded
                            : Icons.water_drop_outlined,
                    color: _notifType(n) == 'earthquake'
                        ? c.danger
                        : (_notifType(n) == 'severe_storm' ||
                                _notifType(n) == 'coastal_storm')
                            ? c.accent
                            : Colors.blue,
                    size: 20),
              ]),
            ))),
    ];
  }

  Widget? _cachedDataBanner(EWColors c, bool fromCache) {
    if (!fromCache) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t('cached_data_note'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textSub, fontSize: 11)),
    );
  }

  void _tick() {
    final now = DateTime.now();
    const arM = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    const enM = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const arD = [
      'الأحد',
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت'
    ];
    const enD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final ar = appLang.value == 'ar';
    if (mounted)
      setState(() {
        _time = '${_p(now.hour)}:${_p(now.minute)}:${_p(now.second)}';
        _date = ar
            ? '${arD[now.weekday % 7]} ${now.day} ${arM[now.month - 1]} ${now.year}'
            : '${enD[now.weekday % 7]}, ${enM[now.month - 1]} ${now.day}, ${now.year}';
      });
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  // The home screen's "Weather Warnings" stat counts these 3 real types
  // combined into one number — this lets the filter match that same group
  // instead of just one of the three and silently dropping the other two.
  static const _weatherWarningTypes = [
    'severe_storm',
    'coastal_storm',
    'flash_flood'
  ];

  void _openNotifs({String initialType = 'all'}) {
    final c = col(context);
    String filterType = initialType;
    String filterOrder = 'newest';

    IconData typeIcon(String? tp) {
      if (tp == 'earthquake') return Icons.show_chart_rounded;
      if (tp == 'severe_storm') return Icons.air_rounded;
      if (tp == 'coastal_storm') return Icons.sailing_rounded;
      if (tp == 'flood') return Icons.water_drop_outlined;
      if (tp == 'flash_flood') return Icons.waves;
      if (tp == 'tsunami') return Icons.water;
      return Icons.notifications_outlined;
    }

    Color typeColor(String? tp) {
      if (tp == 'earthquake') return c.danger;
      if (tp == 'severe_storm') return c.accent;
      if (tp == 'coastal_storm') return Colors.orange;
      if (tp == 'flood') return Colors.blue;
      if (tp == 'flash_flood') return Colors.teal;
      if (tp == 'tsunami') return Colors.indigo;
      return c.text;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (shCtx) => StatefulBuilder(
        builder: (ctx, setSt) {
          List<Map<String, dynamic>> filtered = filterType == 'all'
              ? List.from(_notifs)
              : filterType == 'weather_all'
                  ? _notifs
                      .where((n) =>
                          _weatherWarningTypes.contains(_notifType(n)))
                      .toList()
                  : _notifs.where((n) => _notifType(n) == filterType).toList();
          if (filterOrder == 'oldest') filtered = filtered.reversed.toList();

          void openFilter() {
            String tmpType = filterType;
            String tmpOrder = filterOrder;
            showDialog(
              context: ctx,
              builder: (dCtx) => StatefulBuilder(
                builder: (_, setD) => Directionality(
                  textDirection: appLang.value == 'ar'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: AlertDialog(
                    backgroundColor: c.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    title: Row(children: [
                      Icon(Icons.filter_list_rounded,
                          color: c.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(t('filter_lbl'),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ]),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('filter_type'),
                              style: TextStyle(
                                  color: c.textSub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                                color: c.input,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.border)),
                            child: DropdownButton<String>(
                              value: tmpType,
                              isExpanded: true,
                              dropdownColor: c.surface,
                              underline: const SizedBox(),
                              style: TextStyle(color: c.text, fontSize: 14),
                              items: [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text(t('flt_all'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'weather_all',
                                    child: Text(t('flt_weather_all'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'earthquake',
                                    child: Text(t('flt_eq'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'severe_storm',
                                    child: Text(t('flt_severe_storm'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'coastal_storm',
                                    child: Text(t('flt_coastal_storm'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'flood',
                                    child: Text(t('flt_flood'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'flash_flood',
                                    child: Text(t('flt_torrent'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'tsunami',
                                    child: Text(t('flt_tsunami'),
                                        style: TextStyle(color: c.text))),
                              ],
                              onChanged: (v) {
                                if (v != null) setD(() => tmpType = v);
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(t('filter_sort'),
                              style: TextStyle(
                                  color: c.textSub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                                color: c.input,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.border)),
                            child: DropdownButton<String>(
                              value: tmpOrder,
                              isExpanded: true,
                              dropdownColor: c.surface,
                              underline: const SizedBox(),
                              style: TextStyle(color: c.text, fontSize: 14),
                              items: [
                                DropdownMenuItem(
                                    value: 'newest',
                                    child: Text(t('sort_newest'),
                                        style: TextStyle(color: c.text))),
                                DropdownMenuItem(
                                    value: 'oldest',
                                    child: Text(t('sort_oldest'),
                                        style: TextStyle(color: c.text))),
                              ],
                              onChanged: (v) {
                                if (v != null) setD(() => tmpOrder = v);
                              },
                            ),
                          ),
                        ]),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx),
                        child: Text(t('cancel_lbl'),
                            style: TextStyle(color: c.textSub)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: c.primary,
                            foregroundColor: Colors.white),
                        onPressed: () {
                          setSt(() {
                            filterType = tmpType;
                            filterOrder = tmpOrder;
                          });
                          Navigator.pop(dCtx);
                        },
                        child: Text(t('done_btn')),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Directionality(
            textDirection:
                appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.border, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('prev_notif'),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.text)),
                      IconButton(
                        onPressed: openFilter,
                        icon: Icon(
                          Icons.filter_list_rounded,
                          color:
                              (filterType != 'all' || filterOrder != 'newest')
                                  ? c.primary
                                  : c.textSub,
                          size: 22,
                        ),
                        tooltip: t('filter_lbl'),
                      ),
                    ]),
              ),
              Divider(color: c.border, height: 1),
              if (_loadingNotifs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: c.primary)),
                )
              else if (_notifsError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(children: [
                    Text(t('notifs_load_error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.danger, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await _loadNotifs();
                        setSt(() {});
                      },
                      child: Text(t('retry_btn'),
                          style: TextStyle(
                              color: c.primary, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(children: [
                    Icon(Icons.notifications_off_outlined,
                        color: c.textSub, size: 36),
                    const SizedBox(height: 8),
                    Text(t('no_notifs'),
                        style: TextStyle(color: c.textSub, fontSize: 13)),
                  ]),
                )
              else
                // Scrolls on its own once there are more alerts than fit on
                // screen, while the handle/title/filter above stay fixed.
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      if (_notifsFromCache)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          child: Text(t('cached_data_note'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textSub, fontSize: 11)),
                        ),
                      ...filtered.map((n) => ListTile(
                            leading: Icon(typeIcon(_notifType(n)),
                                color: typeColor(_notifType(n)), size: 22),
                            title: Text(_notifTitle(n),
                                style: TextStyle(
                                    color: c.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(_notifSubtitle(n),
                                style:
                                    TextStyle(color: c.textSub, fontSize: 11)),
                          )),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ]),
          );
        },
      ),
    );
  }

  void _openMenu() {
    final c = col(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (shCtx) => Directionality(
        textDirection:
            appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.border, borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(t('menu_lbl'),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: c.text)))),
          Divider(color: c.border, height: 1),
          _mi(shCtx, Icons.person_outline_rounded, t('my_acc'), c,
              () => push(context, const ProfileScreen())),
          _mi(shCtx, Icons.language_rounded, t('lang_menu'), c,
              () => push(context, const LanguageScreen())),
          _mi(shCtx, Icons.palette_outlined, t('themes_menu'), c,
              () => push(context, const ThemesScreen())),
          _mi(shCtx, Icons.phone_outlined, t('reports_menu'), c,
              () => push(context, const ReportsScreen())),
          _mi(shCtx, Icons.lock_outline_rounded, t('perms_menu'), c,
              () => push(context, const PermissionsScreen())),
          _mi(shCtx, Icons.health_and_safety_rounded, t('precautions_menu'), c,
              () => push(context, const PrecautionsScreen())),
          _mi(shCtx, Icons.vibration_rounded, t('dyfi_menu'), c,
              () => push(context, const DidYouFeelItScreen())),
          _mi(shCtx, Icons.history_rounded, t('eq_history_menu'), c,
              () => push(context, const EarthquakeHistoryScreen())),
          _mi(shCtx, Icons.menu_book_outlined, t('about_menu'), c,
              () => push(context, const AboutScreen())),
          Divider(color: c.border),
          _mi(shCtx, Icons.logout_rounded, t('logout_menu'), c,
              () => _logoutDialog(context, c),
              danger: true),
          SizedBox(height: MediaQuery.of(shCtx).padding.bottom + 12),
        ]),
      ),
    );
  }

  Widget _mi(BuildContext shCtx, IconData icon, String label, EWColors c,
          VoidCallback action,
          {bool danger = false}) =>
      ListTile(
        leading: Icon(icon, color: danger ? c.danger : c.primary, size: 22),
        title: Text(label,
            style: TextStyle(color: danger ? c.danger : c.text, fontSize: 15)),
        trailing: Icon(
            appLang.value == 'ar'
                ? Icons.arrow_back_ios_new_rounded
                : Icons.arrow_forward_ios_rounded,
            color: c.textSub,
            size: 14),
        onTap: () {
          Navigator.pop(shCtx);
          action();
        },
      );

  void _logoutDialog(BuildContext ctx, EWColors c) {
    showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
              backgroundColor: c.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(t('logout_menu'), style: TextStyle(color: c.text)),
              content: Text(t('logout_q'), style: TextStyle(color: c.textSub)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('cancel_lbl'),
                        style: TextStyle(color: c.textSub))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final logoutDone = performLogout();
                    showDialog(
                        context: ctx,
                        builder: (_) => AlertDialog(
                              backgroundColor: c.surface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 8),
                                    Icon(Icons.waving_hand_rounded,
                                        color: c.primary, size: 56),
                                    const SizedBox(height: 14),
                                    Text(t('farewell'),
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: c.text)),
                                    const SizedBox(height: 8),
                                  ]),
                            ));
                    Future.delayed(const Duration(seconds: 2), () async {
                      await logoutDone;
                      if (ctx.mounted) pushOff(ctx, const LoginScreen());
                    });
                  },
                  child: Text(t('yes_btn')),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // RIGHT = Richter (notifications)
        leading: InkWell(
          onTap: _openNotifs,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Stack(clipBehavior: Clip.none, children: [
              SizedBox(
                  width: 50,
                  height: 22,
                  child:
                      CustomPaint(painter: RichterPainter(c.primary, sw: 2.2))),
              if (_notifs.isNotEmpty)
                Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                            color: c.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 1.5)),
                        child: Center(
                            child: Text('${_notifs.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold))))),
            ]),
          ),
        ),
        title: Column(children: [
          Text('Early Warning',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: c.text,
                  letterSpacing: 1)),
          Text(_date,
              style: TextStyle(
                  fontSize: 10,
                  color: col(context).textSub,
                  fontWeight: FontWeight.w300)),
        ]),
        centerTitle: true,
        // LEFT = Hamburger menu
        actions: [
          IconButton(
              icon: Icon(Icons.menu_rounded, color: c.text, size: 26),
              onPressed: _openMenu)
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_time,
                    style: TextStyle(
                        color: c.primary,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w500)))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Alert — only shown while there's a real active warning; hidden
          // when there's none instead of always showing fixed placeholder
          // text.
          if (_loadingSummary || _activeWarning != null) ...[
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: c.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.danger.withOpacity(0.3))),
                child: Row(children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.danger.withOpacity(0.18)),
                      child: _loadingSummary
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.danger))
                          : Icon(Icons.warning_amber_rounded,
                              color: c.danger, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(t('act_warning'),
                            style: TextStyle(
                                color: c.danger,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                            _loadingSummary
                                ? ''
                                : (_activeWarningMessage() ?? ''),
                            style: TextStyle(
                                color: c.textSub, fontSize: 12, height: 1.4)),
                        if (_summaryFromCache && !_loadingSummary)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(t('cached_data_note'),
                                style: TextStyle(
                                    color: c.textSub, fontSize: 10)),
                          ),
                      ])),
                ])),
            const SizedBox(height: 16),
          ],
          // Stats
          Row(children: [
            _sc(context, t('today_eq'), '${_stats['today_earthquakes']}',
                Icons.show_chart_rounded, c.primary,
                onTap: () => push(context, const EarthquakeHistoryScreen())),
            const SizedBox(width: 8),
            _sc(context, t('weat_warn'), '${_stats['weather_warnings']}',
                Icons.air_rounded, c.accent,
                onTap: () => _openNotifs(initialType: 'weather_all')),
            const SizedBox(width: 8),
            _sc(context, t('floods'), '${_stats['floods']}',
                Icons.water_drop_outlined, Colors.blue,
                onTap: () => _openNotifs(initialType: 'flood')),
          ]),
          const SizedBox(height: 12),
          // Relief button
          InkWell(
            onTap: () => push(context, const ReliefScreen()),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  c.danger,
                  Color.lerp(c.danger, Colors.deepOrange, 0.5)!
                ]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: c.danger.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.emergency_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(t('relief_btn'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.75), size: 14),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // Danger Simulator button
          InkWell(
            onTap: () => push(context, const DangerSimulatorScreen()),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.primary.withOpacity(0.4)),
              ),
              child: Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: c.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.sensors_rounded,
                        color: c.primary, size: 22)),
                const SizedBox(width: 12),
                Text(t('sim_btn'),
                    style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: c.textSub, size: 14),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          // Weather cards — horizontal scroll
          Text(t('weather_sec'),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 10),
          SizedBox(
            height: 152,
            child: _loadingWeather
                ? Center(child: CircularProgressIndicator(color: c.primary))
                : _weatherError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t('weather_load_error'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.danger, fontSize: 12)),
                            TextButton(
                              onPressed: _loadWeather,
                              child: Text(t('retry_btn'),
                                  style: TextStyle(
                                      color: c.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )
                    : _weather.isEmpty
                        ? Center(
                            child: Text(t('no_weather'),
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: c.textSub, fontSize: 12)))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _weather.length,
                            itemBuilder: (_, i) {
                              final w = _weather[i];
                              final cond = weatherCond(w['weather_code']);
                              final isSunny = cond == 's';
                              final isRainy = cond == 'r';
                              final condIcon = isSunny
                                  ? Icons.wb_sunny_rounded
                                  : isRainy
                                      ? Icons.grain_rounded
                                      : Icons.cloud_rounded;
                              final condColor = isSunny
                                  ? const Color(0xFFFBBF24)
                                  : isRainy
                                      ? Colors.blueAccent
                                      : Colors.blueGrey;
                              final temp = (w['temperature_c'] as num?)?.round();
                              final hum = w['humidity_percent'];
                              final wind = (w['wind_speed_kmh'] as num?)?.round();
                              final wCity = w['city'] as Map<String, dynamic>?;
                              final wCityCode = wCity?['code'] as String? ?? '';
                              return InkWell(
                                onTap: wCityCode.isEmpty
                                    ? null
                                    : () => push(
                                        context,
                                        WeatherForecastScreen(
                                            cityCode: wCityCode,
                                            cityName: _weatherCityName(w))),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                width: 118,
                                margin: EdgeInsets.only(
                                    left: i == _weather.length - 1 ? 0 : 10),
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: c.border),
                                ),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_weatherCityName(w),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: c.text,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        Icon(condIcon, color: condColor, size: 20),
                                        const SizedBox(width: 6),
                                        Text('$temp°C',
                                            style: TextStyle(
                                                color: c.text,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace')),
                                      ]),
                                      const Spacer(),
                                      Row(children: [
                                        Icon(Icons.water_drop_rounded,
                                            color: Colors.blue, size: 12),
                                        const SizedBox(width: 4),
                                        Text('$hum%',
                                            style: TextStyle(
                                                color: c.textSub, fontSize: 11)),
                                      ]),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        Icon(Icons.air_rounded,
                                            color: c.accent, size: 12),
                                        const SizedBox(width: 4),
                                        Text('$wind km/h',
                                            style: TextStyle(
                                                color: c.textSub, fontSize: 11)),
                                      ]),
                                    ]),
                              ));
                            },
                          ),
          ),
          if (_weatherFromCache && !_loadingWeather && _weatherError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t('cached_data_note'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSub, fontSize: 11)),
            ),
          const SizedBox(height: 16),
          // Last Earthquake — only shown once a real earthquake has ever
          // been recorded; hidden entirely until then instead of showing
          // fixed placeholder data.
          if (_loadingSummary || _latestEarthquake != null) ...[
            InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => push(context, const EarthquakeHistoryScreen()),
                child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border)),
                child: _loadingSummary
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                            child:
                                CircularProgressIndicator(color: c.primary)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header ──
                          Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(t('last_eq'),
                                    style: TextStyle(
                                        color: c.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: c.danger.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                    child: Text(t('live_lbl'),
                                        style: TextStyle(
                                            color: c.danger,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600))),
                              ]),
                          const SizedBox(height: 14),
                          // ── 3 Info Blocks ──
                          IntrinsicHeight(
                              child: Row(children: [
                            // Magnitude
                            Expanded(
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                  Text(_lastEqMagnitude().toStringAsFixed(1),
                                      style: TextStyle(
                                          color: c.danger,
                                          fontSize: 38,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          height: 1)),
                                  const SizedBox(height: 4),
                                  Text(t('eq_mag'),
                                      style: TextStyle(
                                          color: c.textSub, fontSize: 11)),
                                ])),
                            VerticalDivider(color: c.border, width: 1),
                            // Depth
                            Expanded(
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                            Icons
                                                .vertical_align_bottom_rounded,
                                            color: c.accent,
                                            size: 18),
                                        const SizedBox(width: 4),
                                        Text(
                                            '${_lastEqDepth()} ${t('eq_km')}',
                                            style: TextStyle(
                                                color: c.text,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace')),
                                      ]),
                                  const SizedBox(height: 4),
                                  Text(t('eq_depth'),
                                      style: TextStyle(
                                          color: c.textSub, fontSize: 11)),
                                ])),
                            VerticalDivider(color: c.border, width: 1),
                            // Location
                            Expanded(
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                  Icon(Icons.location_on_rounded,
                                      color: c.primary, size: 22),
                                  const SizedBox(height: 2),
                                  Text(_lastEqLocation(),
                                      style: TextStyle(
                                          color: c.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(t('eq_loc'),
                                      style: TextStyle(
                                          color: c.textSub, fontSize: 11)),
                                ])),
                          ])),
                          const SizedBox(height: 14),
                          // ── Scale Bar ──
                          richterScale(c, _lastEqMagnitude()),
                          const SizedBox(height: 10),
                          // ── Footer ──
                          Row(children: [
                            Icon(Icons.access_time_rounded,
                                color: c.textSub, size: 12),
                            const SizedBox(width: 4),
                            Text(
                                relativeTime(_latestEarthquake?['occurred_at']
                                    as String?),
                                style: TextStyle(
                                    color: c.textSub, fontSize: 11)),
                            const Spacer(),
                            Text('EMSC',
                                style: TextStyle(
                                    color: c.textSub,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1)),
                          ]),
                        ],
                      ))),
            const SizedBox(height: 16),
          ],
          Text(t('recent'),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 10),
          ..._buildNotifPreview(c),
        ]),
      ),
    );
  }

  Widget _sc(BuildContext ctx, String label, String value, IconData icon,
      Color color, {VoidCallback? onTap}) {
    final c = col(ctx);
    return Expanded(
        child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22))),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(color: c.textSub, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    )));
  }

}

// ═══════════════════════════════════════════════════════════════════════════
//  10. RELIEF SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class ReliefScreen extends StatefulWidget {
  const ReliefScreen({super.key});
  @override
  State<ReliefScreen> createState() => _ReliefState();
}

class _ReliefState extends State<ReliefScreen> {
  bool _sent = false;
  bool _sending = false;
  bool _loadingTeams = true;
  String? _teamsError;
  List<Map<String, dynamic>> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loadingTeams = true;
      _teamsError = null;
    });
    try {
      final res = await ApiClient.get('/relief-teams');
      final list = (res['relief_teams'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _teams = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _teamsError = e.message);
    } finally {
      if (mounted) setState(() => _loadingTeams = false);
    }
  }

  String _teamCityName(Map<String, dynamic> team) {
    final name = (team['city'] as Map<String, dynamic>?)?['name'];
    if (name is Map) {
      return (appLang.value == 'ar' ? name['ar'] : name['en'])?.toString() ??
          '';
    }
    return '';
  }

  Color _teamStatusColor(EWColors c, String? status) {
    switch (status) {
      case 'active':
        return c.success;
      case 'en_route':
        return c.accent;
      default:
        return c.textSub;
    }
  }

  IconData _reliefTypeIcon(String? type) {
    switch (type) {
      case 'medical':
        return Icons.medical_services_rounded;
      case 'food_water':
        return Icons.restaurant_rounded;
      case 'shelter':
        return Icons.home_rounded;
      case 'search_rescue':
        return Icons.search_rounded;
      case 'logistics':
        return Icons.local_shipping_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  List<Widget> _buildTeamsList(EWColors c) {
    if (_loadingTeams) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(color: c.primary)),
        ),
      ];
    }
    if (_teamsError != null) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border)),
          child: Column(children: [
            Text(t('teams_load_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.danger, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadTeams,
              child: Text(t('retry_btn'),
                  style:
                      TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ];
    }
    if (_teams.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(t('no_teams'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSub, fontSize: 13)),
        ),
      ];
    }
    return _teams
        .map((team) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showTeamDetails(c, team),
              child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border)),
              child: Row(children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.emergency_share_rounded,
                        color: c.accent, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Icon(Icons.location_city_rounded,
                            color: c.textSub, size: 13),
                        const SizedBox(width: 4),
                        Text(_teamCityName(team),
                            style: TextStyle(
                                color: c.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.signpost_rounded,
                            color: c.textSub, size: 12),
                        const SizedBox(width: 4),
                        Text('${team['street']} · ${team['building_number']}',
                            style:
                                TextStyle(color: c.textSub, fontSize: 12)),
                      ]),
                    ])),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _teamStatusColor(c, team['status'] as String?)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(bilingual(team['status_label']),
                        style: TextStyle(
                            color: _teamStatusColor(
                                c, team['status'] as String?),
                            fontSize: 10,
                            fontWeight: FontWeight.w700))),
              ]),
            )))
        .toList();
  }

  void _showTeamDetails(EWColors c, Map<String, dynamic> team) {
    showDialog(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Icon(Icons.emergency_share_rounded, color: c.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_teamCityName(team),
                    style: TextStyle(
                        color: c.text, fontSize: 16, fontWeight: FontWeight.bold))),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.signpost_rounded, color: c.textSub, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('${team['street']} · ${team['building_number']}',
                          style: TextStyle(color: c.textSub, fontSize: 13))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: _teamStatusColor(c, team['status'] as String?)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(bilingual(team['status_label']),
                          style: TextStyle(
                              color: _teamStatusColor(
                                  c, team['status'] as String?),
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
                ]),
                if (team['relief_type_label'] != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(_reliefTypeIcon(team['relief_type'] as String?),
                        color: c.accent, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(bilingual(team['relief_type_label']),
                            style:
                                TextStyle(color: c.textSub, fontSize: 13))),
                  ]),
                ],
                if (team['disaster_type'] != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: c.danger, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            bilingual((team['disaster_type']
                                as Map<String, dynamic>)['name']),
                            style:
                                TextStyle(color: c.textSub, fontSize: 13))),
                  ]),
                ],
                if (team['deployed_at'] != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.access_time_rounded,
                        color: c.textSub, size: 15),
                    const SizedBox(width: 6),
                    Text(relativeTime(team['deployed_at'] as String?),
                        style: TextStyle(color: c.textSub, fontSize: 13)),
                  ]),
                ],
              ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(t('relief_ok'), style: TextStyle(color: c.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendRequest() async {
    setState(() => _sending = true);
    try {
      await ApiClient.post('/relief-requests', {});
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    final c = col(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => Directionality(
        textDirection:
            appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: c.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: c.success.withOpacity(0.12), shape: BoxShape.circle),
                child:
                    Icon(Icons.emergency_rounded, color: c.success, size: 40)),
            const SizedBox(height: 16),
            Text(t('relief_sent'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.4)),
            const SizedBox(height: 10),
            if (user.cityName.isNotEmpty || user.streetName.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: c.bg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                    [
                      if (user.cityName.isNotEmpty) user.cityName,
                      if (user.streetName.isNotEmpty) user.streetName,
                      if (user.buildingNumber.isNotEmpty) user.buildingNumber
                    ].join(' · '),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSub, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.pop(dCtx),
                  child: Text(t('relief_ok'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                )),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('relief_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Section 1: Send Relief ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: c.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.emergency_rounded,
                        color: c.success, size: 26)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(t('relief_ready'),
                        style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.3))),
              ]),
              const SizedBox(height: 16),
              // User's registered data
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border)),
                child: Column(children: [
                  infoRow(c, Icons.location_city_rounded, t('city_lbl'),
                      user.cityName),
                  Divider(color: c.border, height: 1),
                  infoRow(c, Icons.signpost_rounded, t('street_lbl'),
                      user.streetName),
                  Divider(color: c.border, height: 1),
                  infoRow(c, Icons.domain_rounded, t('building_lbl'),
                      user.buildingNumber),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.info_outline_rounded, color: c.textSub, size: 13),
                const SizedBox(width: 5),
                Text(t('relief_info'),
                    style: TextStyle(color: c.textSub, fontSize: 11)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Icon(
                            _sent
                                ? Icons.check_circle_rounded
                                : Icons.send_rounded,
                            size: 20),
                    label: Text(_sent ? t('resend_btn') : t('relief_send'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _sent ? c.textSub : c.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: _sent ? 0 : 3,
                        shadowColor: c.success.withOpacity(0.4)),
                    onPressed: _sending ? null : _sendRequest,
                  )),
            ]),
          ),
          const SizedBox(height: 22),

          // ── Section 2: Active Teams ─────────────────────────────────────
          Text(t('relief_teams'),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: c.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.primary.withOpacity(0.18))),
            child: Row(children: [
              Icon(Icons.groups_rounded, color: c.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(t('active_teams'),
                      style: TextStyle(color: c.textSub, fontSize: 13))),
              Text(
                  '${_teams.where((t) => t['status'] == 'active' || t['status'] == 'en_route').length}',
                  style: TextStyle(
                      color: c.primary,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace')),
              const SizedBox(width: 6),
              Text(t('team_unit'),
                  style: TextStyle(
                      color: c.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 10),
          ..._buildTeamsList(c),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  10B. DID YOU FEEL IT (earthquake self-report / citizen science)
// ═══════════════════════════════════════════════════════════════════════════
class DidYouFeelItScreen extends StatefulWidget {
  const DidYouFeelItScreen({super.key});
  @override
  State<DidYouFeelItScreen> createState() => _DidYouFeelItState();
}

class _DidYouFeelItState extends State<DidYouFeelItScreen> {
  bool _loading = true;
  String? _error;
  bool _hasEarthquake = false;
  String? _reason;
  bool _alreadyReported = false;
  int _reportCount = 0;
  Map<String, dynamic>? _earthquake;
  List<Map<String, dynamic>> _levels = [];
  final Set<int> _selected = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/felt-reports/current-earthquake');
      if (mounted) {
        setState(() {
          _hasEarthquake = res['has_earthquake'] as bool? ?? false;
          _reason = res['reason'] as String?;
          _alreadyReported = res['already_reported'] as bool? ?? false;
          _reportCount = res['report_count'] as int? ?? 0;
          _earthquake = res['earthquake'] as Map<String, dynamic>?;
          _levels = (res['levels'] as List).cast<Map<String, dynamic>>();
          _selected.clear();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(int value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
        return;
      }
      if (_selected.length >= 3) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('dyfi_max_selection'))));
        return;
      }
      _selected.add(value);
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ApiClient
          .post('/felt-reports', {'intensity_levels': _selected.toList()});
      if (mounted) {
        setState(() {
          _alreadyReported = true;
          _reportCount += 1;
          _submitting = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _counterCard(EWColors c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: c.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.primary.withOpacity(0.18))),
        child: Column(children: [
          Text('$_reportCount',
              style: TextStyle(
                  color: c.primary,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(t('dyfi_reports_24h'),
              style: TextStyle(color: c.textSub, fontSize: 12)),
        ]),
      );

  Widget _levelItem(EWColors c, Map<String, dynamic> level) {
    final value = level['value'] as int;
    final roman = level['roman'] as String;
    final labelMap = level['label'] as Map<String, dynamic>;
    final label =
        (appLang.value == 'ar' ? labelMap['ar'] : labelMap['en'])
                ?.toString() ??
            '';
    final selected = _selected.contains(value);
    return GestureDetector(
      onTap: () => _toggle(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: selected ? c.primary.withOpacity(0.1) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? c.primary : c.border,
                width: selected ? 1.5 : 1)),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: selected ? c.primary : c.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border)),
            child: Text(roman,
                style: TextStyle(
                    color: selected ? Colors.white : c.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(color: c.text, fontSize: 13, height: 1.3))),
          const SizedBox(width: 8),
          Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: selected ? c.primary : c.textSub,
              size: 22),
        ]),
      ),
    );
  }

  Widget _buildNoEarthquake(EWColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.vibration_rounded, color: c.textSub, size: 48),
          const SizedBox(height: 12),
          Text(
              _reason == 'no_city' ? t('dyfi_no_city') : t('dyfi_no_quake'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSub, fontSize: 13)),
        ]),
      );

  Widget _buildAlreadyReported(EWColors c) => Column(children: [
        _counterCard(c),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: c.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.success.withOpacity(0.25))),
          child: Column(children: [
            Icon(Icons.check_circle_rounded, color: c.success, size: 36),
            const SizedBox(height: 10),
            Text(t('dyfi_already_reported'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]);

  Widget _buildSelection(EWColors c) {
    final canSubmit = _selected.isNotEmpty && !_submitting;
    final magnitude = _earthquake?['magnitude'];
    final location = _earthquake?['location_name'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _counterCard(c),
      if (magnitude != null || (location != null && location.isNotEmpty)) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border)),
          child: Column(children: [
            if (magnitude != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(Icons.speed_rounded, color: c.primary, size: 16),
                  const SizedBox(width: 10),
                  Text(t('dyfi_magnitude_lbl'),
                      style: TextStyle(color: c.textSub, fontSize: 13)),
                  const Spacer(),
                  Text('$magnitude',
                      style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            if (location != null && location.isNotEmpty) ...[
              Divider(color: c.border, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(Icons.location_on_outlined,
                      color: c.primary, size: 16),
                  const SizedBox(width: 10),
                  Text(t('dyfi_location_lbl'),
                      style: TextStyle(color: c.textSub, fontSize: 13)),
                  const Spacer(),
                  Text(location,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.info_outline_rounded, color: c.textSub, size: 13),
        const SizedBox(width: 5),
        Expanded(
            child: Text(t('dyfi_select_hint'),
                style: TextStyle(color: c.textSub, fontSize: 12))),
      ]),
      const SizedBox(height: 12),
      ..._levels.map((lvl) => _levelItem(c, lvl)),
      const SizedBox(height: 8),
      ewBtn(context, t('dyfi_submit_btn'),
          onTap: canSubmit ? _submit : null, loading: _submitting),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('dyfi_title'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('dyfi_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _load,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: !_hasEarthquake
                      ? _buildNoEarthquake(c)
                      : _alreadyReported
                          ? _buildAlreadyReported(c)
                          : _buildSelection(c),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  10C. EARTHQUAKE HISTORY (nationwide, paginated list from /earthquake-events)
// ═══════════════════════════════════════════════════════════════════════════
class EarthquakeHistoryScreen extends StatefulWidget {
  const EarthquakeHistoryScreen({super.key});
  @override
  State<EarthquakeHistoryScreen> createState() => _EarthquakeHistoryState();
}

class _EarthquakeHistoryState extends State<EarthquakeHistoryScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  int _currentPage = 1;
  int _lastPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await ApiClient.get('/earthquake-events?page=1', auth: false);
      final list =
          (res['earthquake_events'] as List).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _events = list;
          _currentPage = meta['current_page'] as int? ?? 1;
          _lastPage = meta['last_page'] as int? ?? 1;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _currentPage >= _lastPage) return;
    setState(() => _loadingMore = true);
    final nextPage = _currentPage + 1;
    try {
      final res = await ApiClient
          .get('/earthquake-events?page=$nextPage', auth: false);
      final list =
          (res['earthquake_events'] as List).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _events.addAll(list);
          _currentPage = meta['current_page'] as int? ?? nextPage;
          _lastPage = meta['last_page'] as int? ?? _lastPage;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _eqLocation(Map<String, dynamic> eq) {
    final city = eq['city'] as Map<String, dynamic>?;
    final name = city?['name'];
    if (name is Map) {
      final picked = appLang.value == 'ar' ? name['ar'] : name['en'];
      if (picked != null && picked.toString().isNotEmpty) {
        return picked.toString();
      }
    }
    return (eq['location_name'] as String?) ?? '';
  }

  Widget _eventCard(EWColors c, Map<String, dynamic> eq) {
    final magnitude = ((eq['magnitude'] as num?) ?? 0).toDouble();
    final depth = ((eq['depth_km'] as num?) ?? 0).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(magnitude.toStringAsFixed(1),
              style: TextStyle(
                  color: c.danger,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Icon(Icons.location_on_outlined,
                      color: c.primary, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(_eqLocation(eq),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.vertical_align_bottom_rounded,
                      color: c.textSub, size: 12),
                  const SizedBox(width: 4),
                  Text('$depth ${t('eq_km')}',
                      style: TextStyle(color: c.textSub, fontSize: 11)),
                  const SizedBox(width: 10),
                  Icon(Icons.access_time_rounded, color: c.textSub, size: 12),
                  const SizedBox(width: 4),
                  Text(relativeTime(eq['occurred_at'] as String?),
                      style: TextStyle(color: c.textSub, fontSize: 11)),
                ]),
              ])),
        ]),
        const SizedBox(height: 10),
        richterScale(c, magnitude, compact: true),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('eq_history_title'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('eq_history_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _load,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : _events.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t('eq_history_empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textSub, fontSize: 13)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _events.length +
                          (_currentPage < _lastPage ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= _events.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Center(
                              child: _loadingMore
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                          color: c.primary, strokeWidth: 2.5),
                                    )
                                  : TextButton(
                                      onPressed: _loadMore,
                                      child: Text(t('load_more_btn'),
                                          style: TextStyle(
                                              color: c.primary,
                                              fontWeight: FontWeight.w600)),
                                    ),
                            ),
                          );
                        }
                        return _eventCard(c, _events[i]);
                      },
                    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  10D. WEATHER FORECAST (per-city 7-day forecast from /weather/forecast/{code})
// ═══════════════════════════════════════════════════════════════════════════
class WeatherForecastScreen extends StatefulWidget {
  final String cityCode, cityName;
  const WeatherForecastScreen(
      {super.key, required this.cityCode, required this.cityName});
  @override
  State<WeatherForecastScreen> createState() => _WeatherForecastState();
}

class _WeatherForecastState extends State<WeatherForecastScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
          '/weather/forecast/${widget.cityCode}', auth: false);
      final list = (res['forecast'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _days = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _weekday(String? isoDate) {
    const arD = [
      'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'
    ];
    const enD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final dt = DateTime.tryParse(isoDate ?? '');
    if (dt == null) return '';
    return appLang.value == 'ar' ? arD[dt.weekday % 7] : enD[dt.weekday % 7];
  }

  Widget _dayCard(EWColors c, Map<String, dynamic> d, bool isToday) {
    final cond = weatherCond(d['weather_code']);
    final condIcon = cond == 's'
        ? Icons.wb_sunny_rounded
        : cond == 'r'
            ? Icons.grain_rounded
            : Icons.cloud_rounded;
    final condColor = cond == 's'
        ? const Color(0xFFFBBF24)
        : cond == 'r'
            ? Colors.blueAccent
            : Colors.blueGrey;
    final maxT = (d['temperature_max_c'] as num?)?.round();
    final minT = (d['temperature_min_c'] as num?)?.round();
    final hum = d['humidity_percent'];
    final wind = (d['wind_speed_kmh'] as num?)?.round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border)),
      child: Row(children: [
        Icon(condIcon, color: condColor, size: 26),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(_weekday(d['date'] as String?),
                    style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: c.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(t('forecast_today'),
                          style: TextStyle(
                              color: c.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700))),
                ],
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.water_drop_rounded, color: Colors.blue, size: 13),
                const SizedBox(width: 4),
                Text('$hum%',
                    style: TextStyle(color: c.textSub, fontSize: 12)),
                const SizedBox(width: 10),
                Icon(Icons.air_rounded, color: c.accent, size: 13),
                const SizedBox(width: 4),
                Text('$wind km/h',
                    style: TextStyle(color: c.textSub, fontSize: 12)),
              ]),
            ])),
        Text('$maxT° / $minT°',
            style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(widget.cityName)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('forecast_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _load,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: _days.length,
                  itemBuilder: (ctx, i) => _dayCard(c, _days[i], i == 0),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  11. PROFILE
// ═══════════════════════════════════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfState();
}

class _ProfState extends State<ProfileScreen> {
  bool _editing = false;
  File? _pickedImage;
  bool _saving = false;
  final _fn = TextEditingController();
  final _ln = TextEditingController();
  final _city = TextEditingController();
  final _mail = TextEditingController();
  final _street = TextEditingController();
  final _build = TextEditingController();
  SyrianCity? _sel;
  List<SyrianCity> _sugg = [];

  @override
  void initState() {
    super.initState();
    _fillFromUser();
    _loadProfile();
    if (cities.isEmpty) {
      loadCities().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _fillFromUser() {
    _fn.text = user.firstName;
    _ln.text = user.lastName;
    _city.text = user.cityName;
    _mail.text = user.email;
    _street.text = user.streetName;
    _build.text = user.buildingNumber;
  }

  Future<void> _loadProfile() async {
    try {
      final res = await ApiClient.get('/profile');
      applyUserFromJson(res['user'] as Map<String, dynamic>);
      if (mounted) setState(_fillFromUser);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  void dispose() {
    _fn.dispose();
    _ln.dispose();
    _city.dispose();
    _mail.dispose();
    _street.dispose();
    _build.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: src, imageQuality: 85, maxWidth: 512);
      if (picked != null && mounted) {
        setState(() => _pickedImage = File(picked.path));
      }
    } catch (_) {}
  }

  void _showPickSheet() {
    final c = col(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection:
            appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: c.border, borderRadius: BorderRadius.circular(2))),
              Text(t('change_photo'),
                  style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: c.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.photo_library_rounded,
                        color: c.primary, size: 22)),
                title: Text(t('pick_gallery'),
                    style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              ListTile(
                leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.camera_alt_rounded,
                        color: c.accent, size: 22)),
                title: Text(t('pick_camera'),
                    style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ])),
      ),
    );
  }

  InputDecoration _dec(BuildContext ctx,
      {bool enabled = true, Widget? suffix}) {
    final c = col(ctx);
    return InputDecoration(
        filled: true,
        fillColor: enabled ? c.input : c.surface,
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border.withOpacity(0.4))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.primary, width: 1.8)));
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: c.text),
        title: Text(t('my_acc')),
        actions: [
          if (!_editing)
            TextButton.icon(
                onPressed: () => setState(() {
                      _editing = true;
                      _sugg = [];
                    }),
                icon: Icon(Icons.edit_outlined, color: c.primary, size: 18),
                label: Text(t('edit_lbl'), style: TextStyle(color: c.primary)))
        ],
      ),
      body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
          child: Column(children: [
            // ── Avatar ─────────────────────────────────────────────────────────
            Center(
                child: Stack(clipBehavior: Clip.none, children: [
              Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary.withOpacity(0.12),
                    border: Border.all(
                        color: c.primary.withOpacity(0.5), width: 2.5),
                    image: _pickedImage != null
                        ? DecorationImage(
                            image: FileImage(_pickedImage!), fit: BoxFit.cover)
                        : user.profileImageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(user.profileImageUrl!),
                                fit: BoxFit.cover)
                            : null,
                  ),
                  child: _pickedImage == null && user.profileImageUrl == null
                      ? Icon(Icons.person_rounded, color: c.primary, size: 48)
                      : null),
              if (_editing)
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showPickSheet,
                      child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.bg, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                    color: c.primary.withOpacity(0.4),
                                    blurRadius: 6)
                              ]),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 17)),
                    )),
            ])),
            const SizedBox(height: 24),
            // ── Fields ─────────────────────────────────────────────────────────
            flabel(context, t('fn_lbl')),
            TextField(
                controller: _fn,
                enabled: _editing,
                style: TextStyle(color: c.text),
                decoration: _dec(context)),
            const SizedBox(height: 14),
            flabel(context, t('ln_lbl')),
            TextField(
                controller: _ln,
                enabled: _editing,
                style: TextStyle(color: c.text),
                decoration: _dec(context)),
            const SizedBox(height: 14),
            flabel(context, t('city_lbl')),
            TextField(
                controller: _city,
                enabled: _editing,
                onChanged: _editing
                    ? (v) => setState(() {
                          _sel = null;
                          _sugg = v.isEmpty
                              ? []
                              : cities
                                  .where((ct) => ct.name.contains(v))
                                  .take(5)
                                  .toList();
                        })
                    : null,
                style: TextStyle(color: c.text),
                decoration: _dec(context,
                    suffix: _sel != null
                        ? Icon(Icons.check_circle_rounded,
                            color: c.success, size: 22)
                        : null)),
            if (_editing && _sugg.isNotEmpty)
              Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border)),
                  child: Column(
                      children: _sugg
                          .map((city) => InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                    _city.text = city.name;
                                    _sel = city;
                                    _sugg = [];
                                  }),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(city.name,
                                            style: TextStyle(
                                                color: c.text, fontSize: 14)),
                                        Text('ID: ${city.id}',
                                            style: TextStyle(
                                                color: c.textSub,
                                                fontSize: 11,
                                                fontFamily: 'monospace')),
                                      ]))))
                          .toList())),
            const SizedBox(height: 14),
            flabel(context, t('email_lbl')),
            TextField(
                controller: _mail,
                enabled: false,
                style: TextStyle(color: c.text),
                decoration: _dec(context, enabled: false)),
            const SizedBox(height: 14),
            flabel(context, t('street_lbl')),
            TextField(
                controller: _street,
                enabled: _editing,
                style: TextStyle(color: c.text),
                decoration: _dec(context)),
            const SizedBox(height: 14),
            flabel(context, t('building_lbl')),
            TextField(
                controller: _build,
                enabled: _editing,
                keyboardType: TextInputType.number,
                style: TextStyle(color: c.text),
                decoration: _dec(context)),
            const SizedBox(height: 20),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => push(context, const ChangePasswordScreen()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border)),
                child: Row(children: [
                  Icon(Icons.lock_outline_rounded, color: c.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(t('change_pass_menu'),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600))),
                  Icon(
                      appLang.value == 'ar'
                          ? Icons.arrow_back_ios_new_rounded
                          : Icons.arrow_forward_ios_rounded,
                      color: c.textSub,
                      size: 14),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // ── Buttons ────────────────────────────────────────────────────────
            if (_editing)
              Row(children: [
                Expanded(
                    child: ewOutBtn(context, t('cancel_lbl'),
                        onTap: _saving
                            ? null
                            : () => setState(() {
                                  _editing = false;
                                  _sugg = [];
                                  _pickedImage = null;
                                  _fillFromUser();
                                  _sel = null;
                                }))),
                const SizedBox(width: 12),
                Expanded(
                    child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  setState(() => _saving = true);
                                  final fields = <String, String>{
                                    'first_name': _fn.text,
                                    'last_name': _ln.text,
                                    'street_name': _street.text,
                                    'building_number': _build.text,
                                  };
                                  if (_sel != null) {
                                    fields['city_code'] = _sel!.id;
                                  }
                                  try {
                                    final res = await ApiClient.postMultipart(
                                        '/profile', fields,
                                        filePath: _pickedImage?.path,
                                        fileField: 'profile_image');
                                    applyUserFromJson(
                                        res['user'] as Map<String, dynamic>);
                                    if (!mounted) return;
                                    setState(() {
                                      _pickedImage = null;
                                      _fillFromUser();
                                      _editing = false;
                                      _sugg = [];
                                      _saving = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t('saved_ok')),
                                        backgroundColor: c.success,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10))));
                                  } on ApiException catch (e) {
                                    if (mounted) {
                                      setState(() => _saving = false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(e.message)));
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: c.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                              shadowColor: c.primary.withOpacity(0.5)),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_rounded, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                        child: Text(t('save_lbl'),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold))),
                                  ]),
                        ))),
              ]),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  11B. CHANGE PASSWORD
// ═══════════════════════════════════════════════════════════════════════════
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePassState();
}

class _ChangePassState extends State<ChangePasswordScreen> {
  final _current = TextEditingController(),
      _pass = TextEditingController(),
      _conf = TextEditingController();
  bool _showCurrent = false, _showPass = false, _showConf = false, _loading = false;

  @override
  void initState() {
    super.initState();
    _current.addListener(_upd);
    _pass.addListener(_upd);
    _conf.addListener(_upd);
  }

  @override
  void dispose() {
    _current.removeListener(_upd);
    _pass.removeListener(_upd);
    _conf.removeListener(_upd);
    _current.dispose();
    _pass.dispose();
    _conf.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  bool get _ok =>
      _current.text.isNotEmpty &&
      isValidPassword(_pass.text) &&
      _pass.text == _conf.text;

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('change_pass_title'))),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 4),
            Text(t('change_pass_title'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 6),
            Text(t('change_pass_desc'),
                style: TextStyle(color: c.textSub, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
                controller: _current,
                obscureText: !_showCurrent,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('current_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showCurrent
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent)))),
            const SizedBox(height: 12),
            TextField(
                controller: _pass,
                obscureText: !_showPass,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('new_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass)))),
            if (_pass.text.isNotEmpty && !isValidPassword(_pass.text))
              Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                  child: Text(t('pass_short'),
                      style: TextStyle(color: c.danger, fontSize: 12))),
            const SizedBox(height: 12),
            TextField(
                controller: _conf,
                obscureText: !_showConf,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: _ewDec(context, t('conf_new_pass_hint'),
                    suffix: IconButton(
                        icon: Icon(
                            _showConf
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.textSub,
                            size: 20),
                        onPressed: () =>
                            setState(() => _showConf = !_showConf)))),
            const SizedBox(height: 28),
            ewBtn(context, t('reset_pass_btn'),
                loading: _loading,
                onTap: _ok
                    ? () async {
                        setState(() => _loading = true);
                        try {
                          await ApiClient.post('/profile/change-password', {
                            'current_password': _current.text,
                            'password': _pass.text,
                            'password_confirmation': _conf.text,
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(t('change_pass_success'))));
                            Navigator.pop(context);
                          }
                        } on ApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      }
                    : null),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  11. LANGUAGE
// ═══════════════════════════════════════════════════════════════════════════
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});
  @override
  State<LanguageScreen> createState() => _LangState();
}

class _LangState extends State<LanguageScreen> {
  void _rb() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    appLang.addListener(_rb);
  }

  @override
  void dispose() {
    appLang.removeListener(_rb);
    super.dispose();
  }

  Widget _opt(BuildContext ctx, String code, String label, Widget flag) {
    final c = col(ctx);
    final sel = appLang.value == code;
    return GestureDetector(
        onTap: () {
          appLang.value = code;
          unawaited(savePrefChoice('app_lang', code));
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: sel ? c.primary.withOpacity(0.1) : c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? c.primary.withOpacity(0.65) : c.border,
                    width: sel ? 1.8 : 1)),
            child: Row(children: [
              flag,
              const SizedBox(width: 16),
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: sel ? c.primary : c.text,
                          fontSize: 17,
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal))),
              if (sel)
                Icon(Icons.check_circle_rounded, color: c.primary, size: 24),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('lang_title'))),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const SizedBox(height: 8),
            _opt(context, 'ar', t('arabic'), newSyriaFlag()),
            const SizedBox(height: 12),
            _opt(context, 'en', t('english'),
                const Text('🇺🇸', style: TextStyle(fontSize: 28))),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  12. THEMES
// ═══════════════════════════════════════════════════════════════════════════
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});
  @override
  State<ThemesScreen> createState() => _ThemesState();
}

class _ThemesState extends State<ThemesScreen> {
  void _rb() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    appTheme.addListener(_rb);
  }

  @override
  void dispose() {
    appTheme.removeListener(_rb);
    super.dispose();
  }

  Widget _opt(
      BuildContext ctx, String code, String label, IconData icon, String desc) {
    final c = col(ctx);
    final sel = appTheme.value == code;
    return GestureDetector(
        onTap: () {
          appTheme.value = code;
          unawaited(savePrefChoice('app_theme', code));
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: sel ? c.primary.withOpacity(0.1) : c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? c.primary.withOpacity(0.65) : c.border,
                    width: sel ? 1.8 : 1)),
            child: Row(children: [
              Icon(icon, color: sel ? c.primary : c.textSub, size: 24),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: TextStyle(
                            color: sel ? c.primary : c.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: TextStyle(color: c.textSub, fontSize: 12)),
                  ])),
              if (sel)
                Icon(Icons.check_circle_rounded, color: c.primary, size: 22),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('themes_title'))),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('mode_lbl'),
                style: TextStyle(
                    color: c.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            _opt(context, 'dark', t('dark_lbl'), Icons.nightlight_outlined,
                t('dark_desc')),
            const SizedBox(height: 10),
            _opt(context, 'light', t('light_lbl'), Icons.wb_sunny_outlined,
                t('light_desc')),
            const SizedBox(height: 10),
            _opt(context, 'classic', t('classic_lbl'), Icons.palette_outlined,
                t('classic_desc')),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  13. REPORTS
// ═══════════════════════════════════════════════════════════════════════════
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('reports_menu'))),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 8),
            Text(t('slogan'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.text,
                    height: 1.7)),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                  child: _card(
                      context,
                      Icons.add_circle_outline_rounded,
                      t('new_rep'),
                      c.primary,
                      c,
                      () => push(context, const NewReportScreen()))),
              const SizedBox(width: 14),
              Expanded(
                  child: _card(
                      context,
                      Icons.history_rounded,
                      t('hist_rep'),
                      c.accent,
                      c,
                      () => push(context, const ReportHistoryScreen()))),
            ]),
          ])),
    );
  }

  Widget _card(BuildContext ctx, IconData icon, String label, Color color,
          EWColors c, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Column(children: [
                Icon(icon, color: color, size: 36),
                const SizedBox(height: 10),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14))
              ])));
}

class NewReportScreen extends StatefulWidget {
  const NewReportScreen({super.key});
  @override
  State<NewReportScreen> createState() => _NRState();
}

class _NRState extends State<NewReportScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_upd);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_upd);
    _ctrl.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  Future<void> _send(EWColors c) async {
    setState(() => _sending = true);
    try {
      await ApiClient.post('/reports', {'message': _ctrl.text});
      if (!mounted) return;
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                backgroundColor: c.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 8),
                  Icon(Icons.mark_email_read_outlined,
                      color: c.success, size: 60),
                  const SizedBox(height: 14),
                  Text(t('rep_sent'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: c.text)),
                  const SizedBox(height: 6),
                  Text(t('thank_you'), style: TextStyle(color: c.textSub)),
                  const SizedBox(height: 8),
                ]),
              ));
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) pushOff(context, const MainScreen());
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar:
          AppBar(leading: BackButton(color: c.text), title: Text(t('new_rep'))),
      body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(children: [
            Expanded(
                child: TextField(
                    controller: _ctrl,
                    maxLength: 400,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textDirection: appLang.value == 'ar'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    style: TextStyle(color: c.text, fontSize: 15, height: 1.7),
                    decoration: InputDecoration(
                        hintText: t('rep_hint'),
                        hintStyle: TextStyle(color: c.textSub, fontSize: 14),
                        filled: true,
                        fillColor: c.input,
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: c.border)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: c.primary, width: 1.8))))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: ewOutBtn(context, t('cancel_lbl'),
                      onTap: _sending ? null : () => Navigator.pop(context))),
              const SizedBox(width: 12),
              Expanded(
                  child: ewBtn(context, t('send_rep'),
                      loading: _sending,
                      onTap: _ctrl.text.isNotEmpty && !_sending
                          ? () => _send(c)
                          : null)),
            ]),
          ])),
    );
  }
}

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});
  @override
  State<ReportHistoryScreen> createState() => _RepHistState();
}

class _RepHistState extends State<ReportHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/reports');
      final list = (res['reports'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _reports = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _reportStatusColor(EWColors c, String? status) {
    switch (status) {
      case 'in_review':
        return c.accent;
      case 'resolved':
        return c.success;
      case 'rejected':
        return c.danger;
      default: // pending
        return c.textSub;
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date — $time';
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('hist_title'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('reports_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _loadReports,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : _reports.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.inbox_outlined, color: c.textSub, size: 68),
                          const SizedBox(height: 16),
                          Text(t('no_reps'),
                              style: TextStyle(color: c.textSub, fontSize: 15))
                        ]))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final r = _reports[i];
                        final txt = (r['message'] as String?) ?? '';
                        final reply = r['admin_reply'] as String?;
                        final hasReply = reply != null && reply.isNotEmpty;
                        final when =
                            _formatDateTime(r['created_at'] as String?);
                        return GestureDetector(
                            onTap: () => showModalBottomSheet(
                                context: ctx,
                                backgroundColor: c.surface,
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(20))),
                                builder: (_) => Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        22, 20, 22, 32),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: _reportStatusColor(
                                                          c,
                                                          r['status']
                                                              as String?)
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8)),
                                              child: Text(
                                                  bilingual(
                                                      r['status_label']),
                                                  style: TextStyle(
                                                      color:
                                                          _reportStatusColor(
                                                              c,
                                                              r['status']
                                                                  as String?),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700))),
                                          const SizedBox(height: 14),
                                          Text(t('rep_content'),
                                              style: TextStyle(
                                                  color: c.textSub,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(height: 8),
                                          Text(txt,
                                              style: TextStyle(
                                                  color: c.text,
                                                  fontSize: 14,
                                                  height: 1.7)),
                                          const SizedBox(height: 16),
                                          Divider(color: c.border),
                                          const SizedBox(height: 8),
                                          Text(t('team_reply'),
                                              style: TextStyle(
                                                  color: c.primary,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          const SizedBox(height: 8),
                                          Text(
                                              hasReply
                                                  ? reply
                                                  : t('rep_pending'),
                                              style: TextStyle(
                                                  color: hasReply
                                                      ? c.text
                                                      : c.textSub,
                                                  fontSize: 14,
                                                  height: 1.7)),
                                        ]))),
                            child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: c.border)),
                                child: Row(children: [
                                  Icon(Icons.description_outlined,
                                      color: c.primary, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(txt,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: c.text,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 3),
                                        Text(when,
                                            style: TextStyle(
                                                color: c.textSub,
                                                fontSize: 11,
                                                fontFamily: 'monospace')),
                                      ])),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      margin: const EdgeInsets.only(
                                          left: 6, right: 6),
                                      decoration: BoxDecoration(
                                          color: _reportStatusColor(
                                                  c, r['status'] as String?)
                                              .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(7)),
                                      child: Text(
                                          bilingual(r['status_label']),
                                          style: TextStyle(
                                              color: _reportStatusColor(c,
                                                  r['status'] as String?),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700))),
                                  Icon(
                                      appLang.value == 'ar'
                                          ? Icons.arrow_back_ios_new_rounded
                                          : Icons.arrow_forward_ios_rounded,
                                      color: c.textSub,
                                      size: 14),
                                ])));
                      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  14. PERMISSIONS
// ═══════════════════════════════════════════════════════════════════════════
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermState();
}

class _PermState extends State<PermissionsScreen> {
  bool _n = true, _s = true, _u = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final n = await NotificationPrefs.notificationsEnabled();
    final s = await NotificationPrefs.alertSoundEnabled();
    if (!mounted) return;
    setState(() {
      _n = n;
      _s = s;
    });
  }

  Widget _perm(BuildContext ctx, IconData icon, String title, String desc,
      bool val, ValueChanged<bool> onChange) {
    final c = col(ctx);
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: val ? c.primary.withOpacity(0.35) : c.border)),
        child: Row(children: [
          Icon(icon, color: val ? c.primary : c.textSub, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: val ? c.text : c.textSub,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(desc,
                    style:
                        TextStyle(color: c.textSub, fontSize: 11, height: 1.5)),
              ])),
          Switch.adaptive(
              value: val, onChanged: onChange, activeColor: c.primary),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('perm_title'))),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _perm(context, Icons.notifications_active_outlined, t('p1_title'),
                t('p1_desc'), _n, (v) async {
              setState(() => _n = v);
              await NotificationPrefs.setNotificationsEnabled(v);
              unawaited(PushNotifications.registerDeviceToken());
            }),
            _perm(context, Icons.volume_up_outlined, t('p2_title'),
                t('p2_desc'), _s, (v) async {
              setState(() => _s = v);
              await NotificationPrefs.setAlertSoundEnabled(v);
              unawaited(PushNotifications.registerDeviceToken());
            }),
            _perm(context, Icons.system_update_outlined, t('p3_title'),
                t('p3_desc'), _u, (v) => setState(() => _u = v)),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  15. ABOUT US
// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
//  PRECAUTIONS LIST
// ═══════════════════════════════════════════════════════════════════════════
class PrecautionsScreen extends StatelessWidget {
  const PrecautionsScreen({super.key});

  static const _items = [
    ('earthquake', 'prec_eq', 'flt_eq', 0xFFEF4444, Icons.show_chart_rounded),
    ('flash_flood', 'prec_torrent', 'flt_torrent', 0xFF0EA5E9, Icons.waves),
    ('flood', 'prec_flood', 'flt_flood', 0xFF3B82F6, Icons.water_drop_outlined),
    ('severe_storm', 'prec_severe_storm', 'flt_severe_storm', 0xFF8B5CF6,
        Icons.air_rounded),
    ('coastal_storm', 'prec_coastal_storm', 'flt_coastal_storm', 0xFFF59E0B,
        Icons.sailing_rounded),
    ('tsunami', 'prec_tsunami', 'flt_tsunami', 0xFF06B6D4, Icons.water),
  ];

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('precautions_title'))),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          final item = _items[i];
          final type = item.$1;
          final titleKey = item.$2;
          final subKey = item.$3;
          final color = Color(item.$4);
          final icon = item.$5;
          return InkWell(
            onTap: () => push(context,
                PrecautionDetailScreen(type: type, titleKey: titleKey)),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Row(children: [
                Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, color: color, size: 26)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(t(subKey),
                          style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(t(titleKey),
                          style: TextStyle(color: c.text, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(t('prec_phases'),
                          style: TextStyle(color: c.textSub, fontSize: 10)),
                    ])),
                const SizedBox(width: 8),
                Icon(Icons.arrow_back_ios_new_rounded,
                    color: c.textSub, size: 14),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRECAUTION DETAIL
// ═══════════════════════════════════════════════════════════════════════════
class PrecautionDetailScreen extends StatefulWidget {
  final String type, titleKey;
  // Only set when opened from the Danger Simulator's training flow — adds a
  // relief-request button that shows a training-only explanation instead of
  // the real relief form, so a drill never sends real data to the server.
  // Defaults to false, so the real Precautions screen is unchanged.
  final bool trainingMode;
  const PrecautionDetailScreen(
      {super.key,
      required this.type,
      required this.titleKey,
      this.trainingMode = false});
  @override
  State<PrecautionDetailScreen> createState() => _PrecDetailState();
}

class _PrecDetailState extends State<PrecautionDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _disasterType;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/disaster-types', auth: false);
      final list =
          (res['disaster_types'] as List).cast<Map<String, dynamic>>();
      unawaited(_cacheDisasterTypes(list));
      final match = list.where((d) => d['key'] == widget.type).toList();
      if (mounted) {
        setState(() {
          _disasterType = match.isEmpty ? null : match.first;
          _fromCache = false;
        });
      }
    } on ApiException catch (e) {
      // No signal or the server is unreachable — fall back to whatever was
      // last cached (see prefetchDisasterTypes) instead of a bare error,
      // since this content matters most exactly when a disaster may have
      // taken the connection down.
      final cached = await _readCachedDisasterTypes();
      final match =
          cached?.where((d) => d['key'] == widget.type).toList() ?? [];
      if (mounted) {
        if (match.isNotEmpty) {
          setState(() {
            _disasterType = match.first;
            _fromCache = true;
            _error = null;
          });
        } else {
          setState(() => _error = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final c = col(context);

    const phases = [
      ('prec_before', Icons.schedule_rounded, Color(0xFF10B981),
          'instructions_before'),
      ('prec_during', Icons.warning_amber_rounded, Color(0xFFEF4444),
          'instructions_during'),
      ('prec_after', Icons.check_circle_outline_rounded, Color(0xFF3B82F6),
          'instructions_after'),
    ];

    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t(widget.titleKey))),
      bottomNavigationBar: widget.trainingMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (dCtx) => Directionality(
                      textDirection: appLang.value == 'ar'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: AlertDialog(
                        backgroundColor: c.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        title: Text(t('sim_relief_title'),
                            style: TextStyle(color: c.text)),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('sim_relief_body'),
                                  style: TextStyle(
                                      color: c.textSub,
                                      height: 1.5,
                                      fontSize: 13)),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                    color: c.bg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: c.border)),
                                child: Column(children: [
                                  infoRow(c, Icons.location_city_rounded,
                                      t('city_lbl'), user.cityName),
                                  Divider(color: c.border, height: 1),
                                  infoRow(c, Icons.signpost_rounded,
                                      t('street_lbl'), user.streetName),
                                  Divider(color: c.border, height: 1),
                                  infoRow(c, Icons.domain_rounded,
                                      t('building_lbl'),
                                      user.buildingNumber),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        color: c.textSub, size: 13),
                                    const SizedBox(width: 5),
                                    Expanded(
                                        child: Text(t('sim_relief_no_data'),
                                            style: TextStyle(
                                                color: c.textSub,
                                                fontSize: 11))),
                                  ]),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: Text(t('relief_ok'),
                                style: TextStyle(color: c.primary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.emergency_share_rounded),
                  label: Text(t('sim_relief_btn')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
            )
          : null,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : (_error != null || _disasterType == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('prec_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _load,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : Column(children: [
                  if (_fromCache)
                    Container(
                      width: double.infinity,
                      color: c.input,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      child: Text(t('cached_data_note'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSub, fontSize: 11)),
                    ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) {
                    final ph = phases[i];
                    final phLabel = t(ph.$1);
                    final phIcon = ph.$2;
                    final phColor = ph.$3;
                    final field =
                        _disasterType![ph.$4] as Map<String, dynamic>?;
                    final text = field == null
                        ? null
                        : (appLang.value == 'ar' ? field['ar'] : field['en'])
                            as String?;
                    final points = splitSentences(text);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: phColor.withOpacity(0.3)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                      color: phColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10)),
                                  child:
                                      Icon(phIcon, color: phColor, size: 20)),
                              const SizedBox(width: 10),
                              Text(phLabel,
                                  style: TextStyle(
                                      color: phColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 12),
                            ...points.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                            width: 6,
                                            height: 6,
                                            margin: EdgeInsets.only(
                                                top: 6,
                                                left: appLang.value == 'ar'
                                                    ? 10
                                                    : 0,
                                                right: appLang.value == 'ar'
                                                    ? 0
                                                    : 10),
                                            decoration: BoxDecoration(
                                                color: phColor,
                                                shape: BoxShape.circle)),
                                        Expanded(
                                            child: Text(p,
                                                style: TextStyle(
                                                    color: c.text,
                                                    fontSize: 13,
                                                    height: 1.55))),
                                      ]),
                                )),
                          ]),
                    );
                  },
                    ),
                  ),
                ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ABOUT
// ═══════════════════════════════════════════════════════════════════════════
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutState();
}

class _AboutState extends State<AboutScreen> {
  static const _fbUrl = 'https://facebook.com/profile.php?id=61593966375506';

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _about;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/about', auth: false);
      unawaited(_cacheAbout(res));
      if (mounted) {
        setState(() {
          _about = res;
          _fromCache = false;
        });
      }
    } on ApiException catch (e) {
      // No signal or the server is unreachable — fall back to whatever was
      // last cached instead of a bare error, same pattern used for the
      // Precautions/Weather screens' offline resilience.
      final cached = await _readCachedAbout();
      if (mounted) {
        if (cached != null) {
          setState(() {
            _about = cached;
            _fromCache = true;
            _error = null;
          });
        } else {
          setState(() => _error = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFb() async {
    final uri = Uri.parse(_fbUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text), title: Text(t('about_menu'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : (_error != null || _about == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('about_load_error'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.danger, fontSize: 14)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _load,
                        child: Text(t('retry_btn'),
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(children: [
            if (_fromCache)
              Container(
                width: double.infinity,
                color: c.input,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(t('cached_data_note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSub, fontSize: 11)),
              ),
            const SizedBox(height: 8),
            Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary.withOpacity(0.12),
                    border: Border.all(
                        color: c.primary.withOpacity(0.35), width: 2)),
                child:
                    Icon(Icons.menu_book_outlined, color: c.primary, size: 38)),
            const SizedBox(height: 18),
            Text(bilingual(_about!['title']),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 20),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border)),
                child: Text(bilingual(_about!['body']),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: c.text, fontSize: 15, height: 2.0))),
            const SizedBox(height: 16),
            // Facebook link row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1877F2).withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF1877F2).withOpacity(0.25)),
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.facebook_rounded,
                    color: Color(0xFF1877F2), size: 22),
                const SizedBox(width: 10),
                Text(t('fb_page'),
                    style: TextStyle(color: c.text, fontSize: 14)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _openFb,
                  child: Text(t('fb_link'),
                      style: const TextStyle(
                        color: Color(0xFF1877F2),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF1877F2),
                      )),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.primary.withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.favorite_rounded,
                      color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 8),
                  Text(t('made_love'),
                      style: TextStyle(
                          color: c.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ])),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TERMS OF SERVICE & PRIVACY POLICY
// ═══════════════════════════════════════════════════════════════════════════
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  // (icon, color, titleKey, bullets_ar, bullets_en) — a fixed, self-contained
  // document (like PrecautionsScreen._items), not routed through the shared
  // `_tr` map since each entry is a bullet list, not a single string.
  static const _sections = [
    (
      Icons.folder_shared_rounded,
      Color(0xFF3B82F6),
      'terms_data_title',
      [
        'الاسم الأول والأخير، والبريد الإلكتروني، وكلمة المرور (مشفّرة دائماً ولا يمكن لأحد قراءتها، حتى فريق الإدارة).',
        'المحافظة التي تختارها بنفسك عند التسجيل — لا يقوم التطبيق بتتبع موقعك الجغرافي (GPS) الحي إطلاقاً.',
        'اسم الشارع ورقم المبنى اللذين تدخلهما بنفسك، ويُستخدمان فقط لتوجيه فرق الإغاثة عند طلبك ذلك.',
        'صورة ملفك الشخصي، إن اخترت إضافتها.',
        'معرّف حسابك على Google، إذا اخترت تسجيل الدخول عبره.',
        'رمز جهازك الخاص بالإشعارات، لإيصال تنبيهات الكوارث إلى هاتفك تحديداً.',
        'أي بلاغ أو شكوى ترسلها عبر التطبيق، وأي رد يصلك عليها.',
        'أي طلب إغاثة ترسله.',
        'تقارير "هل شعرت بزلزال؟" التي ترسلها، بما فيها مستوى الشدة الذي تختاره.',
      ],
      [
        'Your first and last name, email address, and password (always encrypted — no one, including the admin team, can read it).',
        'The governorate you choose yourself at registration. The app never tracks your live GPS location.',
        'The street name and building number you type in yourself, used only to direct relief teams when you request help.',
        'Your profile picture, if you choose to add one.',
        'Your Google account identifier, if you sign in with Google.',
        "Your device's notification token, used to deliver disaster alerts to your phone specifically.",
        'Any report or complaint you submit through the app, and any reply you receive.',
        'Any relief request you submit.',
        'Any "Did You Feel It?" earthquake report you submit, including the intensity level you select.',
      ],
    ),
    (
      Icons.security_rounded,
      Color(0xFF8B5CF6),
      'terms_perms_title',
      [
        'الإنترنت: للاتصال بخوادمنا وجلب التنبيهات وبيانات الطقس والزلازل الحقيقية.',
        'الإشعارات: لإعلامك فوراً عند صدور تنبيه كارثة حقيقي، بما في ذلك تشغيل صوت الإنذار.',
        'الكاميرا: تُطلب فقط إذا اخترت التقاط صورة جديدة لملفك الشخصي.',
        'معرض الصور: يُطلب فقط إذا اخترت صورة موجودة مسبقاً لملفك الشخصي.',
        'لا يطلب التطبيق أي صلاحية أخرى — لا موقع، لا مايكروفون، لا جهات اتصال، لا رسائل.',
      ],
      [
        'Internet: to connect to our servers and fetch real alerts, weather, and earthquake data.',
        'Notifications: to inform you immediately when a real disaster alert is issued, including playing the alarm sound.',
        'Camera: requested only if you choose to take a new photo for your profile.',
        'Photo gallery: requested only if you choose an existing photo for your profile.',
        'The app requests no other permission — no location, no microphone, no contacts, no SMS.',
      ],
    ),
    (
      Icons.settings_suggest_rounded,
      Color(0xFF10B981),
      'terms_usage_title',
      [
        'لمطابقتك مع محافظتك وإرسال التنبيهات المناسبة لها فوراً عند وقوع كارثة حقيقية.',
        'للتواصل معك بخصوص أي بلاغ ترسله، عبر البريد الإلكتروني وداخل التطبيق.',
        'لتوجيه فرق الإغاثة إليك في حال طلبت ذلك.',
        'لتحسين دقة تنبيهات الطقس والزلازل بناءً على تقارير "هل شعرت بزلزال؟" التي يرسلها المستخدمون.',
        'لا تُستخدم بياناتك لأي غرض إعلاني أو تسويقي، ولا تُباع لأي جهة على الإطلاق.',
      ],
      [
        'To match you with your governorate and deliver the right alerts immediately when a real disaster occurs.',
        'To communicate with you about any report you submit, by email and inside the app.',
        'To direct relief teams to you if you request assistance.',
        'To improve weather and earthquake alert accuracy using the "Did You Feel It?" reports users submit.',
        'Your data is never used for advertising or marketing, and is never sold to anyone.',
      ],
    ),
    (
      Icons.share_rounded,
      Color(0xFFF59E0B),
      'terms_sharing_title',
      [
        'Google: لتفعيل تسجيل الدخول بحساب Google، ولإرسال الإشعارات عبر خدمة Firebase.',
        'Gmail: لإرسال رموز التحقق ورسائل البلاغات إلى بريدك الإلكتروني.',
        'خدمات الطقس والزلازل العامة (Open-Meteo وEMSC): تُستخدم فقط كمصدر للبيانات العامة، ولا يتم إرسال أي معلومة شخصية عنك إليها إطلاقاً.',
        'لا نشارك بياناتك مع أي جهة إعلانية أو تجارية أخرى.',
      ],
      [
        'Google: to enable Google Sign-In and to deliver push notifications via Firebase.',
        'Gmail: to send verification codes and report-related emails to your inbox.',
        'Public weather and earthquake services (Open-Meteo and EMSC): used only as a source of public data — no personal information about you is ever sent to them.',
        'We do not share your data with any advertiser or other commercial party.',
      ],
    ),
    (
      Icons.lock_rounded,
      Color(0xFF06B6D4),
      'terms_security_title',
      [
        'كلمة مرورك مشفّرة دائماً بتقنية تشفير قياسية (bcrypt) ولا تُحفظ كنص عادي أبداً.',
        'يتم نقل بياناتك بين التطبيق والخادم عبر اتصال مشفّر (HTTPS).',
        'رمز تسجيل دخولك محفوظ في مكان آمن ومشفّر داخل هاتفك، وليس كنص عادي.',
        'رموز التحقق (OTP) المرسلة إلى بريدك مشفّرة أيضاً على خوادمنا ولا يمكن لأحد قراءتها.',
      ],
      [
        'Your password is always encrypted using a standard hashing algorithm (bcrypt) and is never stored as plain text.',
        'Data between the app and our server travels over an encrypted connection (HTTPS).',
        'Your login token is stored securely and encrypted on your phone, not as plain text.',
        'Verification codes (OTP) sent to your email are also stored encrypted on our servers and cannot be read by anyone.',
      ],
    ),
    (
      Icons.verified_user_rounded,
      Color(0xFF6366F1),
      'terms_rights_title',
      [
        'يمكنك تعديل بياناتك الشخصية أو صورتك في أي وقت من شاشة "ملفي الشخصي".',
        'يمكنك طلب حذف حسابك بالتواصل معنا عبر ميزة "الإبلاغات" داخل التطبيق.',
        'عند حذف حسابك: تُحذف تنبيهاتك ورمز جهازك نهائياً، أما البلاغات التي قدّمتها سابقاً فتبقى محفوظة دون اسمك، للحفاظ على سجل الشكاوى.',
        'يمكنك إيقاف تشغيل الإشعارات أو صوت الإنذار في أي وقت من شاشة "الأذونات".',
      ],
      [
        'You can update your personal information or photo at any time from the "My Profile" screen.',
        'You can request your account be deleted by contacting us through the in-app "Reports" feature.',
        'If your account is deleted: your alerts and device token are permanently removed, while any reports you previously submitted are kept without your name attached, to preserve the complaint record.',
        'You can turn notifications or the alarm sound off at any time from the "Permissions" screen.',
      ],
    ),
    (
      Icons.update_rounded,
      Color(0xFF64748B),
      'terms_changes_title',
      [
        'قد نقوم بتحديث هذه الاتفاقية من وقت لآخر لتعكس أي تغييرات حقيقية في كيفية عملنا. سنُعلمك داخل التطبيق عند حدوث أي تحديث جوهري.',
      ],
      [
        'We may update this agreement from time to time to reflect real changes in how we operate. You will be notified inside the app whenever a meaningful update occurs.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = col(context);
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('terms_screen_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(t('terms_intro'),
              style: TextStyle(color: c.textSub, fontSize: 13, height: 1.7)),
          const SizedBox(height: 16),
          ..._sections.map((s) {
            final icon = s.$1;
            final color = s.$2;
            final titleKey = s.$3;
            final bullets = appLang.value == 'ar' ? s.$4 : s.$5;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(icon, color: color, size: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(t(titleKey),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 12),
                    ...bullets.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    margin: EdgeInsets.only(
                                        top: 6,
                                        left: appLang.value == 'ar' ? 10 : 0,
                                        right: appLang.value == 'ar' ? 0 : 10),
                                    decoration: BoxDecoration(
                                        color: color, shape: BoxShape.circle)),
                                Expanded(
                                    child: Text(p,
                                        style: TextStyle(
                                            color: c.text,
                                            fontSize: 13,
                                            height: 1.55))),
                              ]),
                        )),
                  ]),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────── Danger Simulator ────────────────────────────────
class DangerSimulatorScreen extends StatefulWidget {
  const DangerSimulatorScreen({super.key});
  @override
  State<DangerSimulatorScreen> createState() => _DangerSimState();
}

class _DangerSimState extends State<DangerSimulatorScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  bool _running = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  String? _selectedType;
  String? _selectedTitleKey;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _running = false);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _launch() async {
    await _player.stop();
    await _player.play(AssetSource('audio/alarm.mp3'));
    setState(() => _running = true);
    if (!mounted) return;

    // Resolve real content for the selected hazard (its real bilingual name
    // + one real quick tip from its "during" instructions) so the dialog
    // reads like an actual alert, not a bare spinner. Reads the same local
    // cache PrecautionDetailScreen uses (warmed at app startup) — no extra
    // network call needed, and it still works offline.
    String? typeName;
    String? quickTip;
    try {
      final cached = await _readCachedDisasterTypes();
      final match =
          cached?.where((d) => d['key'] == _selectedType).toList() ?? [];
      if (match.isNotEmpty) {
        typeName = bilingual(match.first['name']);
        final sentences =
            splitSentences(bilingual(match.first['instructions_during']));
        quickTip = sentences.isNotEmpty ? sentences.first : null;
      }
    } catch (_) {
      // Best-effort only — the dialog still works without this extra content.
    }

    if (!mounted) return;
    final c = Theme.of(context).extension<EWColors>()!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: c.surface,
          title: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFEF4444), size: 36)),
            ),
            const SizedBox(height: 12),
            Text('Early Warning',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: c.text)),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t('sim_running'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSub, fontSize: 15)),
              if (typeName != null && typeName.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.25)),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                          child: Text(typeName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: c.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(t('sim_critical'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.location_on_rounded,
                          color: c.textSub, size: 14),
                      const SizedBox(width: 4),
                      Text(user.cityName.isNotEmpty ? user.cityName : '—',
                          style: TextStyle(color: c.textSub, fontSize: 12)),
                    ]),
                  ]),
                ),
                if (quickTip != null && quickTip.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        color: c.accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(quickTip,
                            style: TextStyle(
                                color: c.text, fontSize: 12, height: 1.4))),
                  ]),
                ],
              ],
            ]),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.stop_rounded),
              label: Text(t('sim_stop')),
              onPressed: () async {
                await _player.stop();
                if (mounted) setState(() => _running = false);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      }),
    ).then((_) async {
      await _player.stop();
      if (mounted) setState(() => _running = false);
      // Training-only: after the alert, walk the user through the same
      // real safety instructions shown elsewhere in the app for the
      // disaster type the user picked — no data is sent to the server for
      // this drill (trainingMode swaps the relief button for a preview).
      if (mounted && _selectedType != null && _selectedTitleKey != null) {
        push(
            context,
            PrecautionDetailScreen(
                type: _selectedType!,
                titleKey: _selectedTitleKey!,
                trainingMode: true));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<EWColors>()!;
    return Directionality(
      textDirection:
          appLang.value == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(color: c.text),
          title: Text(t('sim_title'),
              style: TextStyle(color: c.text, fontWeight: FontWeight.bold)),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFF97316).withOpacity(0.35),
                            width: 2),
                      ),
                      child: const Icon(Icons.sensors_rounded,
                          color: Color(0xFFF97316), size: 44),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(t('sim_title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: c.text)),
                  const SizedBox(height: 20),
                  // Description card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(t('sim_desc'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: c.text, fontSize: 14, height: 1.7)),
                  ),
                  const SizedBox(height: 12),
                  // Warning chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFEF4444).withOpacity(0.25)),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.volume_up_rounded,
                              color: Color(0xFFEF4444), size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(t('sim_warn'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600))),
                        ]),
                  ),
                  const SizedBox(height: 20),
                  // Disaster-type picker — which disaster the drill walks
                  // the user through afterward.
                  Align(
                    alignment: appLang.value == 'ar'
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Text(t('sim_select_type'),
                        style: TextStyle(
                            color: c.textSub,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  ...PrecautionsScreen._items.map((item) {
                    final type = item.$1;
                    final titleKey = item.$2;
                    // The short hazard name ("Earthquakes"), not the
                    // Precautions-screen title ("Earthquake Precautions") —
                    // this list is picking a hazard to simulate, not opening
                    // its precautions page.
                    final shortLabelKey = item.$3;
                    final color = Color(item.$4);
                    final icon = item.$5;
                    final selected = _selectedType == type;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedType = type;
                        _selectedTitleKey = titleKey;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.1)
                                : c.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: selected ? color : c.border,
                                width: selected ? 1.5 : 1)),
                        child: Row(children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(t(shortLabelKey),
                                  style:
                                      TextStyle(color: c.text, fontSize: 13))),
                          Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected ? color : c.textSub,
                              size: 20),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Launch button
                  ElevatedButton.icon(
                    onPressed:
                        (_running || _selectedType == null) ? null : _launch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFF97316).withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon:
                        const Icon(Icons.play_circle_outline_rounded, size: 24),
                    label: Text(t('sim_launch'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}
