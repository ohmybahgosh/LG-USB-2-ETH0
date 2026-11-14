# webOS 26: one quick setup step

On webOS 26, the LG-USB-2-ETH0 app can say it can't reach the TV as root, even on a rooted TV.  webOS 26 stopped letting homebrew apps use the Homebrew Channel's root service.  The Homebrew Channel has a fix for this ([webosbrew PR #233](https://github.com/webosbrew/webos-homebrew-channel/pull/233)), but it isn't in a Homebrew Channel release yet.

Running the script once as root puts that fix in place, so this app and your other homebrew apps can reach root again.  After that, the app takes it from there.

## Steps

1. On the TV, open the **Homebrew Channel**, then **Settings**, and turn on **SSH Server**.
2. From a phone or computer on the same network, connect to the TV.  The app shows the TV's IP address.  The password is `alpine` unless you changed it.

   ```sh
   ssh root@TV_IP
   ```

3. Run this:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh status
   ```

4. That's it.  The app checks every few seconds and carries on by itself.

On a phone, an app like Termius (iPhone and Android) works for SSH.

## What it changes

- The Homebrew Channel's root service also goes in `lunabus.query`, a permission group every app still has on webOS 26.  This is the same change the Homebrew Channel makes in its fix.
- The app goes in `org.webosbrew.hbchannel.service.group`, the group the Homebrew Channel's own app is in.

Then the TV reloads its app permissions.  With **Run at every boot** on, the boot hook checks this at every boot and puts it back if an update takes it away.  Once a Homebrew Channel release includes its fix, this step won't be needed at all.

Found by yurix67rem in [#32](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/32).

---

## По-русски

На webOS 26 приложение может писать, что нет root-доступа, даже на телевизоре с root.  Homebrew Channel уже исправил это, но исправление ещё не вышло в релизе.  Один запуск скрипта от root ставит это исправление.

1. В **Homebrew Channel** откройте **Settings** и включите **SSH Server**.
2. С телефона или компьютера в той же сети подключитесь (пароль `alpine`, если вы его не меняли):

   ```sh
   ssh root@TV_IP
   ```

3. Выполните:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh status
   ```

4. Готово.  Приложение само это заметит и продолжит.

## En español

En webOS 26 la app puede decir que no tiene acceso root, incluso con un televisor con root.  El Homebrew Channel ya lo arregló, pero el arreglo aún no está en una versión publicada.  Ejecutar el script una vez como root lo aplica.

1. En el **Homebrew Channel**, abre **Settings** y activa **SSH Server**.
2. Desde un teléfono o computadora en la misma red, conéctate (la contraseña es `alpine` si no la cambiaste):

   ```sh
   ssh root@TV_IP
   ```

3. Ejecuta:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh status
   ```

4. Listo.  La app lo detecta y sigue sola.
