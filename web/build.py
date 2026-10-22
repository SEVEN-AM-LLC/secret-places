#!/usr/bin/env python3
"""Generates the static site (index / privacy / support) with a shared header & footer.
Run: python3 build.py  — writes the .html files next to this script."""
from pathlib import Path

HERE = Path(__file__).parent
CONTACT = "hello@7am.agency"
UPDATED_EN, UPDATED_UK = "22 October 2026", "22 жовтня 2026"

def page(slug, title_en, title_uk, desc, body):
    nav = [("index", "Home", "Головна", "/"), ("privacy", "Privacy", "Приватність", "/privacy"), ("support", "Support", "Підтримка", "/support"), ("terms", "Terms", "Умови", "/terms")]
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
  <span>© 2026 SEVEN AM LLC · <span lang="en">Place data © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a> (ODbL) · Photos from <a href="https://commons.wikimedia.org/">Wikimedia Commons</a>, credited in the app</span><span lang="uk">Дані про місця © <a href="https://www.openstreetmap.org/copyright">учасники OpenStreetMap</a> (ODbL) · Фото з <a href="https://commons.wikimedia.org/">Wikimedia Commons</a>, з авторством у застосунку</span></span>
  <span><a href="/privacy"><span lang="en">Privacy Policy</span><span lang="uk">Політика приватності</span></a> · <a href="/support"><span lang="en">Support</span><span lang="uk">Підтримка</span></a> · <a href="/terms"><span lang="en">Terms of Use</span><span lang="uk">Умови використання</span></a> · <a href="mailto:{CONTACT}">{CONTACT}</a></span>
</div></footer>
</body>
</html>
"""

INDEX = f"""<main class="wrap">
<section class="hero">
  <img class="icon" src="/icon-512.png" alt="Secret Places app icon">
  <h1 lang="en">Lesser-known places, on open map data</h1>
  <h1 lang="uk">Менш відомі місця на відкритих картографічних даних</h1>
  <p class="lede" lang="en">Secret Places is a guide to lesser-known bars, rooftops and viewpoints, built on open map data.</p>
  <p class="lede" lang="uk">Secret Places — це путівник менш відомими барами, дахами й оглядовими майданчиками, створений на відкритих картографічних даних.</p>
  <p class="badge" role="status"><span lang="en">Secret Places is on pause while we rework it, and is not currently available in the App Store.</span><span lang="uk">Secret Places на паузі, поки ми його переробляємо, і зараз недоступний в App Store.</span></p>
</section>
<section class="features">
  <div class="card"><span class="ic">🗺️</span>
    <h3 lang="en">Built on OpenStreetMap</h3><h3 lang="uk">На основі OpenStreetMap</h3>
    <p lang="en">Names, locations, addresses and opening hours come from OpenStreetMap open data. Short descriptions are generated automatically from that data.</p>
    <p lang="uk">Назви, розташування, адреси й години роботи взято з відкритих даних OpenStreetMap. Короткі описи створюються з цих даних автоматично.</p></div>
  <div class="card"><span class="ic">🗝️</span>
    <h3 lang="en">Teasers first</h3><h3 lang="uk">Спершу тизери</h3>
    <p lang="en">Browse teasers for free. Some places and routes are unlocked with a one-time in-app purchase to see the exact spot and directions.</p>
    <p lang="uk">Тизери переглядай безкоштовно. Деякі місця й маршрути відкриваються разовою покупкою в застосунку — тоді видно точне місце й маршрут.</p></div>
  <div class="card"><span class="ic">📷</span>
    <h3 lang="en">Openly licensed photos</h3><h3 lang="uk">Фото з відкритими ліцензіями</h3>
    <p lang="en">Many photos come from Wikimedia Commons. Each one shows its author and licence in the app.</p>
    <p lang="uk">Багато фото взято з Wikimedia Commons. Кожне показує автора й ліцензію в застосунку.</p></div>
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
 ("<b>Searches.</b> What you type into search is sent to our server to find places. Our server logs can keep it for a short time; it is not linked to your account.",
  "<b>Пошук.</b> Те, що ти вводиш у пошук, надсилається на наш сервер, щоб знайти місця. Журнали сервера можуть недовго це зберігати; до акаунта воно не прив’язується."),
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
 ("<b>Wikimedia Commons</b> — many place photos are loaded directly from Wikimedia's servers (Wikimedia Foundation), which can see your device's IP address when an image loads. See the <a href=\"https://foundation.wikimedia.org/wiki/Policy:Privacy_policy\">Wikimedia privacy policy</a>.", "<b>Wikimedia Commons</b> — багато фото місць завантажується безпосередньо із серверів Wikimedia (Wikimedia Foundation), які бачать IP-адресу пристрою під час завантаження зображення. Див. <a href=\"https://foundation.wikimedia.org/wiki/Policy:Privacy_policy\">політику приватності Wikimedia</a>."),
 ("<b>Google</b> — some venue photos are loaded directly from Google's servers, which can see your device's IP address when an image loads.", "<b>Google</b> — частина фото закладів завантажується безпосередньо із серверів Google, які бачать IP-адресу пристрою під час завантаження зображення."),
])}
{p("We don't sell or share your personal data with anyone else, except where required by law.", "Ми не продаємо і не передаємо твої персональні дані іншим, окрім випадків, які вимагає закон.")}

{h("Where place data comes from", "Звідки дані про місця")}
{p('Place data (names, locations, addresses, opening hours, websites) is © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>, available under the Open Database License (ODbL). Place descriptions are generated automatically from that data. Photos marked © are from <a href="https://commons.wikimedia.org/">Wikimedia Commons</a>; each shows its author and licence in the app. Awards come from Wikidata.',
   'Дані про місця (назви, розташування, адреси, години роботи, сайти) © <a href="https://www.openstreetmap.org/copyright">учасники OpenStreetMap</a>, доступні за ліцензією Open Database License (ODbL). Описи місць створюються з цих даних автоматично. Фото з позначкою © взято з <a href="https://commons.wikimedia.org/">Wikimedia Commons</a>; кожне показує автора й ліцензію в застосунку. Нагороди взято з Wikidata.')}

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

TERMS = f"""<main class="wrap doc">
{h("Terms of Use", "Умови використання", "h1")}
<p class="meta"><span lang="en">Last updated: {UPDATED_EN}</span><span lang="uk">Оновлено: {UPDATED_UK}</span></p>
{p('Secret Places is an iOS app operated by SEVEN AM LLC (“we”). It is licensed to you under Apple’s <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Licensed Application End User License Agreement</a> (the Standard EULA), together with these terms.',
   'Secret Places — iOS-застосунок SEVEN AM LLC («ми»). Він надається тобі за <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">стандартною ліцензійною угодою Apple</a> (Standard EULA) разом із цими умовами.')}
{p("Secret Places is on pause while we rework it and is not currently available in the App Store.", "Secret Places на паузі, поки ми його переробляємо, і зараз недоступний в App Store.")}

{h("1. In-app purchases", "1. Покупки в застосунку")}
{p('Some places, routes and city passes are unlocked with one-time, non-consumable in-app purchases processed by Apple. They are not subscriptions: nothing renews and nothing is charged again. Prices are shown in the App Store in your currency before you buy. To restore purchases on a new device, sign in and open <b>Profile → Restore purchases</b>. Refunds are handled by Apple at <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.',
   'Деякі місця, маршрути й міські пропуски відкриваються разовими (non-consumable) покупками в застосунку, які обробляє Apple. Це не підписки: нічого не поновлюється і повторно не списується. Ціну видно в App Store у твоїй валюті до покупки. Щоб відновити покупки на новому пристрої, увійди й відкрий <b>Профіль → Відновити покупки</b>. Повернення коштів обробляє Apple на <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.')}

{h("2. Place information", "2. Інформація про місця")}
{p('Place data comes from OpenStreetMap (© OpenStreetMap contributors, ODbL) and descriptions are generated automatically. Places can close, move or change their hours, so check before you go. Follow local laws and the rules of each venue. Photos from Wikimedia Commons remain under their authors’ licences.',
   'Дані про місця взято з OpenStreetMap (© учасники OpenStreetMap, ODbL), а описи створюються автоматично. Місця можуть закритися, переїхати чи змінити години роботи, тож перевіряй перед виходом. Дотримуйся місцевих законів і правил кожного закладу. Фото з Wikimedia Commons лишаються під ліцензіями їхніх авторів.')}

{h("3. Your account", "3. Твій акаунт")}
{p('An account is optional and uses Sign in with Apple. You can delete it at any time in <b>Profile → Delete account</b>. See the <a href="/privacy">Privacy Policy</a>.',
   'Акаунт необов’язковий і використовує вхід через Apple. Видалити його можна будь-коли в <b>Профіль → Видалити акаунт</b>. Див. <a href="/privacy">Політику приватності</a>.')}

{h("4. Acceptable use", "4. Допустиме використання")}
{p("Use the app lawfully. Don't copy its content in bulk, resell it, reverse engineer the app or interfere with its service.",
   "Користуйся застосунком законно. Не копіюй його вміст масово, не перепродавай, не здійснюй зворотну розробку і не заважай роботі сервісу.")}

{h("5. Disclaimer", "5. Відмова від відповідальності")}
{p("The app is provided “as is”. To the extent permitted by law, we are not liable for indirect or consequential damages arising from its use, or for the accuracy of place information.",
   "Застосунок надається «як є». У межах, дозволених законом, ми не відповідаємо за непрямі чи похідні збитки від його використання або за точність інформації про місця.")}

{h("6. Contact", "6. Контакти")}
{p(f"SEVEN AM LLC — {MAIL}", f"SEVEN AM LLC — {MAIL}")}
</main>"""

pages = {
  "index.html": page("index", "Secret Places — lesser-known places on open map data", "Secret Places — менш відомі місця на відкритих даних",
                     "A guide to lesser-known bars, rooftops and viewpoints, built on OpenStreetMap open data. On pause while we rework it.", INDEX),
  "privacy/index.html": page("privacy", "Privacy Policy — Secret Places", "Політика приватності — Secret Places",
                       "How the Secret Places app handles your data.", PRIVACY),
  "support/index.html": page("support", "Support — Secret Places", "Підтримка — Secret Places",
                       "Help with Secret Places: purchases, restore, account deletion and contact.", SUPPORT),
  "terms/index.html": page("terms", "Terms of Use — Secret Places", "Умови використання — Secret Places",
                       "Terms of use and in-app purchase terms for Secret Places.", TERMS),
}
for name, html in pages.items():
    out = HERE / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
print("wrote", ", ".join(pages))
