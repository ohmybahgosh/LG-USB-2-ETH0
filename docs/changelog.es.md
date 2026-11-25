# Registro de cambios (en español)

Los cambios de LG-USB-2-ETH0 en español, para la pantalla Novedades de la aplicación después de una actualización.  La lista completa en inglés: [CHANGELOG.md](../CHANGELOG.md).  Los títulos de sección (`### Added`, `### Fixed`, `### Changed`) quedan en inglés: la aplicación los traduce sola.

## [2.11.55] - 2026-11-25

### Added

- **Avisa cuando pasó la comprobación de actualizaciones de LG al encender el TV.**  El actualizador de LG comprueba una vez justo después de cada reinicio, hacia el segundo 23, antes de que nada que arranque un TV con root pueda bloquearlo, y los ajustes de actualización de webOS no detienen esa comprobación (el actualizador siempre lee el ajuste como activado; encontrado en un C2 por FW Block 1.3.0).  Cuando pasa, el bloqueo ahora lo nota por el registro del actualizador, quita lo que encontró y lo dice en el registro, en `status` y en la app, con la versión que ofreció LG.  La nueva sección del README **Block LG on your router too** lista los seis nombres que bloquear en el router, lo único que detiene esa comprobación.

### Fixed

- **El README decía que el bloqueo detiene la comprobación de actualizaciones al principio del arranque.**  No es así: nada en el TV puede, y el README ahora lo dice y remite a la lista para el router.
- **Las reglas del cortafuegos podían parecer ausentes mientras otra herramienta usaba iptables.**  iptables 1.8.7 sale con 4 sin `-w` mientras otra herramienta tiene su bloqueo, así que una comprobación podía dar una regla por perdida.  Ahora el bloqueo espera al bloqueo de iptables, donde el iptables del TV lo permite.

## [2.11.54] - 2026-11-25

### Added

- **Un controlador más confirmado, ahora ofrecido por el controlador más rápido.**  El `ax88179_178a` de ASIX para el kernel `4.4.84-612.40.jimna.1` con el chip K6Hp hizo funcionar un adaptador AX88179 como `eth0` en un NANO91 de 2020 (55NANO916NA, webOS 5), en línea a 1000 Mbit/s (Shintech19, issue #59).

## [2.11.53] - 2026-11-24

### Changed

- **Listo para el Homebrew Channel 0.8.0.**  La 0.8.0 incluye el propio arreglo del Homebrew Channel para webOS 26, así que en webOS 26 la app ahora indica actualizar el Homebrew Channel y reiniciar el TV, lo que devuelve el acceso a todas las apps.  El comando `app-access` se queda para el Homebrew Channel 0.7.3 o anterior, y nunca toca el archivo de permisos que la 0.8.0 crea por sí misma.  La nueva forma de bloquear actualizaciones de la 0.8.0 (apagar la comprobación de actualizaciones de webOS, PR #264) ya era compatible: Bloquear actualizaciones a fondo funciona junto a ella y nunca vuelve a encender la comprobación mientras el Homebrew Channel la mantenga apagada.  Una diferencia de la 0.8.0: apagar su Block system updates vuelve a encender la comprobación de actualizaciones de webOS, incluso con Bloquear actualizaciones a fondo activado.  Ahora el bloqueo lo nota en 30 segundos y vuelve a apagar la comprobación, en vez de en su siguiente comprobación de 10 minutos (gracias a FW Block 1.2.2 por notarlo).

## [2.11.52] - 2026-11-23

### Added

- **Novedades antes de actualizar, y una fila Novedades.**  El aviso de actualización ahora muestra qué cambió desde su versión, del registro de cambios de la nueva versión, en el idioma de la app, antes de pulsar OK.  Y la pestaña Más tiene una fila **Novedades** que muestra las notas de esta versión cuando quiera.

### Fixed

- **Las novedades tras una actualización no siempre aparecían.**  La app marcaba la nueva versión como vista antes de comprobar si había otra cosa en pantalla, y si la había, las novedades se saltaban para siempre.  Ahora espera a la siguiente comprobación del estado, y pulsar un botón en su primer momento ya no las cierra antes de que las vea.

## [2.11.51] - 2026-11-23

### Fixed

- **Los servidores ocultos al arrancar vuelven en 30 segundos, no en 10 minutos.**  El bloqueador de anuncios de Glasshouse monta su propia tabla sobre `/etc/hosts` en segundo plano al arrancar, y si lo hace justo después de que el bloqueo de actualizaciones o de soporte remoto añadiera sus líneas, quedan ocultas debajo hasta la siguiente comprobación, hasta 10 minutos después.  Ahora la tarea en segundo plano lee `/etc/hosts` cada 30 segundos y, si a alguno de los servidores del bloqueo le falta su línea, las vuelve a poner enseguida, bajo el encabezado de Glasshouse (encontrado por FW Block 1.1.1 en un C2).

## [2.11.50] - 2026-11-21

### Added

- **Un controlador más confirmado, ahora ofrecido por el controlador más rápido.**  El `r8152_oot` de Realtek para el kernel `4.4.84-899.19.koli.1` hizo funcionar un TP-Link UE300 (RTL8153) en un NANO85 de 2021 (NANO85APA, webOS 6), a 296 Mbit/s de bajada (pdroidix, issue #57).

### Fixed

- **La app de TV decía que no podía llegar a root en televisores con un BusyBox antiguo.**  Una vez que el TV había registrado una reconexión del cable, una línea del historial de conexión usaba una forma de `awk` que el `awk` del BusyBox antiguo de algunos televisores lee como una llamada a una función que no existe.  Su error quedaba en medio del estado, así que la app no podía leerlo y mostraba "No se puede acceder al televisor como root" o "El script dio una respuesta inesperada", mientras el adaptador seguía funcionando (un NANO85 de 2021 con webOS 6, pdroidix, issue #57).  Corregido, y una nueva comprobación mantiene cada `awk` del script legible para ese BusyBox.

## [2.11.49] - 2026-11-20

### Fixed

- **Los servidores del bloqueo de actualizaciones siguen bloqueados con el bloqueador de anuncios de Glasshouse.**  [Glasshouse](https://github.com/rorygallagher2024/glasshouse) monta su propia tabla sobre `/etc/hosts` y, cuando cambian sus ajustes, solo conserva las líneas de otras herramientas bajo su encabezado "Kept from /etc/hosts".  El bloqueo de actualizaciones añadía sus líneas sin él, así que Glasshouse las quitaba hasta la siguiente comprobación de 10 minutos.  Ahora van bajo ese encabezado.

## [2.11.48] - 2026-11-20

### Fixed

- **Las apps podían quedarse sin DNS con el encendido por Wi-Fi activado.**  El encendido por Wi-Fi mantiene el Wi-Fi conectado a la misma red que el adaptador, y el TV respondía al "quién tiene esta dirección" del router desde ambos, así que el router podía mandar el tráfico de `eth0` a la radio Wi-Fi.  El relé DNS del TV solo escucha respuestas en `eth0`, así que cada consulta caducaba y las apps no encontraban nada por nombre (visto en un C2: Netflix, TiviBro y la terminal fallaban mientras el router respondía bien).  Ahora cada conexión solo responde por su propia dirección, y el TV se lo dice al router justo después del cambio.  Desinstalar lo deja como estaba.

## [2.11.47] - 2026-11-20

### Changed

- **Bloquear actualizaciones desde el teléfono dice cuándo hace falta reiniciar el TV.**  La conexión con el teléfono solo lee su lista al encender el TV, así que el interruptor ahora dice "funciona tras el próximo reinicio del TV" hasta que el bloqueo esté en su sitio, en vez de prometerlo en 10 minutos.
- **Bloquear actualizaciones a fondo funciona junto a FW Block y al bloqueo del Homebrew Channel.**  Si FW Block ya apagó la comprobación de actualizaciones y las actualizaciones automáticas de webOS, el bloqueo de aquí ahora guarda los valores originales de FW Block en vez de "apagado", y al apagar este bloqueo ambos ajustes siguen apagados mientras FW Block o Block system updates del Homebrew Channel los mantengan apagados, y lo dice.  Un ajuste guardado solo se borra cuando de verdad ha vuelto, así que si webOS no deja cambiarlo, apagar el bloqueo otra vez (o uninstall) lo vuelve a intentar, y al quitar la app se sigue intentando hasta devolverlo todo.  El estado dice cuándo es FW Block quien bloquea las actualizaciones.

### Added

- **Un controlador más confirmado, ahora ofrecido por el controlador más rápido.**  `ax88179_178a` de ASIX para el kernel `4.4.84-899.19.koli.1`, con el `usbnet` que ese kernel no trae, hizo funcionar un adaptador AX88179 en un B1 de 2021 (OLED55B16LA, webOS 6), en línea a 1000 Mbit/s (lun3x, issue #55).

## [2.11.46] - 2026-11-19

### Changed

- **Un menú nuevo, hecho para televisores grandes.**  El menú se divide en pestañas (Conexión, Bloqueo de actualizaciones, Controlador, Red y Más), con texto más grande y una descripción más larga en cada fila.  ARRIBA desde la primera fila de una pestaña va a las pestañas, IZQUIERDA y DERECHA cambian entre ellas, y una barra de desplazamiento fina aparece cuando una pestaña tiene más filas de las que caben.

### Added

- **Cinco herramientas nuevas en la pestaña Red, y por SSH.**  Comprobar conexión prueba el cable, la dirección, el router, el DNS e internet paso a paso y dice dónde falla, además de si las apps usan `eth0` y si los servidores de LG que bloqueó siguen bloqueados (`netcheck`).  Detalles de red muestra la dirección, el router, los servidores DNS, la dirección MAC y el MTU (`netinfo`).  Tráfico en vivo muestra a qué velocidad pasan los datos por el adaptador y el Wi-Fi, cada segundo (`traffic`).  Salud del enlace muestra cuánto lleva activo el enlace por cable, sus cortes y errores, y los cambios recientes.  Historial de pruebas de velocidad muestra sus pruebas anteriores con el controlador de cada una, frente a lo que puede llevar la conexión.
- **Bloquear actualizaciones a fondo ahora cubre las apps del teléfono y detiene una descarga que empiece de todos modos, como FW Block.**  La app de LG en el teléfono (LG ThinQ) puede hacer que el TV descargue una actualización de firmware directamente desde el teléfono, saltándose cualquier bloqueo de servidores: la conexión del TV con el teléfono ya no lo ofrece, desde el próximo encendido (Bloquear actualizaciones desde el teléfono, `--no-block-phone-updates` para dejarlo abierto).  Y cada 30 segundos mientras el actualizador de LG trabaja, se cancela una descarga de firmware con un mensaje en el TV, sin tocar una instalación ni una actualización por USB (Detener descargas de firmware, `--no-stop-downloads`).  Ambas se activan con el bloqueo, tienen su propio interruptor en la app y aparecen en Comprobar conexión y en el informe.
- **Un controlador más confirmado, ahora ofrecido por “Controlador más rápido”.**  El `r8152_oot` de Realtek para el kernel `5.4.268-329.ptl4tv.2` hizo funcionar un adaptador RTL8153 como `eth0` en un G2 de 2022 (OLED65G26LA, webOS 25), conectado a 1000 Mbit/s (lasharor, issue #53).
- **“Bloquear el soporte remoto de LG”, un ajuste nuevo y opcional (`--block-remote-support`), desactivado por defecto.**  Durante una sesión de soporte remoto de LG, su personal puede enviar una actualización de firmware que se salta la comprobación de actualizaciones que detiene el bloqueo (encontrado en el firmware del C2, igual en webOS 26).  Bloquea los servidores de soporte remoto de LG en `/etc/hosts` y los dos a los que el televisor llega por IP, y lo comprueba cada 10 minutos como el bloqueo de actualizaciones.  Mientras está activado, el soporte de LG no puede conectarse al televisor, y la aplicación lo avisa antes de activarlo.
- **Cada ajuste de la aplicación pregunta antes.**  “Ejecutar en cada arranque”, “Seguir conexión y desconexión”, “Modo Realtek”, “Wi-Fi como respaldo” y “Encendido por Wi-Fi en reposo” cambiaban al momento, en un sentido o en los dos.  Ahora cada ajuste, al activarlo y al desactivarlo, explica qué hace y cómo deshacerlo, y solo sigue con OK.

### Fixed

- **Apagar todo ya no deja nada atrás, y quitar la app también limpia.**  `uninstall` dejaba el registro, los contadores del bloqueo de actualizaciones, el historial de conexión y los controladores descargados.  Ahora borra todos los archivos del script y deshace todas las opciones.  Y como webOS no ejecuta nada al quitar una app, la tarea de fondo ahora revisa cada 30 segundos que la app siga ahí: si falta durante cerca de un minuto, lo deshace todo igual.  También se corrigió que las líneas del bloqueo de actualizaciones en `/etc/hosts` se quedaran cuando eran las únicas del archivo.
- **“Bloquear actualizaciones a fondo” también desactiva las actualizaciones automáticas de webOS.**  El actualizador lee un segundo ajuste (`automaticUpdate`) junto con la comprobación de actualizaciones y, si está activado, instala sin preguntar una actualización que encuentre.  Ahora también se desactiva, se comprueba cada 10 minutos y vuelve a como estaba al desactivar la opción.
- **Ya no hay aviso por el indicador de servidor del actualizador.**  2.11.44 avisaba cuando aparecía uno de los archivos indicadores de servidor, pero el actualizador crea uno él mismo, y todos los servidores que elige los cubre el bloqueo.  Ahora solo aparecen en el informe.

## [2.11.45] - 2026-11-19

### Added

- **Novedades en su idioma.**  Después de una actualización, la pantalla Novedades de la aplicación muestra ahora los cambios en ruso o en español cuando la aplicación está en uno de esos idiomas, en lugar de solo en inglés.  Los cambios en cada idioma están en `docs/changelog.ru.md` y `docs/changelog.es.md`, y una comprobación se asegura de que cada versión los tenga.

## [2.11.44] - 2026-11-19

### Changed

- **La comprobación del bloqueo de actualizaciones empieza enseguida.**  Antes, activar “Bloquear actualizaciones a fondo”, o cambiar cualquier ajuste, detenía la tarea en segundo plano hasta el siguiente arranque, y estos televisores pueden pasar semanas en reposo sin reiniciarse.  Ahora la tarea vuelve a empezar en cuanto se guardan los ajustes.  Si ya estaba en marcha, sigue como antes.  Si no, solo empieza lo que no puede esperar (la comprobación del bloqueo de actualizaciones, IPv6 desactivado, EEE desactivado y el historial de conexión); seguir el adaptador, pasarlo al controlador más rápido y el respaldo Wi-Fi siguen empezando en el siguiente arranque, como siempre.

### Added

- **Un aviso si el actualizador de webOS se cambia a otro servidor.**  El actualizador guarda archivos indicadores que pueden apuntarlo a un servidor distinto de los que bloquean las líneas de hosts (en un C2 con webOS 25 no hay ninguno).  La comprobación cada 10 minutos ahora los busca, anota uno en el registro, y `status`, la aplicación y el informe lo señalan.  No toca el archivo de LG.  La comprobación de actualizaciones de webOS sigue desactivada, así que el actualizador no puede comprobar de ninguna forma.

## [2.11.43] - 2026-11-19

### Added

- **“Bloquear actualizaciones a fondo” ahora sigue comprobando.**  Antes solo actuaba al arrancar, y estos televisores pueden pasar semanas en reposo sin un arranque.  Ahora comprueba cada 10 minutos que nada lo haya deshecho: la comprobación de actualizaciones de webOS activada de nuevo, sus servidores fuera de `/etc/hosts` o su regla de firewall eliminada.  Lo que falte se vuelve a poner enseguida y se anota en el registro.  Una actualización que webOS encontró o descargó se quita en cuanto aparece, no solo en el siguiente arranque.
- **Prueba de que el bloqueo funciona.**  La regla de firewall cuenta cada vez que el actualizador de LG intenta llegar a su servidor por IP, y la fila “Bloquear actualizaciones a fondo” de la aplicación ahora dice cuántas veces lo detuvo y cuándo, o que quitó una actualización que webOS encontró.  `status` señala todo lo que tuvo que volver a poner en la última semana, y el informe muestra la cuenta.
- **Historial de conexión.**  La tarea en segundo plano anota cada vez que el enlace por cable del adaptador se cae y vuelve, cuánto tiempo faltó y a qué velocidad volvió.  Las caídas cuando el televisor entra en reposo no cuentan, porque el reposo apaga el adaptador.  La aplicación muestra cuántas caídas hubo en el último día, `status` lo señala a partir de dos, y el informe lista las últimas, para ayudar a encontrar un cable, puerto o adaptador defectuoso.
- **“Desactivar Energy Efficient Ethernet” (`--eee-off`), desactivado por defecto.**  EEE es una causa frecuente de que el enlace se caiga unos segundos con algunos adaptadores y routers.  Necesita `ethtool`, que webOS no trae (con Entware: `opkg install ethtool`), así que la aplicación solo muestra la fila donde está `ethtool`.  Desactiva EEE cada vez que se activa el enlace del adaptador.
