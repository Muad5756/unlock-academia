# تقرير دفاعي: مخاطر dylib / Runtime Hooking على تطبيق Academia iOS

تاريخ التقرير: 2026-06-26  
النطاق: `E:\muad\muadclaude\app\extracted`  
التطبيق: `com.speetar.academia.app`، الإصدار `1.9.14`، البناء `149`  
الغرض: تعليمي ودفاعي لتطوير الحماية. لا يحتوي هذا التقرير على أوامر حقن، خطوات إعادة توقيع، payloads، أو كود يساعد على تجاوز الدفع أو حماية الشاشة.

## 1. الخلاصة التنفيذية

التطبيق يحتوي على عدة أسطح حساسة يمكن للمهاجمين استهدافها عند تشغيله على جهاز مكسور الحماية أو نسخة IPA معدلة:

1. **الاشتراك والوصول للكورسات**: وجود `RevenueCat`, `purchases_flutter`, و`PurchasesHybridCommon` يعني أن أي قرار اشتراك يظهر في العميل يمكن محاولة تزويره محليًا. الحماية الصحيحة يجب أن تكون في الخادم، لا في التطبيق فقط.
2. **حماية الشاشة والفيديو**: وجود `ScreenPreventerKit`, `ScreenProtectorKit`, `screen_protector`, و`vdocipher_flutter/VdoFramework` يعني أن المهاجم قد يحاول جعل دوال حماية الشاشة ترجع "نجاح" أو تعطيل طبقة الإخفاء بينما يستمر تشغيل الفيديو.
3. **كشف الجيلبريك والـ hooks**: وجود `safe_device` و`DTTJailbreakDetection` جيد كإشارة، لكنه غير كاف إذا كان القرار النهائي محليًا. هذه الإشارات يجب أن تؤثر على إصدار التوكنات من الخادم.
4. **أسرار وإعدادات داخل الحزمة**: تم العثور على `.env.prod` و`.env.dev` داخل `flutter_assets`. يحتويان على endpoints ومفاتيح عميل واسم `SECRET_KEY` ظاهر. إذا كان هذا المفتاح مستخدمًا كسر فعلي، يجب تدويره فورًا ونقله للخادم.
5. **إعدادات نقل وملفات خطرة**: `NSAllowsArbitraryLoads=true` و`UIFileSharingEnabled=true` يزيدان أثر التحليل العكسي أو اعتراض الشبكة أو استخراج ملفات التطبيق.

أهم توصية: **أي كورس، فيديو، PDF، download token، VdoCipher OTP/license، أو entitlement يجب ألا يصدر إلا من الخادم بعد تحقق اشتراك + سلامة الجلسة + سياسة جهاز/تطبيق.**

## 2. أدلة ثابتة من الحزمة

| الدليل | الملاحظة الدفاعية |
|---|---|
| `Payload/Runner.app/Info.plist` | `CFBundleIdentifier=com.speetar.academia.app`, إصدار `1.9.14`, `MinimumOSVersion=15.6`. |
| `Payload/Runner.app/Info.plist` | `NSAllowsArbitraryLoads=true` و`NSAllowsArbitraryLoadsInWebContent=true`. يضعف سياسة TLS إذا لم توجد حماية إضافية. |
| `Payload/Runner.app/Info.plist` | `UIFileSharingEnabled=true` و`LSSupportsOpeningDocumentsInPlace=true`. راجع الحاجة لها لأن ملفات التطبيق قد تصبح أسهل وصولًا. |
| `flutter_assets/.env.prod` و`.env.dev` | ملفات بيئة مشحونة داخل التطبيق، وفيها endpoints ومفاتيح عميل وقيمة باسم `SECRET_KEY`، مع `REAL_DEVICE_CHECK=false` في dev. |
| `Frameworks/RevenueCat.framework`, `purchases_flutter.framework`, `PurchasesHybridCommon.framework` | سطح قرارات اشتراك/استحقاق داخل العميل. |
| `Frameworks/vdocipher_flutter.framework`, `VdoFramework.framework` | سطح تشغيل فيديو/DRM وتوكنات playback/offline. |
| `Frameworks/ScreenPreventerKit.framework`, `ScreenProtectorKit.framework`, `screen_protector.framework` | سطح منع screenshot/recording. |
| `Frameworks/safe_device.framework`, `DTTJailbreakDetection.framework` | سطح كشف jailbreak/runtime tampering. |
| `PlugIns/ScreenSharing.appex` | ReplayKit Broadcast Upload Extension شرعي لمشاركة الشاشة عبر RTMP، لكنه يحتاج سياسات صارمة حتى لا يصبح قناة تسريب. |

دليل سابق موجود في `defensive_fail_closed_harness/VALIDATION_STATUS.md` يؤكد وجود مؤشرات مثل:

- `enableScreenshotBlocking: failed to apply protection`
- `UIApplicationUserDidTakeScreenshotNotification`
- `UIScreenCapturedDidChangeNotification`
- `isPreventScreenshotEnabled`
- `isPreventScreenRecordingEnabled`
- `DYLD_INSERT_LIBRARIES`
- `/usr/sbin/frida-server`
- `ScreenshotProtectionService`
- `preventScreenshotOn`
- `preventScreenshotOff`
- `_checkScreenRecording`
- `allowScreenshot`

## 3. كيف يفكر المهاجم في dylib / runtime hooks

هذا القسم يصف الفئات فقط، بدون خطوات تنفيذية.

### 3.1 تزوير نتائج الاشتراك

الفكرة الهجومية: مكتبة محقونة أو runtime hook قد تغيّر نتيجة دالة أو callback تقول إن المستخدم غير مشترك إلى نتيجة تقول إنه مشترك. قد يستهدف المهاجم:

- كائنات `CustomerInfo` أو `EntitlementInfos`.
- قوائم `activeSubscriptions`.
- شاشات paywall أو route guards.
- استجابات API التي ترجع صلاحية الكورس.
- التخزين المحلي الذي يحفظ حالة الاشتراك.

المخاطر: إذا كان التطبيق يعرض الكورس أو يطلب توكن الفيديو بناءً على قرار محلي فقط، يمكن فتح المحتوى بدون دفع.

الحماية:

- اجعل الخادم هو المصدر الوحيد للاستحقاق.
- اربط كل طلب كورس أو فيديو بفحص اشتراك server-side.
- استخدم RevenueCat webhooks أو backend verification لتحديث entitlement في قاعدة بياناتك.
- لا تقبل entitlement من التطبيق كحقيقة، بل كإشارة قابلة للتلاعب.
- اجعل توكنات الفيديو قصيرة العمر ومربوطة بالمستخدم والكورس والجلسة.

### 3.2 تعطيل حماية الشاشة

الفكرة الهجومية: hook يمكن أن يجعل دالة حماية الشاشة ترجع نجاحًا حتى لو فشلت، أو يعطّل overlay/secure view، أو يمنع وصول إشعارات screen recording للتطبيق.

أسطح محتملة في هذه الحزمة:

- `ScreenPreventerKit`
- `ScreenProtectorKit`
- `screen_protector`
- `ScreenshotProtectionService`
- `preventScreenshotOn/off`
- `_checkScreenRecording`
- `allowScreenshot`

المخاطر: تشغيل الفيديو أو PDF بينما حماية الشاشة معطلة، ثم تصوير الشاشة أو تسجيلها.

الحماية:

- اجعل المحتوى محجوبًا قبل نجاح الحماية، وليس العكس.
- إذا فشلت الحماية أو تأخرت أو رجعت null، اعتبرها failure وليس warning.
- عند الفشل: أوقف player، امسح/عطّل الجلسة، واطلب revalidation.
- لا تعتمد على `UIApplicationUserDidTakeScreenshotNotification` كمنع أساسي؛ هو reactive بعد حدوث screenshot.
- لا تصدر VdoCipher OTP/license من الخادم إلا بعد نجاح policy check.
- أضف watermark ديناميكي باسم المستخدم/رقم الهاتف/وقت الجلسة على الفيديو والمستندات.

### 3.3 تجاوز كشف الجيلبريك والحقن

الفكرة الهجومية: hook قد يجعل فحوصات `isJailbroken`, `isRealDevice`, أو فحص متغيرات البيئة ترجع حالة نظيفة. كما قد يخفي أدوات runtime أو مسارات jailbreak.

أسطح دفاعية موجودة:

- `safe_device`
- `DTTJailbreakDetection`
- مؤشرات مثل `DYLD_INSERT_LIBRARIES`, `/usr/sbin/frida-server`, MobileSubstrate paths.

المخاطر: السماح بتشغيل المحتوى على بيئة قابلة للتلاعب.

الحماية:

- استخدم عدة إشارات، وليس فحصًا واحدًا.
- أرسل نتيجة الإشارات للخادم كـ risk score، ولا تجعلها قرارًا محليًا فقط.
- استخدم Apple App Attest وDeviceCheck حيثما أمكن.
- افصل سياسة "عرض UI" عن سياسة "إصدار توكنات المحتوى"؛ الخادم يجب أن يرفض التوكنات عند الخطر العالي.
- راقب تغيّر الإشارات أثناء الجلسة، وليس عند بدء التطبيق فقط.

### 3.4 تعديل IPA أو Flutter AOT

الفكرة الهجومية: بدل hook مباشر، قد يعدّل المهاجم IPA أو الثوابت أو branching داخل Flutter AOT ثم يعيد توقيع نسخة خارج App Store.

مؤشرات في الحزمة:

- أسماء دوال ومسارات Flutter/Dart ظاهرة في `App.framework/App`.
- ملفات `.env` مشحونة داخل `flutter_assets`.
- وجود dev configuration داخل حزمة الإنتاج.

المخاطر:

- قلب feature flag مثل `REAL_DEVICE_CHECK`.
- تبديل base URL أو auth endpoint.
- تعطيل شاشة paywall أو حماية screen recording.
- استخراج مفاتيح أو endpoints واستخدامها خارج التطبيق.

الحماية:

- لا تشحن `.env.dev` داخل build الإنتاج.
- لا تعتمد على `SECRET_KEY` داخل العميل لأي توقيع أو تشفير موثوق.
- انقل التوقيع والتحقق والحسابات الحساسة للخادم.
- طبّق obfuscation/strip symbols لرفع تكلفة التحليل، مع العلم أنه ليس بديلًا عن حماية الخادم.
- أضف integrity telemetry: app version, build number, bundle id, team id, jailbreak score, attestation result.

### 3.5 اعتراض الشبكة أو تزوير الاستجابات

الفكرة الهجومية: إذا استطاع المهاجم اعتراض الشبكة أو تشغيل نسخة معدلة، قد يحاول تغيير استجابات API أو استخراج tokens.

مؤشر مهم:

- `NSAllowsArbitraryLoads=true`.

المخاطر:

- تبديل response يقول إن الكورس غير متاح إلى متاح.
- استخراج stream keys أو playback tokens.
- إعادة استخدام توكنات video/offline خارج الجلسة.

الحماية:

- عطّل `NSAllowsArbitraryLoads` في الإنتاج، وأضف exceptions دقيقة فقط للضرورة.
- طبّق certificate pinning بحذر مع خطة تدوير للشهادات.
- وقّع requests الحساسة من الخادم أو اربطها بـ App Attest/session.
- لا تجعل response client-side وحده يفتح المحتوى؛ يجب أن يكون token المحتوى صادرًا من الخادم بعد policy check.
- اجعل التوكنات short-lived وغير قابلة لإعادة الاستخدام.

### 3.6 إساءة استخدام مشاركة الشاشة الشرعية

الفكرة الهجومية: التطبيق يحتوي `ScreenSharing.appex` لبث الشاشة عبر RTMP. حتى لو كانت ميزة شرعية، يمكن أن تصبح قناة تسريب إذا بدأ البث أثناء عرض محتوى محمي أو إذا خزنت مفاتيح البث بطريقة سهلة.

المخاطر:

- بث محتوى كورسات إلى RTMP خارجي.
- إعادة استخدام stream key.
- عدم ربط stream session بالمستخدم والسياسة.

الحماية:

- لا تسمح ببث شاشة أثناء عرض محتوى محمي إلا بسياسة واضحة.
- اجعل stream key قصير العمر ومربوطًا بجلسة ومستخدم.
- احفظ مفاتيح RTMP في App Group بأقل مدة ممكنة وامسحها بعد الاستخدام.
- راقب `broadcastState` وأوقف المحتوى المحمي أو حجبه عند بدء مشاركة الشاشة.

## 4. خريطة المخاطر والأولوية

| الأولوية | الخطر | الأثر | الإجراء المطلوب |
|---|---|---|---|
| P0 | الاعتماد على entitlement محلي لفتح كورسات أو فيديو | كورسات مجانية بدون دفع | انقل قرار الوصول للخادم لكل request. |
| P0 | إصدار VdoCipher token قبل تحقق الخادم | تصوير/تسريب الفيديو | اجعل token قصير العمر ومربوطًا بالمستخدم والكورس والجهاز والجلسة. |
| P0 | `SECRET_KEY` داخل التطبيق إن كان سرًا فعليًا | توقيع/تشفير قابل للاستخراج | تدوير المفتاح ونقله للخادم. |
| P1 | فشل حماية الشاشة بشكل fail-open | تسجيل الشاشة رغم الحماية | اعتماد fail-closed harness وربطه بالplayer والخادم. |
| P1 | `NSAllowsArbitraryLoads=true` | اعتراض/خفض حماية TLS | إزالته أو تقليصه إلى domain exceptions. |
| P1 | شحن `.env.dev` مع production IPA | إعدادات dev قابلة للاستغلال | أزل ملفات dev من build الإنتاج. |
| P1 | `UIFileSharingEnabled=true` بدون حاجة | تسهيل استخراج ملفات | تعطيله أو حصر الملفات الحساسة خارج documents. |
| P2 | كشف jailbreak محلي فقط | bypass عبر hook | App Attest + server risk scoring + telemetry. |
| P2 | Broadcast extension بدون ربط بسياسة المحتوى | تسريب شاشة شرعي ظاهريًا | حجب المحتوى المحمي عند البث أو السماح بسياسة server-side. |

## 5. نموذج حماية مقترح

### 5.1 قاعدة ذهبية

العميل يمكن التلاعب به. لذلك:

- العميل يطلب.
- الخادم يقرر.
- الخادم يصدر توكنات قصيرة العمر.
- العميل يعرض المحتوى فقط بعد نجاح سياسة الخادم والمحلية.

### 5.2 تدفق آمن لتشغيل فيديو كورس

1. المستخدم يفتح درسًا.
2. التطبيق يجهز طبقة حماية الشاشة ويترك الفيديو محجوبًا.
3. التطبيق يرسل للخادم:
   - user id/session id
   - course id/lesson id
   - app version/build
   - device attestation result
   - jailbreak/tamper risk score
   - screen protection status
4. الخادم يتحقق من:
   - الاشتراك أو الشراء.
   - صلاحية الجهاز والجلسة.
   - عدم تجاوز عدد الأجهزة/الجلسات.
   - عدم وجود risk score عال.
5. الخادم يصدر VdoCipher token/OTP لمدة قصيرة.
6. التطبيق يبدأ التشغيل.
7. عند screenshot/recording/tamper signal:
   - التطبيق يحجب المحتوى فورًا.
   - يوقف player.
   - يرسل telemetry.
   - الخادم يلغي أو لا يجدد token.

### 5.3 سياسة المستندات/PDF

- لا تخزن PDF كاملًا قابلًا للنسخ إذا كان المحتوى مدفوعًا.
- استخدم روابط قصيرة العمر وwatermark لكل صفحة.
- اربط التحميل بالاشتراك والجهاز.
- امنع فتح الملفات الحساسة عبر `UIFileSharingEnabled` إن لم يكن مطلوبًا.
- أضف سجل تنزيلات وتحذيرات عند سلوك غير طبيعي.

## 6. خطة اختبار دفاعية مصرح بها

هذه الخطة لا تحتاج dylib أو hook payload.

### 6.1 اختبار fail-closed المحلي

استخدم الحزمة الموجودة:

- `defensive_fail_closed_harness/lib/security_gate_controller.dart`
- `defensive_fail_closed_harness/lib/method_channel_screen_protection_client.dart`
- `defensive_fail_closed_harness/ios/SecurityScreenProtectionBridge.swift`

اختبار النجاح:

- عند فشل `enableScreenshotBlocking` يجب أن يبقى المحتوى محجوبًا.
- يجب إيقاف وdispose للـ player.
- يجب إجبار revalidation أو logout.
- screenshot notification تكون telemetry فقط وليست enforcement.

ملاحظة تنفيذية: لم أتمكن من تشغيل `flutter test` في هذه البيئة لأن أمر `flutter` غير موجود في PATH.

### 6.2 اختبار backend authorization

استخدم حسابًا غير مشترك في بيئة QA:

1. اطلب course metadata.
2. اطلب VdoCipher token.
3. اطلب download/offline token.
4. اطلب PDF أو lesson assets.

النتيجة المطلوبة:

- الخادم يرفض كل طلب محمي حتى لو أرسل العميل flags تقول إنه آمن أو مشترك.
- لا يوجد token جديد بعد فشل حماية الشاشة.
- logs تربط الرفض بالمستخدم، الجهاز، الكورس، وسبب السياسة.

### 6.3 اختبار إعدادات الإنتاج

قبل كل release:

- افحص IPA لعدم وجود `.env.dev`.
- افحص عدم وجود مفاتيح سرية داخل `flutter_assets`.
- تحقق أن `REAL_DEVICE_CHECK` لا يأتي من ملف عميل قابل للتعديل.
- تحقق أن `NSAllowsArbitraryLoads` غير مفعل إلا باستثناءات محدودة.
- تحقق من عدم وجود debug endpoints.
- تحقق أن `UIFileSharingEnabled` له حاجة واضحة أو معطل.

## 7. توصيات فورية

1. **دوّر أي قيمة اسمها `SECRET_KEY` إذا كانت مستخدمة كسر فعلي**، وانقل الاستخدام للخادم.
2. **أزل `.env.dev` من IPA الإنتاج** ولا تشحن flags تطوير داخل التطبيق.
3. **اجعل `REAL_DEVICE_CHECK` سياسة خادمية**، وليس flag قابل للقراءة والتعديل داخل assets.
4. **ألغ `NSAllowsArbitraryLoads`** أو حصره في domains محددة مع سبب واضح.
5. **اربط RevenueCat بالbackend** عبر webhooks وتحقق server-side قبل فتح أي كورس.
6. **لا تصدر VdoCipher OTP/license إلا بعد تحقق server-side** من الاشتراك والجهاز والجلسة وحالة الحماية.
7. **اعتمد fail-closed للحماية**: أي فشل/timeout/null في screen protection يعني حجب وإيقاف player.
8. **أضف watermark ديناميكي** على الفيديو وPDF لتقليل قيمة التسريب.
9. **راقب مؤشرات الخطر**: أجهزة كثيرة، token reuse، تبدل IP/device، فشل حماية متكرر، تشغيل Broadcast أثناء محتوى محمي.
10. **راجع `ScreenSharing.appex`**: امنع أو حجّب المحتوى المحمي عند بدء broadcast، واجعل stream keys قصيرة العمر.

## 8. ما لم يتم إثباته في هذا الفحص

لم يتم إثبات تجاوز فعلي للدفع أو DRM لأن ذلك يحتاج:

- جهاز iOS مصرح به للاختبار.
- حسابات QA: مشترك وغير مشترك.
- سجلات backend.
- بيئة dynamic testing مصرح بها.

النتيجة الحالية: **المخاطر plausible ومهمة، لكن إثبات bypass كامل يتطلب اختبارًا ديناميكيًا يثبت أن الخادم أصدر محتوى محميًا لحساب غير مستحق أو لجهاز فشل في سياسة الحماية.**

## 9. معيار القبول الأمني قبل الإطلاق

اعتبر الحماية مقبولة فقط إذا تحقق الآتي:

- حساب غير مشترك لا يستطيع الحصول على course/video/PDF token من الخادم.
- فشل حماية الشاشة يمنع إصدار أو تجديد video token.
- hook أو تعديل محلي لحالة الاشتراك لا يكفي لفتح المحتوى.
- dev config غير موجود في production IPA.
- لا توجد أسرار server-side داخل التطبيق.
- كل فيديو أو PDF حساس يحمل watermark ديناميكيًا.
- بدء screen sharing أو screen recording يحجب المحتوى أو يوقف الجلسة حسب السياسة.
- telemetry يغطي كل قرار رفض أو revalidation.

## 10. مراجع داخلية مفيدة

- `defensive_fail_closed_harness/README.md`
- `defensive_fail_closed_harness/VALIDATION_STATUS.md`
- `defensive_fail_closed_harness/IOS_DEV_MODE_TEST.md`
- `Payload/Runner.app/Info.plist`
- `Payload/Runner.app/PlugIns/ScreenSharing.appex/README.md`
- `Payload/Runner.app/PlugIns/ScreenSharing.appex/MONITORING_GUIDE.md`
