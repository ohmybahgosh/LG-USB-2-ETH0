# Registro de cambios (en español)

Los cambios de LG-USB-2-ETH0 en español, para la pantalla Novedades de la aplicación después de una actualización.  La lista completa en inglés: [CHANGELOG.md](../CHANGELOG.md).  Los títulos de sección (`### Added`, `### Fixed`, `### Changed`) quedan en inglés: la aplicación los traduce sola.

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
