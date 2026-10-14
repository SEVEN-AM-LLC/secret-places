#!/usr/bin/env python3
"""Generates the static site (index / privacy / support) with a shared header & footer.
Run: python3 build.py  — writes the .html files next to this script."""
from pathlib import Path

HERE = Path(__file__).parent
CONTACT = "hello@7am.agency"
UPDATED_EN, UPDATED_UK = "14 October 2026", "14 жовтня 2026"

def page(slug, title_en, title_uk, desc, body):
    nav = [("index", "Home", "Головна", "/"), ("privacy", "Privacy", "Приватність", "/privacy"), ("support", "Support", "Підтримка", "/support")]
    links = "".join(
        f'<a href="{href}"{" aria-current=\"page\"" if s == slug else ""}><span lang="en">{en}</span><span lang="uk">{uk}</span></a>'
        for s, en, uk, href in nav)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_en}</title>
<meta name="title-en" content="{title_en}">
<meta name="title-uk" content="{title_uk}">
<meta name="description" content="{desc}">
<meta name="theme-color" content="#121217">
<link rel="icon" href="/favicon.png">
<link rel="apple-touch-icon" href="/icon-180.png">
<link rel="stylesheet" href="/style.css">
<script src="/lang.js"></script>
</head>
<body>
<header class="top"><div class="wrap">
  <a class="brand" href="/"><img src="/icon-180.png" alt=""><span>Secret Places</span></a>
  <nav class="links">{links}</nav>
  <div class="lang" role="group" aria-label="Language"><button data-lang="en" aria-pressed="true">EN</button><button data-lang="uk" aria-pressed="false">UA</button></div>
</div></header>
{body}
<footer><div class="wrap">
  <span>© 2026 SEVEN AM LLC</span>
  <span><a href="/privacy"><span lang="en">Privacy Policy</span><span lang="uk">Політика приватності</span></a> · <a href="/support"><span lang="en">Support</span><span lang="uk">Підтримка</span></a> · <a href="mailto:{CONTACT}">{CONTACT}</a></span>
</div></footer>
</body>
</html>
"""

INDEX = f"""<main class="wrap">
<section class="hero">
  <img class="icon" src="/icon-512.png" alt="Secret Places app icon">
  <h1 lang="en">The city's best-kept secrets</h1>
  <h1 lang="uk">Найкраще сховані секрети міста</h1>
  <p class="lede" lang="en">Hidden courtyards, unmarked bars, quiet viewpoints and underground nights — curated by locals, revealed when you're ready to go. Starting in Ukraine, with more cities on the way.</p>
  <p class="lede" lang="uk">Приховані дворики, бари без вивісок, тихі оглядові майданчики й андерграундні вечірки — зібрані місцевими й відкриваються, коли ти готовий іти. Починаємо з України, далі — нові міста світу.</p>
  <span class="badge"><span lang="en">Coming soon to the App Store</span><span lang="uk">Незабаром в App Store</span></span>
</section>
<section class="features">
  <div class="card"><span class="ic">🗝️</span>
    <h3 lang="en">Secrets, kept secret</h3><h3 lang="uk">Секрети лишаються секретами</h3>
    <p lang="en">Browse teasers for free. Unlock a place to get the exact spot, directions and insider tips.</p>
    <p lang="uk">Переглядай тизери безкоштовно. Відкрий місце — отримаєш точну локацію, маршрут і поради.</p></div>
  <div class="card"><span class="ic">🍸</span>
    <h3 lang="en">Night routes</h3><h3 lang="uk">Нічні маршрути</h3>
    <p lang="en">Curated bar crawls and underground nights, stop by stop — door words included.</p>
    <p lang="uk">Готові бар-кроли та андерграундні вечори, зупинка за зупинкою — разом із паролями на вході.</p></div>
  <div class="card"><span class="ic">🎟️</span>
    <h3 lang="en">What's on</h3><h3 lang="uk">Афіша</h3>
    <p lang="en">Concerts, theatre, markets and club nights in the cities we cover.</p>
    <p lang="uk">Концерти, театр, маркети й клубні ночі в містах, які ми охоплюємо.</p></div>
</section>
</main>"""

def h(en, uk, tag="h2"):
    return f'<{tag} lang="en">{en}</{tag}><{tag} lang="uk">{uk}</{tag}>'

def p(en, uk):
    return f'<p lang="en">{en}</p><p lang="uk">{uk}</p>'

def ul(items):
    en = "".join(f"<li>{a}</li>" for a, _ in items)
    uk = "".join(f"<li>{b}</li>" for _, b in items)
    return f'<ul lang="en">{en}</ul><ul lang="uk">{uk}</ul>'

MAIL = f'<a href="mailto:{CONTACT}">{CONTACT}</a>'

PRIVACY = f"""<main class="wrap doc">
{h("Privacy Policy", "Політика приватності", "h1")}
<p class="meta"><span lang="en">Last updated: {UPDATED_EN}</span><span lang="uk">Оновлено: {UPDATED_UK}</span></p>
{p("This policy explains what the Secret Places iOS app (“the app”) collects, why, and the choices you have. The app is operated by SEVEN AM LLC (“we”, “us”).",
   "Ця політика пояснює, які дані збирає iOS-застосунок Secret Places («застосунок»), навіщо, і який у тебе є вибір. Застосунок належить SEVEN AM LLC («ми»).")}
<div class="callout">{p("Short version: you can browse without an account. We don't sell data, don't show ads, don't track you across apps or websites, and don't use third-party analytics.",
   "Коротко: переглядати можна без акаунта. Ми не продаємо дані, не показуємо рекламу, не відстежуємо тебе в інших застосунках і на сайтах і не використовуємо сторонню аналітику.")}</div>

{h("1. Data we collect", "1. Які дані ми збираємо")}
{ul([
 ("<b>Account (only if you sign in).</b> When you use Sign in with Apple we receive an Apple user identifier and, if you choose to share them, your name and email address (which may be an Apple private relay address).",
  "<b>Акаунт (лише якщо ти входиш).</b> Під час входу через Apple ми отримуємо ідентифікатор користувача Apple і, якщо ти погодишся, ім’я та email (це може бути приватна адреса-ретранслятор Apple)."),
 ("<b>Your activity in the app.</b> Places you save, mark as visited or rate, and anything you submit to us. This is linked to your account so it syncs across your devices.",
  "<b>Твоя активність у застосунку.</b> Місця, які ти зберігаєш, позначаєш відвіданими чи оцінюєш, і все, що ти нам надсилаєш. Це прив’язано до акаунта, щоб синхронізуватися між пристроями."),
 ("<b>Purchases.</b> When you unlock a place or route, Apple sends the app a signed transaction. We store the product, transaction identifiers and date to record your unlock. Payment is handled entirely by Apple — we never see your card or payment details.",
  "<b>Покупки.</b> Коли ти відкриваєш місце чи маршрут, Apple передає застосунку підписану транзакцію. Ми зберігаємо продукт, ідентифікатори транзакції та дату, щоб зафіксувати доступ. Оплату повністю обробляє Apple — даних твоєї картки ми не бачимо."),
 ("<b>Location (optional).</b> If you allow it, the app uses your approximate location only while you're using it, to show places near you. It is sent to our server to run that search and is not stored or linked to your account. You can use the app fully without location by choosing a city.",
  "<b>Геолокація (необов’язково).</b> Якщо дозволиш, застосунок використовує твоє приблизне місцезнаходження лише під час роботи, щоб показати місця поруч. Воно передається на сервер для пошуку, не зберігається і не прив’язується до акаунта. Без геолокації застосунком можна повністю користуватися, обравши місто."),
])}

{h("2. How we use it", "2. Як ми це використовуємо")}
{p("Only to provide the app: signing you in, syncing your saves and unlocks, verifying purchases, restoring them on a new device, and answering your support requests. We do not use your data for advertising or profiling.",
   "Лише для роботи застосунку: вхід, синхронізація збережень і покупок, перевірка покупок, їх відновлення на новому пристрої та відповіді на звернення в підтримку. Ми не використовуємо дані для реклами чи профілювання.")}

{h("3. Who processes data for us", "3. Хто обробляє дані від нашого імені")}
{ul([
 ("<b>Supabase</b> — hosts our database, authentication and server functions.", "<b>Supabase</b> — хостинг бази даних, автентифікації та серверних функцій."),
 ("<b>Apple</b> — Sign in with Apple, App Store payments, and Apple Maps for maps in the app.", "<b>Apple</b> — вхід через Apple, оплата в App Store та Apple Maps для мап у застосунку."),
 ("<b>Google</b> — some venue photos are loaded directly from Google's servers, which can see your device's IP address when an image loads.", "<b>Google</b> — частина фото закладів завантажується безпосередньо із серверів Google, які бачать IP-адресу пристрою під час завантаження зображення."),
])}
{p("We don't sell or share your personal data with anyone else, except where required by law.", "Ми не продаємо і не передаємо твої персональні дані іншим, окрім випадків, які вимагає закон.")}

{h("4. On your device", "4. На твоєму пристрої")}
{p("Your sign-in session is stored in the iOS Keychain. Place data may be cached on the device for offline use; you can clear it in the app.",
   "Сесія входу зберігається в Keychain iOS. Дані про місця можуть кешуватися на пристрої для роботи офлайн; кеш можна очистити в застосунку.")}

{h("5. Retention and deletion", "5. Зберігання та видалення")}
{p("We keep your account data until you delete your account. You can do this at any time in the app: <b>Profile → Delete account</b>. This permanently removes your profile, saves, visits, ratings, submissions and unlock records from our database. Apple keeps its own record of your purchases, so you can still restore them later with a new account. You can also ask us to delete your data by email.",
   "Ми зберігаємо дані акаунта, доки ти його не видалиш. Зробити це можна будь-коли в застосунку: <b>Профіль → Видалити акаунт</b>. Це остаточно видаляє профіль, збереження, відвідування, оцінки, надіслані матеріали й записи про покупки з нашої бази. Apple зберігає власний запис про покупки, тож пізніше їх можна відновити з новим акаунтом. Також можна попросити нас видалити дані електронною поштою.")}

{h("6. Your rights", "6. Твої права")}
{p(f"Depending on where you live (including under the GDPR), you can ask to access, correct, export or delete your personal data, or object to its processing. Email us at {MAIL} and we'll respond within 30 days. You can also complain to your local data protection authority.",
   f"Залежно від країни проживання (зокрема за GDPR) ти можеш вимагати доступу до своїх даних, їх виправлення, експорту чи видалення, або заперечити проти обробки. Напиши на {MAIL} — ми відповімо протягом 30 днів. Також можна звернутися до місцевого органу із захисту даних.")}

{h("7. Children", "7. Діти")}
{p("The app is not directed at children under 13, and we don't knowingly collect their data.", "Застосунок не призначений для дітей до 13 років, і ми свідомо не збираємо їхніх даних.")}

{h("8. Changes", "8. Зміни")}
{p("If we change this policy, we'll update the date above and, for significant changes, let you know in the app.", "Якщо ми змінимо політику, то оновимо дату вище, а про суттєві зміни повідомимо в застосунку.")}

{h("9. Contact", "9. Контакти")}
{p(f"SEVEN AM LLC — {MAIL}", f"SEVEN AM LLC — {MAIL}")}
</main>"""

SUPPORT = f"""<main class="wrap doc">
{h("Support", "Підтримка", "h1")}
{p(f"Questions, a place that's closed or moved, or a problem with a purchase? Email {MAIL} — we usually reply within 1–2 business days.",
   f"Питання, місце закрилося чи переїхало, або проблема з покупкою? Пиши на {MAIL} — зазвичай відповідаємо протягом 1–2 робочих днів.")}

{h("Common questions", "Часті питання")}
<details><summary><span lang="en">I paid but the place is still locked</span><span lang="uk">Я заплатив, але місце досі закрите</span></summary>
{p("Make sure you're signed in, then open <b>Profile → Restore purchases</b>. If you were offline when buying, this re-syncs the unlock. Still locked? Email us with the place name and the date of purchase.",
   "Переконайся, що ти увійшов в акаунт, і відкрий <b>Профіль → Відновити покупки</b>. Якщо під час покупки не було інтернету, це повторно синхронізує доступ. Досі закрито? Напиши нам назву місця й дату покупки.")}</details>
<details><summary><span lang="en">How do I restore purchases on a new iPhone?</span><span lang="uk">Як відновити покупки на новому iPhone?</span></summary>
{p("Sign in with the same Apple ID, then tap <b>Profile → Restore purchases</b>.", "Увійди з тим самим Apple ID і натисни <b>Профіль → Відновити покупки</b>.")}</details>
<details><summary><span lang="en">How do I get a refund?</span><span lang="uk">Як повернути кошти?</span></summary>
{p('Purchases are processed by Apple, so refunds are requested from Apple at <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.',
   'Покупки обробляє Apple, тому повернення коштів оформлюється через Apple на <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.')}</details>
<details><summary><span lang="en">Do I need to share my location?</span><span lang="uk">Чи обов’язково ділитися геолокацією?</span></summary>
{p("No. Location only powers “near me”. You can browse everything by choosing a city.", "Ні. Геолокація потрібна лише для пошуку «поруч». Усе можна переглядати, обравши місто.")}</details>
<details><summary><span lang="en">How do I delete my account?</span><span lang="uk">Як видалити акаунт?</span></summary>
{p('In the app go to <b>Profile → Delete account</b>. Your data is removed permanently. See the <a href="/privacy">Privacy Policy</a> for details.',
   'У застосунку відкрий <b>Профіль → Видалити акаунт</b>. Дані видаляються остаточно. Подробиці — у <a href="/privacy">Політиці приватності</a>.')}</details>
<details><summary><span lang="en">A place is closed, moved or wrong</span><span lang="uk">Місце закрилося, переїхало чи вказане неправильно</span></summary>
{p(f"Thank you — tell us at {MAIL} with the place name and what changed. We check every report.", f"Дякуємо! Напиши на {MAIL} назву місця й що змінилося. Ми перевіряємо кожне повідомлення.")}</details>
</main>"""

pages = {
  "index.html": page("index", "Secret Places — hidden spots, revealed", "Secret Places — приховані місця",
                     "Hidden courtyards, unmarked bars, quiet viewpoints and underground nights, curated by locals.", INDEX),
  "privacy/index.html": page("privacy", "Privacy Policy — Secret Places", "Політика приватності — Secret Places",
                       "How the Secret Places app handles your data.", PRIVACY),
  "support/index.html": page("support", "Support — Secret Places", "Підтримка — Secret Places",
                       "Help with Secret Places: purchases, restore, account deletion and contact.", SUPPORT),
}
for name, html in pages.items():
    out = HERE / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
print("wrote", ", ".join(pages))
