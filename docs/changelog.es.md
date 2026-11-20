# Registro de cambios (en español)

Los cambios de LG-USB-2-ETH0 en español, para la pantalla Novedades de la aplicación después de una actualización.  La lista completa en inglés: [CHANGELOG.md](../CHANGELOG.md).  Los títulos de sección (`### Added`, `### Fixed`, `### Changed`) quedan en inglés: la aplicación los traduce sola.

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
