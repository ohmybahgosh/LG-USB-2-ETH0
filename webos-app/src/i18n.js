/*
 * The app's translations.  Each language maps the English text to its own;
 * anything missing shows in English, so a half-done language still works.
 * {name} is filled in by T(text, { name: value }).
 *
 * The language is the TV's menu language (the web runtime's locale), unless
 * one was picked with the Language row, which is kept in the app's own
 * storage.  Only the app's own words are translated: what the script prints,
 * and the GitHub report fields (which must match the form's choices), stay
 * in English.
 *
 * Adding a language: copy the ru block, translate the values, and add it to
 * NAMES.  tests/check-i18n.js checks that every text app.js and index.html
 * use is translated.
 */
(function () {
    'use strict';

    var NAMES = { en: 'English', ru: 'Русский' };

    var ru = {
        // index.html
        'Loading…': 'Загрузка…',
        'Checking the TV…': 'Проверяю телевизор…',
        'Reading the network setup.': 'Читаю настройки сети.',
        'Upgrade from v1': 'Обновление с v1',
        'replaces the old boot hook, step by step': 'заменяет старый загрузочный хук, шаг за шагом',
        'Update': 'Обновить',
        'Run at every boot': 'Запуск при каждом включении',
        'Faster driver': 'Быстрый драйвер',
        'Realtek mode': 'Режим Realtek',
        'uses the TV\'s own Realtek driver': 'встроенный драйвер Realtek телевизора',
        'Test a new driver': 'Проверить новый драйвер',
        'Follow plug and unplug': 'Следить за подключением',
        'from the next boot': 'со следующего включения',
        'Wi-Fi as a backup': 'Wi-Fi как резерв',
        'if the cable stops working': 'если кабель перестанет работать',
        'Block updates harder': 'Усиленная блокировка обновлений',
        'on top of the Homebrew Channel\'s block': 'в дополнение к блокировке Homebrew Channel',
        'Switch now': 'Переключить сейчас',
        'applies without a reboot': 'без перезагрузки',
        'Speed test': 'Тест скорости',
        'through Cloudflare': 'через Cloudflare',
        'Report for GitHub': 'Отчёт для GitHub',
        'shows a QR code': 'показывает QR-код',
        'Language': 'Язык',
        'Turn everything off': 'Выключить всё',
        'back to the built-in port': 'вернуть встроенный порт',
        'Select': 'Выбор',
        'Move': 'Вверх/вниз',
        'Exit': 'Выход',

        // Language row
        'Auto ({lang})': 'Авто ({lang})',

        // Status
        'The script gave an unexpected answer.': 'Скрипт ответил что-то непонятное.',
        'eth0 is connected at {ip}.  Press OK or BACK to close.': 'eth0 подключён, адрес {ip}.  Нажмите OK или НАЗАД, чтобы закрыть.',
        'Waiting for eth0 to get an address…  Press OK or BACK to close.': 'Жду, пока eth0 получит адрес…  Нажмите OK или НАЗАД, чтобы закрыть.',
        'eth0 has no address after 40 seconds.  Check the cable and the router.  Press OK or BACK to close.': 'eth0 не получил адрес за 40 секунд.  Проверьте кабель и роутер.  Нажмите OK или НАЗАД, чтобы закрыть.',
        'Can\'t reach the TV as root': 'Нет root-доступа к телевизору',
        'This app needs a rooted TV with the Homebrew Channel.  ': 'Приложению нужен телевизор с root-доступом и Homebrew Channel.  ',
        'USB adapter is eth0': 'USB-адаптер работает как eth0',
        'Traffic is going over the adapter.': 'Трафик идёт через адаптер.',
        'Traffic is going out {route}, not the adapter.': 'Трафик идёт через {route}, а не через адаптер.',
        'nowhere': 'никуда',
        'Adapter found, not eth0 yet': 'Адаптер найден, но ещё не eth0',
        'Choose Switch now, or reboot.': 'Выберите «Переключить сейчас» или перезагрузите телевизор.',
        'Turn on Run at every boot, or choose Switch now.': 'Включите «Запуск при каждом включении» или выберите «Переключить сейчас».',
        'No USB adapter found': 'USB-адаптер не найден',
        'Plug in a USB Ethernet adapter.  The built-in port keeps working meanwhile.': 'Подключите USB-Ethernet адаптер.  Пока что работает встроенный порт.',
        'An old v1 boot hook is installed.  Choose Upgrade from v1 to replace it, step by step.': 'Установлен старый загрузочный хук v1.  Выберите «Обновление с v1», чтобы заменить его.',
        '  No problems found.': '  Проблем не найдено.',
        'Adapter': 'Адаптер',
        'Link': 'Связь',
        'up': 'есть',
        'no cable': 'нет кабеля',
        ', half duplex': ', полудуплекс',
        'Address': 'Адрес',
        'none yet': 'пока нет',
        'none': 'нет',
        'Wi-Fi backup': 'Резерв Wi-Fi',
        'on, the cable has no link': 'включён, у кабеля нет связи',
        'Speed': 'Скорость',
        '{down} down · {up} up Mbit/s': '{down} приём · {up} передача Мбит/с',
        'Built-in port': 'Встроенный порт',
        'cable in': 'кабель подключён',
        'connected': 'подключён',
        'off': 'выкл.',
        'on': 'вкл.',
        'off (disabled)': 'выкл. (отключён)',
        'broken link': 'ссылка повреждена',
        'old v1 hook': 'старый хук v1',
        'At boot': 'При включении',
        ' · running': ' · работает',
        'Last log': 'Последняя запись',
        'your adapter is on the TV\'s own r8152': 'адаптер работает на встроенном r8152',
        'r8152 didn\'t take your adapter': 'r8152 не подхватил адаптер',
        'also covers the Homebrew Channel\'s block, which is off': 'заменяет блокировку Homebrew Channel, которая выключена',
        'the Homebrew Channel\'s block is off too': 'блокировка Homebrew Channel тоже выключена',
        'built for this TV\'s kernel': 'собран для ядра этого телевизора',
        'custom module': 'свой модуль',
        'built for an older kernel, not loaded': 'собран для старого ядра, не загружен',
        'firmware updated, a driver for the new kernel is ready': 'прошивка обновилась, есть драйвер для нового ядра',
        'file changed, not loaded': 'файл изменён, не загружен',
        'module file is missing': 'файла модуля нет',
        'testing now': 'идёт проверка',
        'last test: {result}': 'последняя проверка: {result}',
        'built for this TV\'s kernel, helps add support': 'собран для ядра этого ТВ, поможет добавить поддержку',
        'plug in an adapter it supports to try it': 'подключите поддерживаемый адаптер, чтобы проверить',
        'Update to v{v}': 'Обновить до v{v}',
        'opens the Homebrew Channel': 'откроет Homebrew Channel',
        'you have v{v}, downloads and installs': 'у вас v{v}, скачает и установит',

        // Overlays
        'Working on it…  The picture is fine, only the network is changing.': 'Выполняю…  С изображением всё в порядке, меняется только сеть.',
        '{title}: done': '{title}: готово',
        '{title}: something went wrong': '{title}: что-то пошло не так',
        'Press OK or BACK to close.': 'Нажмите OK или НАЗАД, чтобы закрыть.',
        'Fixed': 'Исправлено',
        'Added': 'Добавлено',
        'Changed': 'Изменено',
        'Updated to v{v}: what\'s new': 'Обновлено до v{v}: что нового',
        'Press OK or BACK to close.  Full notes: github.com/ohmybahgosh/LG-USB-2-ETH0/releases': 'Нажмите OK или НАЗАД, чтобы закрыть.  Подробно (на английском): github.com/ohmybahgosh/LG-USB-2-ETH0/releases',
        'Press OK to go ahead, or BACK to cancel.': 'Нажмите OK, чтобы продолжить, или НАЗАД для отмены.',

        // Upgrade from v1
        'Step 3 of 3 · upgrading': 'Шаг 3 из 3 · обновление',
        'Replacing the boot hook…': 'Заменяю загрузочный хук…',
        'The boot hook is this version\'s now: {link}': 'Загрузочный хук теперь от этой версии: {link}',
        'The boot hook isn\'t this version\'s yet.': 'Загрузочный хук ещё не от этой версии.',
        'The old v1 file is gone.': 'Старый файл v1 удалён.',
        'The old v1 file is still there.': 'Старый файл v1 всё ещё на месте.',
        'Your USB adapter is still {eth0}.': 'USB-адаптер по-прежнему {eth0}.',
        'The adapter becomes {eth0} at the next boot, or choose Switch now.': 'Адаптер станет {eth0} при следующем включении, или выберите «Переключить сейчас».',
        'Run at every boot is on.  Your settings are in {file}.': '«Запуск при каждом включении» включён.  Настройки хранятся в {file}.',
        'Upgrade from v1: done': 'Обновление с v1: готово',
        'Upgrade from v1: something went wrong': 'Обновление с v1: что-то пошло не так',
        'Step 3 of 3 · all done': 'Шаг 3 из 3 · всё готово',
        'Step 3 of 3 · check this': 'Шаг 3 из 3 · проверьте',
        'Press OK or BACK to close.  Nothing else to do.': 'Нажмите OK или НАЗАД, чтобы закрыть.  Больше ничего делать не нужно.',
        'Press OK or BACK to close.  Report for GitHub makes a report you can send.': 'Нажмите OK или НАЗАД, чтобы закрыть.  «Отчёт для GitHub» соберёт отчёт, который можно отправить.',
        'A v1 boot hook you turned off is still in the boot folder, as {file}.  On many TVs that file still runs at every boot.': 'Отключённый вами хук v1 всё ещё лежит в папке автозапуска как {file}.  На многих телевизорах этот файл всё равно запускается при каждом включении.',
        'The v1 boot hook is installed, at {file}.  It runs at every boot and renames {eth0} even when no adapter is plugged in.': 'Установлен хук v1: {file}.  Он запускается при каждом включении и переименовывает {eth0}, даже когда адаптер не подключён.',
        'Your USB adapter is {eth0} right now.': 'Сейчас USB-адаптер работает как {eth0}.',
        'Your USB adapter is plugged in, as {name}.': 'USB-адаптер подключён как {name}.',
        'No USB adapter is plugged in right now.': 'Сейчас USB-адаптер не подключён.',
        'Step 1 of 3 · what\'s there now': 'Шаг 1 из 3 · что установлено сейчас',
        'The upgrade takes a few seconds and doesn\'t touch the network.': 'Обновление займёт несколько секунд и не затронет сеть.',
        'Press OK to see what changes, or BACK to cancel.': 'Нажмите OK, чтобы увидеть изменения, или НАЗАД для отмены.',
        'Step 2 of 3 · what changes': 'Шаг 2 из 3 · что изменится',
        'The v1 hook is replaced, in place, by this version\'s: a link to the script inside this app, so updating the app updates the hook too.': 'Хук v1 заменяется на месте хуком этой версии: ссылкой на скрипт внутри приложения, так что при обновлении приложения обновится и хук.',
        'Nothing switches now.  The adapter stays as it is until the next boot.': 'Сейчас ничего не переключается.  Адаптер остаётся как есть до следующего включения.',
        'At boot, the new hook only changes anything when an adapter is plugged in, and puts the old names back if a step fails.': 'При включении новый хук что-то меняет, только если адаптер подключён, и возвращает старые имена, если какой-то шаг не удался.',
        'It starts with the defaults.  Turn on Faster driver, Follow plug and unplug or Wi-Fi as a backup afterwards if you want them.': 'Сначала всё по умолчанию.  Потом при желании включите «Быстрый драйвер», «Следить за подключением» или «Wi-Fi как резерв».',
        'This turns the boot hook on.  Prefer it off?  Turn off Run at every boot afterwards.': 'Это включит загрузочный хук.  Нужно выключить?  Потом отключите «Запуск при каждом включении».',
        'To undo everything later, use Turn everything off.': 'Чтобы потом всё отменить, выберите «Выключить всё».',
        'Press OK to upgrade, or BACK to cancel.': 'Нажмите OK, чтобы обновить, или НАЗАД для отмены.',

        // Driver test
        'it works': 'работает',
        'link, but not online': 'связь есть, интернета нет',
        'no cable link': 'нет связи по кабелю',
        'adapter didn\'t move to it': 'адаптер не перешёл на него',
        'didn\'t load': 'не загрузился',
        'the TV restarted': 'телевизор перезагрузился',
        'It works!  ': 'Работает!  ',
        'The TV restarted during the test, so this driver doesn\'t fit as it is.  ': 'Во время проверки телевизор перезагрузился, значит этот драйвер в таком виде не подходит.  ',
        'Scan this with your phone to send the result on GitHub, already filled in.  Every result helps, good or bad.  MAC and IP addresses are left out.': 'Отсканируйте телефоном, чтобы отправить уже заполненный результат на GitHub.  Полезен любой результат, хороший или плохой.  MAC- и IP-адреса не включаются.',
        'Driver test: {result}': 'Проверка драйвера: {result}',
        'Press OK to test again, or BACK to close.': 'Нажмите OK, чтобы проверить ещё раз, или НАЗАД, чтобы закрыть.',
        'Press OK or BACK to close.  The driver stays in use until the next restart.': 'Нажмите OK или НАЗАД, чтобы закрыть.  Драйвер работает до следующей перезагрузки.',
        'There\'s a driver built for this TV\'s kernel from LG\'s own source, and nobody with this kernel has tried it yet.': 'Есть драйвер, собранный из исходников LG для ядра этого телевизора, и его ещё никто с таким ядром не пробовал.',
        'There\'s a driver built for this TV\'s kernel from LG\'s own source, so your adapter could work, and nobody with this kernel has tried it yet.': 'Есть драйвер, собранный из исходников LG для ядра этого телевизора, так что ваш адаптер может заработать, и его ещё никто с таким ядром не пробовал.',
        'Testing it takes a minute: it\'s only loaded until the next restart, and you send the result with your phone.  That\'s how it gets offered to everyone with this TV.': 'Проверка занимает минуту: драйвер загружается только до следующей перезагрузки, а результат вы отправляете с телефона.  Так он становится доступен всем владельцам такого телевизора.',
        'Your adapter is one it supports.': 'Ваш адаптер поддерживается.',
        'Plug in an adapter it supports first: Realtek (RTL8152, RTL8153 or RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 or Microchip LAN78xx, whichever the new driver is for.': 'Сначала подключите поддерживаемый адаптер: Realtek (RTL8152, RTL8153 или RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 или Microchip LAN78xx, смотря для какого чипа новый драйвер.',
        'It stays in the menu as Test a new driver, so you can do it any time.': 'Он остаётся в меню как «Проверить новый драйвер», так что можно сделать это в любой момент.',
        'A new driver to test': 'Новый драйвер для проверки',
        'Press OK to test it now, or BACK for later.': 'Нажмите OK, чтобы проверить сейчас, или НАЗАД, чтобы отложить.',
        'Plug in a USB adapter it supports first: Realtek (RTL8152, RTL8153 or RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 or Microchip LAN78xx, whichever the new driver is for.': 'Сначала подключите поддерживаемый USB-адаптер: Realtek (RTL8152, RTL8153 или RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 или Microchip LAN78xx, смотря для какого чипа новый драйвер.',
        'Test a new driver?': 'Проверить новый драйвер?',
        'There\'s a driver built for this TV\'s kernel from LG\'s own source, that hasn\'t run on a TV with this kernel yet.  The test downloads it, checks its checksum, loads it until the next restart only, moves the adapter to it and checks it gets online.  The network drops for a moment.  If it doesn\'t fit, the TV can freeze or restart: restart it (unplug it if needed) and open the app again to send that result too.': 'Есть драйвер, собранный из исходников LG для ядра этого телевизора, который ещё не запускался на ТВ с таким ядром.  Проверка скачает его, сверит контрольную сумму, загрузит только до следующей перезагрузки, переведёт на него адаптер и проверит выход в интернет.  Сеть на мгновение пропадёт.  Если драйвер не подходит, телевизор может зависнуть или перезагрузиться: перезагрузите его (при необходимости выньте вилку из розетки) и откройте приложение снова, чтобы отправить и этот результат.',
        'Testing the new driver': 'Проверяю новый драйвер',
        'Downloading and checking it, then moving the adapter over.  This takes up to a minute.': 'Скачиваю и проверяю его, затем перевожу адаптер.  Это займёт до минуты.',
        'Driver test: still running': 'Проверка драйвера: ещё идёт',
        'Driver test: didn\'t start': 'Проверка драйвера: не запустилась',

        // Actions
        'Stop running at boot?': 'Не запускать при включении?',
        'The adapter stays eth0 until the next reboot.  After that, the built-in port is eth0 again.': 'Адаптер останется eth0 до следующей перезагрузки.  После неё eth0 снова станет встроенный порт.',
        'Turn off at boot': 'Отключение запуска при включении',
        'Turn on at boot': 'Запуск при включении',
        'Switch to the driver for the new kernel?': 'Перейти на драйвер для нового ядра?',
        'A firmware update changed this TV\'s kernel{change}, so your faster driver isn\'t loaded anymore.  This downloads the one built for the new kernel{by}, checks its checksum, and uses it from now on.  The network drops for a moment while the adapter moves over.': 'Обновление прошивки сменило ядро телевизора{change}, поэтому быстрый драйвер больше не загружается.  Будет скачан драйвер для нового ядра{by}, сверена его контрольная сумма, и дальше будет использоваться он.  Сеть на мгновение пропадёт, пока адаптер переключается.',
        ' (from {old} to {new})': ' (с {old} на {new})',
        ' by {who}': ' от {who}',
        'Driver for the new kernel': 'Драйвер для нового ядра',
        'Stop using the faster driver?': 'Перестать использовать быстрый драйвер?',
        'The boot hook stops loading it.  It stays in use until the next reboot.': 'Загрузочный хук перестанет его загружать.  Он работает до следующей перезагрузки.',
        'Faster driver off': 'Быстрый драйвер выключен',
        'Use the faster driver?': 'Использовать быстрый драйвер?',
        'This downloads a driver module built for this exact TV kernel{by}, checks its checksum, and loads it at every boot.  Moving the adapter to it takes the network down for a moment.  Wi-Fi is a good way back in if anything goes wrong.': 'Будет скачан модуль драйвера, собранный именно для ядра этого телевизора{by}, сверена его контрольная сумма, и он будет загружаться при каждом включении.  При переключении адаптера сеть на мгновение пропадёт.  Если что-то пойдёт не так, Wi-Fi поможет вернуть доступ.',
        ' by {who} ({page})': ' от {who} ({page})',
        'Stop following plug and unplug': 'Не следить за подключением',
        'Turn Realtek mode off?': 'Выключить режим Realtek?',
        'Your Realtek adapter stays on the generic driver, which works but is slower.  It takes effect from the next boot.': 'Адаптер Realtek останется на общем драйвере: работает, но медленнее.  Действует со следующего включения.',
        'Realtek mode off': 'Режим Realtek выключен',
        'Wi-Fi backup off': 'Резерв Wi-Fi выключен',
        'Use Wi-Fi as a backup?': 'Использовать Wi-Fi как резерв?',
        'If eth0 loses its cable link for a minute while Wi-Fi is off, the TV turns Wi-Fi on and joins a network it already knows.  Once the cable works again, Wi-Fi goes back off, so traffic returns to the adapter.  Starts from the next boot.': 'Если у eth0 на минуту пропадёт связь по кабелю, а Wi-Fi выключен, телевизор включит Wi-Fi и подключится к знакомой сети.  Когда кабель снова заработает, Wi-Fi выключится и трафик вернётся на адаптер.  Действует со следующего включения.',
        'Stop blocking updates harder?': 'Отключить усиленную блокировку обновлений?',
        'webOS\'s own update check goes back to how it was, and the extra servers and the firewall rule come off.  The Homebrew Channel\'s Block system updates stays as it is.': 'Собственная проверка обновлений webOS вернётся как была, дополнительные серверы и правило фаервола будут сняты.  Блокировка обновлений в Homebrew Channel останется как есть.',
        'Update blocking off': 'Блокировка обновлений выключена',
        'Block updates harder?': 'Включить усиленную блокировку обновлений?',
        'A firmware update can remove root for good: LG\'s current firmware, webOS 26 from October 2026 on included, can\'t be rooted again.  It turns off webOS\'s own update check, blocks LG\'s update servers (the ones the Homebrew Channel\'s Block system updates covers, if that\'s off, and the ones it misses), and the one the updater reaches by IP.  It starts now and at every boot, and turning it off undoes all of it.': 'Обновление прошивки может навсегда лишить root: текущие прошивки LG, включая webOS 26 с октября 2026 года, рутировать уже нельзя.  Эта функция отключает собственную проверку обновлений webOS, блокирует серверы обновлений LG (те, что закрывает блокировка Homebrew Channel, если она выключена, и те, что она пропускает), а также сервер, к которому прошивальщик обращается по IP.  Работает сразу и при каждом включении, а выключение отменяет всё.',
        'Block updates': 'Блокировка обновлений',
        'Switch now?': 'Переключить сейчас?',
        'The network drops for a few seconds while the adapter becomes eth0.': 'Сеть пропадёт на несколько секунд, пока адаптер становится eth0.',
        'Update to v{v}?': 'Обновить до v{v}?',
        'Downloads the new version from GitHub, checks its SHA-256, and installs it.  The app closes and opens again by itself.  Your settings stay as they are.': 'Новая версия будет скачана с GitHub, проверена по SHA-256 и установлена.  Приложение закроется и откроется само.  Настройки сохранятся.',
        'Updating to v{v}': 'Обновление до v{v}',
        'Checked the download and installing it now.  The app closes and opens again by itself in a few seconds, then shows what\'s new.': 'Загрузка проверена, устанавливаю.  Через несколько секунд приложение закроется и откроется само, а потом покажет, что нового.',

        // Speed test
        'Download': 'Приём',
        'Upload': 'Передача',
        'Latency': 'Задержка',
        'Mbit/s': 'Мбит/с',
        'ms': 'мс',
        'Earlier (down / up Mbit/s, driver):': 'Раньше (приём / передача Мбит/с, драйвер):',
        'Over {nic}, to Cloudflare\'s {server} server.': 'Через {nic}, до сервера Cloudflare {server}.',
        'Over {nic}, to Cloudflare.': 'Через {nic}, до Cloudflare.',
        'Finding the nearest Cloudflare server…': 'Ищу ближайший сервер Cloudflare…',
        'Speed test: {stage}': 'Тест скорости: {stage}',
        'latency': 'задержка',
        'download': 'приём',
        'upload': 'передача',
        '  Uses a few hundred MB of data.': '  Расходует несколько сотен МБ трафика.',
        'This takes about 15 seconds.': 'Это займёт около 15 секунд.',
        'Speed test: something went wrong': 'Тест скорости: что-то пошло не так',
        'No answer from the script.': 'Скрипт не ответил.',

        // Report
        'Scan this with your phone to open a compatibility report on GitHub, already filled in.  It opens in your browser so the details carry over.  Check the result it picked and submit.  MAC addresses are hidden.': 'Отсканируйте телефоном, чтобы открыть уже заполненный отчёт о совместимости на GitHub.  Он откроется в браузере, чтобы данные сохранились.  Проверьте выбранный результат и отправьте.  MAC-адреса скрыты.  Писать можно и по-русски.',
        'Turn everything off?': 'Выключить всё?',
        'This removes the boot hook and gives eth0 back to the built-in port now.  Do this before removing the app.': 'Загрузочный хук будет удалён, а eth0 сразу вернётся встроенному порту.  Сделайте это перед удалением приложения.'
    };


    // The script's status messages (status --json issues and notes), in
    // pieces: a message can be several of these back to back, so each piece
    // is translated where it appears.  Where the English says to run a
    // command, the translation names the app's menu row instead.  Longest
    // first.  tests/check-i18n.js checks every message the script can give.
    var ruScript = [
        [/The driver module is built for kernel (\S+), but the TV now runs (\S+?)(?= \(it was|, probably|\.  |$)/g, 'Модуль драйвера собран для ядра $1, а телевизор сейчас работает на $2'],
        [/ ?\(it was (\S+) when you set it up, so a firmware update changed it\)/g, ' (при настройке было $1, значит его сменило обновление прошивки)'],
        [/, probably after a firmware update/g, ', вероятно, после обновления прошивки'],
        [/\.  It won't be loaded, so the adapter stays on the TV's own driver\./g, '.  Он не будет загружен, поэтому адаптер остаётся на собственном драйвере телевизора.'],
        [/A driver is known for the new kernel and your adapter: run 'get-driver', then 'install --module \S+'\./g, 'Для нового ядра и вашего адаптера есть драйвер: выберите «Быстрый драйвер».'],
        [/There's a new driver to test for this kernel: run 'test-driver'\./g, 'Для этого ядра есть новый драйвер для проверки: выберите «Проверить новый драйвер».'],
        [/No driver is known for this kernel yet\.  Run 'report' and open an issue, so one can be built\./g, 'Для этого ядра пока нет драйвера.  Отправьте «Отчёт для GitHub», чтобы его можно было собрать.'],
        [/A driver is known for this kernel and adapter: run 'get-driver'\./g, 'Для этого ядра и адаптера есть драйвер: выберите «Быстрый драйвер».'],
        [/The hook is a copy from an older version\. Run 'install' to switch it to a link \(your settings are kept\)\./g, 'Загрузочный хук остался копией из старой версии.  Выключите и снова включите «Запуск при каждом включении», чтобы заменить его ссылкой (настройки сохранятся).'],
        [/Run 'install' to replace the v1 hook\./g, 'Выберите «Обновление с v1», чтобы заменить хук v1.'],
        [/Busybox run-parts may still run that file at boot\. Run 'disable' to move it out, or 'install' to upgrade\./g, 'Busybox run-parts может всё равно запускать этот файл при включении.  Выберите «Обновление с v1».'],
        [/The app or script the boot hook used was removed\. Run 'install' to relink it, or 'uninstall'\./g, 'Приложение или скрипт, на который указывал загрузочный хук, удалён.  Включите «Запуск при каждом включении» заново или выберите «Выключить всё».'],
        [/Homebrew Channel not found, so a boot hook would never run\./g, 'Homebrew Channel не найден, поэтому загрузочный хук никогда не запустится.'],
        [/(\S+) runs at USB 1\.1 speed\. Try another port or cable\./g, '$1 работает на скорости USB 1.1.  Попробуйте другой порт или кабель.'],
        [/(\S+) is on USB 2\.0, which tops out around 300 Mbit\/s on these TVs\./g, '$1 подключён по USB 2.0: на этих телевизорах это около 300 Мбит/с максимум.'],
        [/(\S+) has a cable but no IPv4 address yet\. webOS may still be setting it up\./g, 'У $1 есть кабель, но пока нет IPv4-адреса.  Возможно, webOS ещё его настраивает.'],
        [/(\S+)'s cable link is only (\d+) Mbit\/s, so it's no faster than the built-in port\. Usually that's a cable with only two wire pairs \(many flat or old cables\), a 100 Mbit\/s port on the router or switch, or a loose plug\. Try a Cat5e or better cable, or another port\./g,
            'Связь $1 по кабелю всего $2 Мбит/с, это не быстрее встроенного порта.  Обычно виноват кабель только с двумя парами проводов (многие плоские или старые кабели), порт на 100 Мбит/с в роутере или коммутаторе, или плохо вставленный штекер.  Попробуйте кабель Cat5e или лучше, либо другой порт.'],
        [/(\S+)'s cable link is half duplex, which is slow and loses packets\. Try another cable or another port on the router or switch\./g, 'Связь $1 по кабелю в режиме полудуплекса: это медленно и с потерями пакетов.  Попробуйте другой кабель или другой порт роутера или коммутатора.'],
        [/USB adapter (\S+) \((.*?)\) is plugged in, but no driver made a network device for it\./g, 'USB-адаптер $1 ($2) подключён, но ни один драйвер не создал для него сетевое устройство.'],
        [/This kernel \((\S+)\) seems to lack a driver for that chip\. Try an adapter with another chip, or load a module built for this exact kernel with --module\./g, 'Похоже, в этом ядре ($1) нет драйвера для этого чипа.  Попробуйте адаптер с другим чипом, или «Быстрый драйвер» и «Проверить новый драйвер», если они есть в меню.'],
        [/The driver module (\S+) is missing\. Run 'get-driver' and 'install --module' again, or 'install --no-module'\./g, 'Файла модуля драйвера $1 нет.  Выключите «Быстрый драйвер» и включите его снова.'],
        [/The driver module changed since it was installed, so it won't be loaded\. Run 'install' again if you replaced it on purpose\./g, 'Модуль драйвера изменился после установки, поэтому он не будет загружен.  Если вы заменили его сознательно, установите его заново.'],
        [/(\S+) is still on (\S+), not (\S+)\. Run 'apply', or check (\S+?)\.(?=\s|$)/g, '$1 всё ещё на драйвере $2, а не $3.  Выберите «Переключить сейчас» или посмотрите журнал $4.'],
        [/Realtek mode was tried, but the kernel's r8152 didn't take your adapter, so it's back on the generic (\S+) driver\./g, 'Режим Realtek пробовали включить, но r8152 ядра не подхватил адаптер, поэтому он снова на общем драйвере $1.'],
        [/This kernel has r8152, but your Realtek adapter is in its standard USB mode, where only the generic (\S+) driver can use it\./g, 'В этом ядре есть r8152, но адаптер Realtek работает в стандартном режиме USB, где его может использовать только общий драйвер $1.'],
        [/Realtek mode switches it over: install --realtek-mode, then apply\./g, 'Режим Realtek переключит его: включите «Режим Realtek», затем «Переключить сейчас».'],
        [/Run 'apply' \(or reboot\) and Realtek mode switches it over\./g, 'Выберите «Переключить сейчас» (или перезагрузите телевизор), и режим Realtek переключит его.'],
        [/(\S+) uses the generic (\S+) driver\. A better driver is known for this kernel and adapter: run 'get-driver'\./g, '$1 работает на общем драйвере $2.  Для этого ядра и адаптера есть драйвер получше: выберите «Быстрый драйвер».'],
        [/This kernel only loads drivers signed by LG \(the 2026 models' webOS 26 kernels enforce it\), so no added driver can load here\.  Only the TV's built-in drivers work\./g, 'Это ядро загружает только драйверы, подписанные LG (так работают ядра webOS 26 у моделей 2026 года), поэтому добавленный драйвер здесь не загрузится.  Работают только встроенные драйверы телевизора.'],
        [/Your adapter has no driver on this TV, but one is known for this kernel and adapter: run 'get-driver'\./g, 'Для вашего адаптера на этом телевизоре нет драйвера, но для этого ядра и адаптера он есть: выберите «Быстрый драйвер».'],
        [/DonZoomik's r8152-autobind hook and --module both manage the driver\. Keep one: /g, 'Драйвером управляют сразу хук r8152-autobind от DonZoomik и «Быстрый драйвер».  Оставьте что-то одно: '],
        [/DonZoomik's r8152-autobind hook is installed\. 'install --module' can do the same job inside LG-USB-2-ETH0\./g, 'Установлен хук r8152-autobind от DonZoomik.  «Быстрый драйвер» в LG-USB-2-ETH0 делает то же самое.'],
        [/The hook is on, but no adapter is visible now, so a boot right now would change nothing\./g, 'Хук включён, но адаптер сейчас не виден, поэтому включение прямо сейчас ничего бы не изменило.'],
        [/The adapter is (\S+), not eth0 yet\. Reboot, run 'apply', or check (\S+?)\.(?=\s|$)/g, 'Адаптер пока $1, а не eth0.  Перезагрузите телевизор, выберите «Переключить сейчас» или посмотрите журнал $2.'],
        [/Traffic goes out (\S+), not the adapter\. webOS prefers Wi-Fi while it's connected: turn Wi-Fi off in the TV's settings, or unplug and replug the network cable\./g, 'Трафик идёт через $1, а не через адаптер.  Пока Wi-Fi подключён, webOS предпочитает его: выключите Wi-Fi в настройках телевизора или выньте и снова вставьте сетевой кабель.'],
        [/The Homebrew Channel blocks four of LG's update servers, but misses others\.  install --block-updates closes the rest\./g, 'Homebrew Channel блокирует четыре сервера обновлений LG, но пропускает другие.  «Усиленная блокировка обновлений» закроет остальные.'],
        [/Firmware updates aren't blocked\.  An update can remove root for good: install with --block-updates, or turn on Block system updates in the Homebrew Channel\./g, 'Обновления прошивки не заблокированы.  Обновление может навсегда лишить root: включите «Усиленную блокировку обновлений» или Block system updates в Homebrew Channel.'],
        [/The Wi-Fi fallback turned Wi-Fi on because eth0 lost its cable link\.  It turns Wi-Fi off again once the cable works for (\d+)s\./g, 'Резерв Wi-Fi включил Wi-Fi, потому что у eth0 пропала связь по кабелю.  Wi-Fi снова выключится, когда кабель проработает $1 с.'],
        [/Both wired ports have a cable\. Unplug the built-in one, or traffic may take the slower port\./g, 'Кабель подключён к обоим проводным портам.  Выньте кабель из встроенного, иначе трафик может пойти через более медленный порт.'],
        // The app's own errors, when the Homebrew Channel doesn't answer
        [/^Not running on a webOS TV$/g, 'Приложение запущено не на телевизоре webOS'],
        [/^Unreadable reply$/g, 'Непонятный ответ']
    ];
    var SCRIPTS = { ru: ruScript };
    var DICTS = { ru: ru };
    var KEY = 'lgu2e.lang';

    function stored() {
        try { return window.localStorage.getItem(KEY) || 'auto'; } catch (e) { return 'auto'; }
    }
    // The TV's menu language, as the web runtime has it (like ru-RU)
    function tvLang() {
        var l = '';
        try {
            l = (window.webOSSystem && window.webOSSystem.locale) || (window.PalmSystem && window.PalmSystem.locale) ||
                navigator.language || (navigator.languages && navigator.languages[0]) || '';
        } catch (e) { l = ''; }
        l = String(l).toLowerCase().slice(0, 2);
        return DICTS[l] ? l : 'en';
    }
    var choice = stored();
    if (choice !== 'auto' && choice !== 'en' && !DICTS[choice]) { choice = 'auto'; }
    var lang = choice === 'auto' ? tvLang() : choice;
    var dict = DICTS[lang] || {};

    function T(text, vars) {
        var s = Object.prototype.hasOwnProperty.call(dict, text) ? dict[text] : text;
        if (vars) {
            s = s.replace(/\{(\w+)\}/g, function (m, k) { return Object.prototype.hasOwnProperty.call(vars, k) ? vars[k] : m; });
        }
        return s;
    }

    // A message from the script (or a system error), translated piece by
    // piece; English where no piece matches
    function TS(msg) {
        var pats = SCRIPTS[lang];
        if (!pats || typeof msg !== 'string') { return msg; }
        for (var i = 0; i < pats.length; i++) { msg = msg.replace(pats[i][0], pats[i][1]); }
        return msg;
    }

    // Translate the page's own text (index.html), keeping the spacing
    function translatePage(root) {
        if (lang === 'en') { return; }
        var walker = document.createTreeWalker(root, 4 /* text */, null, false);
        var n;
        while ((n = walker.nextNode())) {
            var t = n.nodeValue.replace(/^\s+|\s+$/g, '');
            if (t && Object.prototype.hasOwnProperty.call(dict, t)) {
                n.nodeValue = n.nodeValue.replace(t, dict[t]);
            }
        }
        document.documentElement.lang = lang;
    }

    // The Language row: Auto, then each language, round and round
    function order() { return ['auto', 'en'].concat(Object.keys(DICTS)); }
    function next() {
        var o = order(), i = o.indexOf(choice);
        var n = o[(i + 1) % o.length];
        try { window.localStorage.setItem(KEY, n); } catch (e) { return false; }
        return true;
    }
    function label() {
        return choice === 'auto' ? T('Auto ({lang})', { lang: NAMES[lang] }) : NAMES[choice];
    }

    window.LGU2E_I18N = { T: T, TS: TS, scripts: SCRIPTS, lang: lang, choice: choice, translatePage: translatePage, next: next, label: label, dicts: DICTS, names: NAMES };
}());
