# webOS 26: one quick setup step

On webOS 26, the LG-USB-2-ETH0 app can say it can't reach the TV as root, even on a rooted TV.  webOS 26 stopped letting homebrew apps use the Homebrew Channel's root service.  **[Homebrew Channel 0.8.0](https://github.com/webosbrew/webos-homebrew-channel/releases/tag/v0.8.0) fixes this for every app** ([webosbrew PR #233](https://github.com/webosbrew/webos-homebrew-channel/pull/233)).  Update the Homebrew Channel from its own app, restart the TV, and you're done: nothing below is needed.

With Homebrew Channel 0.7.3 or older:

Running the script's `app-access` command once lets this app back in.  It only runs when you run it, and it only changes this app's own permissions, nothing of the Homebrew Channel's or any other app's, so the Homebrew Channel's own updates aren't affected.  Other homebrew apps get the same fix from Homebrew Channel 0.8.0.

## Steps

1. On the TV, open the **Homebrew Channel**, then **Settings**, and turn on **SSH Server**.
2. From a phone or computer on the same network, connect to the TV.  The app shows the TV's IP address.  The password is `alpine` unless you changed it.

   ```sh
   ssh root@TV_IP
   ```

3. Run this:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh app-access
   ```

4. That's it.  The app checks every few seconds and carries on by itself.

On a phone, an app like Termius (iPhone and Android) works for SSH.

## What it changes

Only this app's own permissions file: the app goes in `org.webosbrew.hbchannel.service.group`, the group the Homebrew Channel's own app is in.  Then the TV reloads its app permissions.  Nothing else runs it, not even the boot hook.  If an app update ever takes it away, the app shows this screen again, and you can run the same command.  With Homebrew Channel 0.8.0 or newer, this step isn't needed at all.

Version 2.11.28 also added a permissions file to the Homebrew Channel itself, which it shouldn't have.  If you ran 2.11.28, `status` says so, and `app-access` takes that file back out, only where it's exactly the file 2.11.28 added.

Found by yurix67rem in [#32](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/32).

---

## По-русски

На webOS 26 приложение может писать, что нет root-доступа, даже на телевизоре с root.  **Homebrew Channel 0.8.0 исправляет это для всех приложений:** обновите Homebrew Channel и перезапустите телевизор, больше ничего не нужно.  Со старым Homebrew Channel (0.7.3 и раньше) один запуск скрипта от root возвращает доступ этому приложению.  Меняются только права этого приложения.

1. В **Homebrew Channel** откройте **Settings** и включите **SSH Server**.
2. С телефона или компьютера в той же сети подключитесь (пароль `alpine`, если вы его не меняли):

   ```sh
   ssh root@TV_IP
   ```

3. Выполните:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh app-access
   ```

4. Готово.  Приложение само это заметит и продолжит.

## En español

En webOS 26 la app puede decir que no tiene acceso root, incluso con un televisor con root.  **El Homebrew Channel 0.8.0 lo arregla para todas las apps:** actualiza el Homebrew Channel y reinicia el televisor, y no hace falta nada más.  Con un Homebrew Channel más antiguo (0.7.3 o anterior), ejecutar el script una vez como root le devuelve el acceso a esta app.  Solo cambia los permisos de esta app.

1. En el **Homebrew Channel**, abre **Settings** y activa **SSH Server**.
2. Desde un teléfono o computadora en la misma red, conéctate (la contraseña es `alpine` si no la cambiaste):

   ```sh
   ssh root@TV_IP
   ```

3. Ejecuta:

   ```sh
   sh /media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0/assets/lg-usb-2-eth0.sh app-access
   ```

4. Listo.  La app lo detecta y sigue sola.
