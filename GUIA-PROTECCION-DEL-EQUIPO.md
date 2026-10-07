---
titulo: Guía de protección del equipo
equipo: Windows 11 Home o Pro
version: 1.3
fecha: 2026-10-04
---

# Guía de protección del equipo

## 1. Propósito y alcance

Este documento reúne en un solo lugar la configuración de seguridad y privacidad aplicada al equipo entre el 26 de agosto y el 2 de octubre de 2026: la reducción de la telemetría de Windows y de los programas instalados, el tratamiento local de los informes de error, el cortafuegos, la resolución de nombres sin terceros y el navegador «Buscador», que sale a internet únicamente por la red Tor. Para cada medida se indica qué hace, por qué se tomó, el comando exacto que la aplica y cómo se deshace. Al final se recogen los errores cometidos durante la construcción, porque explican varias decisiones que de otro modo parecerían arbitrarias.

Todo el sistema vive en `%USERPROFILE%\Seguridad\`. Cada script trabaja en simulacro o guarda un respaldo antes de cambiar nada, y casi todos aceptan `-Revertir`. Los respaldos están en `Seguridad\Respaldos\`.

## 2. Principios que gobiernan la configuración

Las decisiones de este documento obedecen a seis reglas fijadas por el propietario. Ninguna información debe salir hacia servicios de terceros: por eso se rechazaron los DNS de Quad9 y Mullvad, y también cualquier VPN, proxy o bloqueador que dependa de un servidor ajeno. Nada debe consumir recursos en segundo plano sin autorización expresa; la vigilancia periódica que existió en agosto se eliminó por completo a petición suya. Los informes de error se conservan en el propio equipo, para que él decida si los envía. No se bloquean dominios de Microsoft ni se fuerza la telemetría por debajo de lo que Windows Home admite, porque una medida así ya le costó un bloqueo de Windows. La dirección IP debe quedar oculta siempre, sin excepciones, y el navegador no puede tener un camino directo de reserva. Por último, todo se entrega como un botón de doble clic en `Downloads\`, no como una instrucción que haya que teclear.

Hay un límite que conviene tener presente desde el principio: en Windows 11 Home la telemetría no puede llevarse a cero. El valor `AllowTelemetry = 0` está escrito en el registro, pero solo lo respetan las ediciones Enterprise y Education; en Home el mínimo efectivo es «Requerido». Lo que sí se consigue es apagar los servicios que la recogen y todo lo opcional.

## 3. Puesta en marcha rápida

Para dejar el equipo configurado desde cero, o repararlo tras una actualización grande de Windows, se pulsan los botones en este orden. Cada uno se eleva solo y puede repetirse sin daño.

1. `BLINDAR MI PC.bat`: endurecimiento base en nueve capas (Defender, puertos, cerrojos, privacidad, sigilo, máquinas virtuales, controladores, credenciales y ransomware).
2. `PROTECCION NIVEL PELICULA.bat`: DNS local con Unbound, informes de error en local, MAC aleatoria por red.
3. `CONFIGURAR CORTAFUEGOS.bat` (nuevo): todo el cortafuegos en una pasada.
4. `CONFIGURAR BUSCADOR COMPLETO.bat` (nuevo): navegador, Edge paralizado, Tor siempre encendido y candado.
5. `COMPROBAR MI PROTECCION.bat`: verificación final en unos treinta segundos.

Si tras cualquiera de ellos se pierde internet, `SI ME QUEDO SIN INTERNET.bat` devuelve la red al estado del respaldo. Los dos scripts nuevos llevan además su propio reversor de diez minutos.

## 4. Telemetría de Windows y de los programas

### 4.1 Servicios de recogida

`DiagTrack` (experiencia del usuario y telemetría conectadas) y `dmwappushservice` están detenidos y deshabilitados. Se comprueba con:

```powershell
Get-Service DiagTrack, dmwappushservice | Select-Object Name, Status, StartType
```

`Servicios-Windows.ps1` apagó además `MapsBroker` (mapas sin conexión), `TrkWks` (seguimiento de vínculos), `PcaSvc` (asistente de compatibilidad, que informa a Microsoft) y `WSearch` (el indexador de búsqueda, cuyo índice de 1,7 GB se borró). El indexador se verificó como auténtico de Microsoft; se apagó por consumo, no por ser malicioso. Una actualización grande puede reactivarlo: `VER COMO ESTA MI PC.bat` avisa si ocurre y basta repetir el script.

```powershell
Stop-Service WSearch -Force; Set-Service WSearch -StartupType Disabled
```

### 4.2 Telemetría restante (`Telemetria-Restante.ps1`)

Este script apagó 42 elementos. En Office, las políticas `sendtelemetry=3`, `qmenable=0`, los comentarios y el agente OSM, más `usercontentdisabled=2` y `downloadcontentdisabled=2` en `HKCU\Software\Policies\Microsoft\Office\16.0\common\privacy`. En Edge, dieciséis políticas en `HKLM\SOFTWARE\Policies\Microsoft\Edge`, entre ellas `DiagnosticData=0`, `PersonalizationReportingEnabled=0`, `CopilotPageContext=0` y `TrackingPrevention=3`. Cinco tareas programadas de recogida: `MareBackup`, `Autochk\Proxy`, `Device`, `Device User` y `MapsToastTask`. En el usuario, las variables `POWERSHELL_TELEMETRY_OPTOUT=1` y `DOTNET_CLI_TELEMETRY_OPTOUT=1`; en VS Code, `telemetry.telemetryLevel = off`; en Claude Code, `DISABLE_TELEMETRY` y `DISABLE_ERROR_REPORTING`. Se revierte con `Telemetria-Restante.ps1 -Revertir`.

### 4.3 Microsoft y fabricantes

`Apagar-Microsoft.ps1` deshabilitó `WSAIFabricSvc`, `whesvc` e `InventorySvc`, siete tareas de Office, Click to Do, CrossDeviceResume y los avisos de bienvenida, y desinstaló el Outlook nuevo y el complemento de Teams. Se conservan deliberadamente `ClickToRunSvc` y las dos tareas de actualización de Office, porque Word depende de ellas.

`Limpiar-Arranque.ps1` apagó la telemetría de Intel (Telemetry Agent, Collector, PresentMon) y el diagnóstico de ASUS (SystemAnalysis, SystemDiagnosis, SoftwareManager). El asistente de controladores de Intel quedó en arranque manual, con su propio botón `ACTUALIZAR DRIVERS INTEL.bat`. `Quitar-Intel-Graficos.ps1` apagó `IntelGraphicsSoftwareService`, que resucitaba PresentMon. Tras cada actualización del controlador gráfico de Intel conviene comprobar que no haya vuelto a Automático:

```powershell
Get-Service IntelGraphicsSoftwareService, PresentMon* -ErrorAction SilentlyContinue | Select-Object Name, StartType
```

`Parche-Eventos.ps1` eliminó el servicio huérfano `PRI-Driver` y deshabilitó los tres servicios «Queencreek» de Intel, que eran telemetría de energía y llenaban el Visor de eventos de errores 7000, 7023 y 7034.

### 4.4 Privacidad adicional (`Paranoia.ps1`)

Apaga el historial de actividad y el portapapeles en la nube, la Optimización de distribución en modo P2P (`DODownloadMode=0`), Buscar mi dispositivo, Recall y Copilot, el reconocimiento de voz en línea y la lista de idiomas que Windows expone a las páginas. En la red local desactiva LLMNR, mDNS, NetBIOS en los quince adaptadores y el autodescubrimiento de proxy (WPAD). Defender deja de subir muestras sin preguntar (`Set-MpPreference -SubmitSamplesConsent 2`) y sigue protegiendo igual. IPv6 pasa a usar direcciones temporales aleatorias:

```powershell
netsh interface ipv6 set privacy state=enabled
netsh interface ipv6 set global randomizeidentifiers=enabled
```

El script anota el valor original de cada uno de sus 29 ajustes antes de cambiarlo, y `-Revertir` los devuelve.

## 5. Informes de error de Windows

Los informes se generan, pero no se envían. `Nivel-Pelicula.ps1` fija en `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting` `ForceQueue=1` (dejar en cola local) y, en su subclave `Consent`, `DefaultConsent=1` (preguntar siempre), y activa `LocalDumps` para que los volcados de los programas que se cierran queden en el disco. El servicio `WerSvc` está en manual. El botón `VER MIS INFORMES DE ERRORES.bat` abre el Monitor de confiabilidad (`perfmon /rel`), desde donde pueden enviarse a Microsoft uno por uno si se desea.

Dos ajustes de estabilidad pertenecen a este apartado aunque nacieron de un problema de hardware. Los apagones y pantallazos negros (22 eventos Kernel-Power 41 y un bugcheck `0x154`) los causa el SSD Kingston NV3, que se desconecta del bus a 76–79 °C. Se apagó el ahorro de energía de PCIe (ASPM de 2 a 0), se activaron los volcados completos (`CrashDumpEnabled=7`) y `Parche-NVMe.ps1` le prohibió el estado de reposo profundo. Si los cuelgues vuelven, la causa sigue siendo ese disco y la solución definitiva es reemplazarlo.

## 6. Pila de red

`Parche-TCPIP.ps1` se ejecutó una sola vez y guardó los `.reg` originales junto a él.

```powershell
netsh interface ipv4 set global icmpredirects=disabled
netsh interface ipv6 set global icmpredirects=disabled
netsh interface ipv4 set global sourceroutingbehavior=drop
netsh interface ipv6 set global sourceroutingbehavior=drop
netsh interface isatap set state disabled
netsh interface 6to4 set state disabled
netsh interface teredo set state disabled
```

Las redirecciones ICMP permitirían a un tercero desviar el tráfico; el enrutamiento por origen deja que un paquete dicte su propio camino; ISATAP, 6to4 y Teredo son túneles que no se usan. En el registro se fijan además `DisableIPSourceRouting=2`, `EnableICMPRedirect=0` y `PerformRouterDiscovery=0`, este último solo en IPv4: el descubrimiento de routers de IPv6 no se toca, porque de él sale la dirección IPv6 pública del equipo.

## 7. Resolución de nombres: Unbound

El equipo no pregunta a ningún DNS ajeno. Unbound, instalado como servicio, resuelve de forma recursiva desde los servidores raíz y solo atiende en `127.0.0.1` y `::1`; cualquier otra dirección recibe `refuse`. Los adaptadores Wi-Fi y Ethernet apuntan a esas dos direcciones. La configuración está en `C:\Program Files\Unbound\service.conf` e incluye minimización de consultas (`qname-minimisation`), validación DNSSEC y ocultación de identidad y versión.

El bloqueador de anuncios y malware funciona en este mismo nivel: `Bloqueador-Red.ps1` añade `bloqueo.conf` (lista StevenBlack, 74 599 dominios, respuesta `always_nxdomain`) mediante una línea `include:`. Antes de reiniciar el servicio valida la configuración con `unbound-checkconf` y, si falla, devuelve la anterior. Excluye a propósito los dominios de Microsoft y los de las cuentas del propietario. Tras cualquier cambio:

```powershell
Restart-Service unbound; ipconfig /flushdns
```

Conviene entender el alcance real. Unbound evita que un proveedor de DNS acumule el historial, pero sus consultas a los servidores autoritativos viajan sin cifrar, de modo que el proveedor de internet podría verlas. Eso no afecta al Buscador, que resuelve los nombres dentro de Tor (apartado 9); sí afecta al resto de programas del equipo.

## 8. Cortafuegos

### 8.1 Estado comprobado el 4 de octubre de 2026

Los tres perfiles están activos, con la entrada bloqueada por defecto, la salida permitida y el registro de conexiones bloqueadas en `C:\Windows\System32\LogFiles\Firewall\pfirewall.log`. Existen las reglas `Centinela-Blindaje-Subred-Local`, las cuatro `Centinela-VM-Aislada-*` y el candado del Buscador. **Faltaban las dos reglas anti-ping** (`Centinela-Sin-Ping-IPv4` y `-IPv6`), que el blindaje de agosto debía haber creado; el nuevo script las repone.

### 8.2 Qué hace `Configurar-Cortafuegos.ps1`

Se ejecuta con `Downloads\CONFIGURAR CORTAFUEGOS.bat`. Funciona en cinco pasos.

**Paso 0, respaldo.** Exporta la política completa con `netsh advfirewall export` a `Respaldos\cortafuegos-AAAAMMDD-HHMMSS.wfw` y registra la tarea `Cortafuegos - Reversor 10 min`, que la reimporta como SYSTEM a los diez minutos.

**Paso 1, perfiles.** Aplica el comando central de toda la configuración y pasa a «Pública» cualquier red marcada como privada:

```powershell
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True `
  -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True `
  -LogBlocked True -LogAllowed False -LogMaxSizeKilobytes 32767
```

**Paso 2, barrido de entrada.** Desactiva, sin borrarlas, las reglas de entrada de descubrimiento de redes, Wi-Fi Direct, proyección inalámbrica, Optimización de distribución, dispositivos conectados, MyASUS, transmisión a dispositivos, Teredo, mDNS, uso compartido de archivos e impresoras, AllJoyn, asistencia y escritorio remotos, monitor de eventos remotos, uso compartido del Reproductor de Windows Media, administración remota y `usbipd`. También las de programas que solo escuchan en el propio equipo (Python, Node, LM Studio, Postman, Packet Tracer, Podman, Outlook, AsusSwitchNet), porque el cortafuegos no filtra el bucle local y esas reglas solo añaden superficie. Elimina las de `adb.exe` y los mineros, y saca del perfil público las de los juegos. Nunca toca «Redes principales», el DHCP ni IPHTTPS: una regla amplia que alcanzara el DHCP dejaría el equipo sin dirección IP.

**Paso 3, reglas propias.** Crea o recrea:

```powershell
New-NetFirewallRule -DisplayName 'Centinela-Sin-Ping-IPv4' -Direction Inbound -Action Block -Protocol ICMPv4 -IcmpType 8 -Profile Any
New-NetFirewallRule -DisplayName 'Centinela-Sin-Ping-IPv6' -Direction Inbound -Action Block -Protocol ICMPv6 -IcmpType 128 -Profile Any
New-NetFirewallRule -DisplayName 'Centinela-Blindaje-Subred-Local' -Direction Inbound -Action Block -RemoteAddress LocalSubnet -Profile Public,Private
```

Solo se bloquea el eco: los mensajes ICMP de tipo 3 y 11 siguen pasando, porque sin ellos se rompe el descubrimiento del tamaño de paquete y algunas páginas dejan de cargar. La regla de subred local impide que cualquier equipo de la red de la casa inicie una conexión hacia este; las respuestas a lo que el propio equipo pide no se ven afectadas. Si existen los adaptadores VMnet1 y VMnet8 de VMware, se bloquean en ambos sentidos. Por último, el candado del Buscador (apartado 9.4).

**Paso 4, servicios que abren puertos.** Detiene y deshabilita WinRM, LanmanServer, SSDP, UPnP, Registro remoto, Acceso remoto, Escritorio remoto y sus servicios auxiliares, el uso compartido del Reproductor, la publicación de recursos, la topología de vínculos, CDPSvc, los servicios P2P y `iphlpsvc`, y deniega por registro el escritorio y la asistencia remotos. LanmanWorkstation se mantiene: es el cliente, sin el cual no se accede a carpetas compartidas ajenas. El puerto 445 puede seguir apareciendo a la escucha hasta el siguiente reinicio, porque el controlador `srv2.sys` continúa cargado; no es un fallo.

**Paso 5, comprobación.** Prueba internet con una conexión TCP directa al puerto 443 de tres direcciones públicas y la resolución por Unbound. Si no hay internet, restaura de inmediato. Si lo hay, pide escribir `SI` tras abrir una página; solo entonces se borra el reversor. Cerrar la ventana sin contestar equivale a deshacer todo a los diez minutos. Para volver atrás más tarde:

```powershell
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\Seguridad\Configurar-Cortafuegos.ps1 -Revertir
```

## 9. El Buscador

### 9.1 Arquitectura

El Buscador es LibreWolf 156.0.1 con apariencia propia (carita amarilla, título «Buscador»). Ninguna página sale directamente desde el navegador: el candado del cortafuegos impide a `librewolf.exe` hablar con cualquier dirección pública, de modo que solo puede comunicarse con tres puertas locales. Un filtro de rutas, escrito en los ajustes del navegador, decide cuál usa cada petición según la página principal que se abrió.

1. **Tor normal**, para todo por defecto, a través de la carrera de circuitos (127.0.0.1:9070, apartado 9.7) y, si esta falla, directamente por 127.0.0.1:9050. Un motor Tor en Ubuntu 26.04 (WSL) entra en la red por un puente WebTunnel, que ante el proveedor parece una conexión HTTPS a una página común; después cruza tres relevos, y cada sitio recibe su propio circuito y su propia IP de salida.
2. **Tor con salida elegida (127.0.0.1:9055)**, para los sitios que bloquean por país y no por ser Tor. Es un segundo motor con el mismo puente que solo sale por relevos de los países admitidos en `Buscador\salida_elegida.txt`. Hoy lo usa un portal educativo: su cortafuegos FortiWeb rechaza ciertas IP por país («Attack ID 20000018», *Unauthorized Geo IP*). La prueba del 4 de octubre mostró que abre desde salidas de Estados Unidos, Canadá, México, Chile, Alemania, Países Bajos, Francia y Reino Unido, y no desde Suecia, Austria, Rumanía o Luxemburgo. La IP sigue oculta.
3. **Puerta directa protegida (127.0.0.1:9060)**, solo para los sitios que rechazan a toda la red Tor y que el propietario autoriza en `Buscador\directos.txt`. Hoy solo Kick, cuya regla de Cloudflare bloqueó las veinte salidas probadas. Por esta puerta el sitio ve la IP real. La puerta solo escucha en el equipo, comprueba que la página principal esté autorizada, admite únicamente HTTPS, rechaza cualquier destino de la red de casa o reservado y anota los rechazos en `Buscador\puerta.log`. Solo los servidores propios del sitio salen directo; lo que la página carga de terceros (anuncios, analítica, otros proveedores) sigue por Tor. En esos sitios la hora y el idioma son los reales de Colombia, porque una IP colombiana con la hora de Islandia es una alerta habitual de los sistemas antifraude.

En Windows, Smart App Control bloquea las bibliotecas de Tor Browser, y por eso los motores viven en Linux. Llegan a Windows a través de `wslrelay`, que solo escucha en el propio equipo: nadie de la red local alcanza esos puertos.

### 9.2 Piezas y su ubicación

En Windows, dentro de `Seguridad\Buscador\`: `lanzar_buscador.pyw` abre el navegador, limpia cookies y caché salvo las de la lista `CONSERVAR`, escribe `ruta.pac` y las listas de sitios en las preferencias, y enciende los motores y la puerta si faltan; un candado (`.lanzador.lock`) impide que dos lanzadores limpien o abran a la vez, el navegador cuenta como abierto solo si su perfil está en uso, y si la limpieza falla el lanzador lo anota en `lanzador.log` y abre igual; `vigia_tor.pyw` comprueba los cuatro servicios (9050, 9055, 9060 y 9070) cada treinta segundos y reenciende lo que caiga; cada dos minutos abre además una conexión de prueba por cada motor y, si falla tres veces seguidas, reinicia ese motor, porque un puente muerto deja el puerto abierto sin salida; cada seis horas pide la renovación de puentes, y anota lo que hace en `vigia.log`. Lo arranca la tarea `Buscador - Tor siempre` al iniciar sesión; `puerta_directa.py` es la puerta; `carrera.py` la carrera de circuitos, `velocidad.json` el requisito y los parámetros de velocidad, y `afinar.py` el afinador; `directos.txt` y `salida_elegida.txt` son las dos listas; `tor-elegida.sh` es la copia en Windows del motor de salida elegida; `desde_edge.pyw` recibe lo que Windows mandaba a Edge; `inicio.html` es la página de inicio, con DuckDuckGo HTML por defecto, y `tls-debil.html` el aviso de conexión débil cortada. La carpeta `pruebas\` guarda las comprobaciones que respaldan cada ajuste, y `BITACORA-2026-10-04.md` el registro de la jornada en que se construyó todo esto. En la carpeta del programa están `defaults\pref\buscador.js`, `distribution\policies.json` y los iconos; en el perfil, `~\.librewolf\librewolf.overrides.cfg`, con los ajustes y los candados `lockPref`.

En Ubuntu, dentro de `~/.carita/`: `tor-buscador.sh` (motor principal), `tor-elegida.sh` (motor de salida elegida), `puentes.sh` (gestión de puentes: `aplicar`, `renovar`, `rescatar`, `probar`) y `puentes.txt` (los puentes en uso). Los dos motores conservan el circuito de un sitio mientras alguna conexión suya sigue abierta (`KeepAliveIsolateSOCKSAuth`, como Tor Browser), y el de salida elegida pasa a todos los puentes si el primero no conecta en 45 segundos. Las copias de Windows de los dos motores están en `Buscador\`.

### 9.3 Ajustes del navegador

**Rutas.** Además del filtro descrito, quedan bloqueados con `lockPref` el archivo PAC, la resolución de nombres por el proxy, el paso directo si el proxy falla (`failover_direct=false`), WebRTC limitado al proxy y HTTP/3 apagado.

**TLS.** Mínimo 1.2 y máximo 1.3, por decisión del propietario del 4 de octubre. El saludo TLS es idéntico al de Firefox, con sus diecisiete cifrados, y su huella JA4 es `t13d1717h2_5b57614c22b0_3cbfd9057e0d`, la de cualquier Firefox 156. Quitar cifrados del saludo, como se hizo durante unas horas, y antes el modo «solo TLS 1.3», dejaba una huella que no era la de Firefox; los sistemas antibots puntúan esa incoherencia como señal de programa automático. La protección se aplica después del saludo: el bloque «TLS vigilado» corta toda conexión en la que el servidor elija un cifrado débil (CBC, o intercambio RSA sin secreto hacia adelante) o una versión anterior a 1.2, y la pestaña muestra «Conexión débil cortada». Las excepciones se indican en `carita.tls_debil_permitido`, hoy vacía. Siguen activos el anclaje estricto de certificados, la revocación por CRLite, el modo solo HTTPS, la renegociación segura, la detección de degradación y la prohibición de TLS 1.0 y 1.1.

**Ubicación y cuentas.** En las páginas que van por Tor, el bloque «Ubicación oculta» presenta el idioma `es-ES` y la zona horaria `Atlantic/Reykjavik` en la página, los marcos y los *workers*. Una sola lista, `CUENTAS`, reúne 45 dominios de correo, estudio, bancos, compras, trabajo y herramientas de IA. Esos sitios ven la hora real y conservan la misma IP durante la sesión: no reciben circuito nuevo automático, y lo que cargan de terceros viaja por un circuito aparte. Hasta el 4 de octubre había dos listas que no coincidían. Las redes sociales quedan fuera a propósito, y los sitios de `directos.txt` también ven la hora real.

**Caché.** LibreWolf trae apagada la caché en disco, y el lanzador borraba además la de todos los sitios en cada apertura: cada sesión volvía a descargar por Tor el código completo de las páginas (274 piezas en Twitch). Desde el 4 de octubre la caché en disco está encendida, con tope de 512 MB, y el lanzador solo borra la de los sitios que no están en `CONSERVAR`. Con la caché, la página de Twitch queda lista en 1,4 segundos.

**Cookies y avisos.** Las cookies se borran al cerrar, salvo las de los 55 dominios de `CONSERVAR` (correo, estudio, IA, trabajo, redes y banca), que guardan la sesión. El historial, los favoritos y las contraseñas se conservan. Los avisos de cookies se ocultan con uBlock Origin, configurado por política con las listas `fanboy-cookiemonster`, `ublock-cookies-easylist` y `adguard-cookies`; el cambio surte efecto en el segundo arranque. Los avisos de términos de servicio actualizados y las reglas que los canales imponen antes de escribir en el chat se **ocultan** sin aceptarlos: el bloque «Avisos ocultos» busca cada segundo esas frases exactas, toma el bloque más pequeño que contiene el texto y un botón de aceptar, y lo oculta con `display:none`. No borra nada, no pulsa nada y nunca toca un bloque con más contenido, como la columna del chat. Tampoco toca los formularios de registro ni los pies de página. Si un canal exige aceptar sus reglas para dejar escribir, su chat puede no enviar mensajes.

### 9.4 Qué hace `Configurar-Buscador.ps1`

Se ejecuta con `Downloads\CONFIGURAR BUSCADOR COMPLETO.bat` y solo pone lo que falta. Primero comprueba los requisitos: Python, las piezas de `Buscador\`, LibreWolf (lo instala con winget si no está) y su firma digital, y que Unbound esté en marcha. Después repone `buscador.js`, sin el cual no corre ninguno de los ajustes con privilegios; los iconos de la carita; y `policies.json` desde `Respaldos\librewolf-propio` si difiere, ya que una actualización de LibreWolf puede reescribirlo. Revisa que los overrides contengan el proxy, la resolución remota y la versión de TLS.

A continuación paraliza Edge sin desinstalarlo. Cierra sus procesos y redirige su ejecutable mediante la clave *Image File Execution Options*:

```powershell
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe'
Set-ItemProperty $ifeo Debugger '"...\pythonw.exe" "%USERPROFILE%\Seguridad\Buscador\desde_edge.pyw"'
```

Desde ese momento, cualquier cosa que Windows mande a Edge, un enlace o un PDF, se abre en el Buscador, maximizada y al frente. Aplica dieciocho políticas de Edge (sin arranque anticipado, sin segundo plano, sin datos de diagnóstico, sin Copilot ni barra lateral), retira sus accesos directos guardando copia, ancla el Buscador a la barra y quita Bing de la búsqueda del menú Inicio. WebView2 no se toca, porque lo usan WhatsApp y la búsqueda de Windows.

Luego crea el candado del cortafuegos: una regla de salida que impide a `librewolf.exe` hablar con cualquier dirección pública de IPv4 o con `2000::/3` en IPv6. En la prueba del 2 de octubre, una conexión directa forzada quedó bloqueada en 188 ms.

Después comprueba que exista el motor en WSL, registra si falta la tarea `Buscador - Tor siempre` (al iniciar sesión, sin privilegios, reinicio cada minuto), la reinicia para que corra la última versión del vigía, espera hasta cuatro minutos a que abra el 9050 y confirma la salida por Tor:

```powershell
curl.exe --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

Por último instala `tor-elegida.sh` en Ubuntu y espera a que escuchen el motor de salida elegida (9055) y la puerta directa (9060). Si algo falla, el resumen final lo enumera.

### 9.5 Rendimiento medido el 4 de octubre

Con el perfil ya en uso (caché llena y listas de uBlock descargadas), el chat de Twitch conectó a los 5,5 segundos y recibió el primer mensaje a los 8,6; el vídeo arrancó hacia los 10 segundos. El directo de Kick arrancó a los 6,1 segundos, a 720p, sin cortes y con el chat cargado. Ese portal abrió por la salida elegida en 1,7 a 5,3 segundos en cinco circuitos distintos. Un circuito de Tor rinde unos 0,7 MB/s; tres a la vez, 1,4 MB/s, con mucha diferencia según la salida que toque. Las pruebas con un perfil recién creado exageran los tiempos, porque uBlock descarga todas sus listas antes de dejar pasar nada.

Se probó y se descartó llevar el vídeo de cada sitio por un circuito propio: el reproductor de Twitch falla con «Error #2000» si el vídeo sale por una IP distinta de la de la página. El ajuste queda apagado (`carita.pesado`).

### 9.6 Límites conocidos

Algunos sitios rechazan a toda la red Tor y solo abrirían por la puerta directa, lo que exige la autorización del propietario sitio por sitio: la Policía, el SISBÉN, Stack Overflow, Falabella y Éxito. Google pide captcha. Un aula virtual universitaria solo ofrece un cifrado CBC y además rechaza a Tor: necesitaría la puerta directa y una excepción de «TLS vigilado». Mojeek no responde por Tor y por eso se usa DuckDuckGo HTML. Si el navegador se abre por una vía distinta del lanzador, las páginas no cargan: es el comportamiento buscado, no una avería.

### 9.7 Velocidad: requisito, carrera de circuitos y afinado

A petición del propietario, la velocidad se gobierna con un requisito medible y parámetros, no con ajustes a ojo. Todo vive en `Buscador\velocidad.json`. El bloque `objetivo` fija el requisito de tiempo de respuesta, medido como segundos hasta el primer byte de la página al abrir un sitio nuevo: mediana de 1,5 s o menos, el 10 % más lento en 4 s o menos y como máximo un 2 % de respuestas de más de 10 s. Los bloques `carrera` y `navegador` contienen los parámetros de cada optimización, y `ultimo_afinado` el resultado de la última medición.

Cuatro piezas actúan sobre la respuesta. La **carrera de circuitos** (`Buscador\carrera.py`, 127.0.0.1:9070) se interpone entre el navegador y Tor: en la primera conexión de cada sitio envía el saludo TLS del navegador por dos circuitos a la vez y se queda con el primero cuyo servidor responde. Después, el sitio entero sigue por ese circuito, porque Twitch falla si un mismo sitio sale por IP distintas; las demás conexiones del sitio esperan al ganador en lugar de competir. Si la carrera no responde, el navegador pasa solo a Tor sin ella, y nunca hay salida directa. El **circuito nuevo automático** cambia de circuito a un sitio cuya página tarda más de `lento_ms` (7 s) en responder y reintenta por otro la que no respondió en `atasco_ms` (12 s), como mucho dos veces por minuto; Ctrl+Shift+L lo hace a mano. El texto se muestra a los 200 ms aunque la tipografía de la página no haya llegado (`fuentes_ms`). Y las conexiones abiertas se conservan diez minutos para no repetir el saludo TLS al volver a un sitio.

En las cuentas, el circuito nuevo automático no actúa: Outlook cambiaba de IP de salida varias veces por sesión (seis en siete minutos) porque Tor retira el circuito de un sitio cuando una petición se cuelga quince segundos en la salida, y lo que la página cargaba de terceros viajaba por ese mismo circuito. Además, pasados diez minutos Tor dejaba de usar un circuito para conexiones nuevas aunque el sitio siguiera abierto, hasta que los motores incorporaron `KeepAliveIsolateSOCKSAuth`. En las cuentas, Ctrl+Shift+L sigue dando un circuito nuevo a mano.

`Buscador\afinar.py` prueba configuraciones de la carrera, de la más barata a la más agresiva, pidiendo cada página a la vez por Tor solo y por la candidata. Se queda con la primera que cumple el objetivo, la escribe en `velocidad.json` y anota el historial en `afinado.log`. La carrera relee el archivo sola, y el lanzador pasa los umbrales del navegador al abrirlo.

El afinado del 4 de octubre no alcanzó el objetivo. La mejor configuración, dos circuitos a la vez en modo «saludo», dio una mediana de 2,4 s, un p90 de 4,2 s y un 4,2 % de respuestas lentas; Tor solo, durante toda la prueba, dio 2,5 s, 8,8 s y 9,9 %. La carrera reduce a menos de la mitad las esperas largas, pero no baja la mediana. Tres configuraciones de Tor se descartaron con datos: dos puentes con Conflux empeoraron la respuesta; Tor no admite un `CircuitStreamTimeout` menor de 10 s; y restringir los relevos a Norteamérica impidió conectar. El límite es físico. Abrir un sitio nuevo exige unas tres idas y vueltas por cuatro saltos (puente y tres relevos), de 0,6 a 0,8 s cada una, y todo pasa por un único puente público compartido. Cuando ese puente se satura, ningún circuito se salva: en un tramo de la prueba, Tor solo tuvo un 20,8 % de respuestas de más de 10 s.

## 10. Errores cometidos y lecciones

Esta sección recoge los fallos de la construcción. Varios eran silenciosos y solo se descubrieron al revisar el resultado.

**El primer blindaje dejó 78 reglas abiertas sin avisar.** `Get-NetFirewallRule -DisplayName X -Direction Inbound` no es un filtro sino un error de PowerShell, porque esos parámetros pertenecen a conjuntos distintos; un `catch` vacío lo convirtió en un cero. Además, los grupos de Windows en español llevan tildes y el código, en ASCII, no coincidía con ninguno. Desde entonces se consulta por un solo criterio, se filtra con `Where-Object` comparando sin tildes, y ningún `catch` que rodee un recuento puede quedar mudo. En la misma revisión se vio que `-EnableInsecureGuestLogons` no existe en `Set-SmbServerConfiguration` y anulaba la orden entera; los ajustes de SMB se aplican de uno en uno.

**Las reglas anti-ping no existían.** Se detectó al preparar esta guía, el 4 de octubre. El nuevo script del cortafuegos las crea y comprueba cada regla por separado.

**El blindaje sobrescribía el DNS local.** `Blindar.ps1` ponía el DNS de Cloudflare aunque Unbound estuviera en marcha, y el DoH nunca llegó a activarse: las consultas viajaron sin cifrar hasta que se corrigió.

**Cortes del Wi-Fi de diez segundos.** La línea `private-address: fd00::/8` de Unbound borraba la respuesta IPv6 de `dns.msftncsi.com`; Windows creía que no había internet y reiniciaba el controlador. Se resolvió con `private-domain: "msftncsi.com"`.

**Configuraciones vaciadas por accidente.** `[regex]::Replace(texto, patrón, reemplazo, 1)` interpreta el 1 como opción y no como límite, y reemplazó todas las llaves del `settings.json` de VS Code; se restauró desde el respaldo. `New-Item -Force` sobre una clave de registro existente la deja vacía; `Carita-Buscador.ps1` y `Apagar-Edge.ps1` lo usaban sobre claves ya existentes; el 4 de octubre se corrigieron para que solo creen la clave si falta (copias en `Respaldos\*.bak-20261004`), y el script nuevo del Buscador sigue la misma regla. Un respaldo que se reescribe en cada pasada acaba guardando valores ya endurecidos como originales; `Paranoia.ps1` fusiona en lugar de reescribir.

**TLS 1.3 obligatorio rompió el aula virtual.** No existe en Firefox una excepción de versión TLS por sitio; se bajó a 1.2 y después, por decisión del propietario, se volvió a 1.3. El 4 de octubre el propietario aceptó de nuevo TLS 1.2, con la protección «TLS vigilado» descrita en el apartado 9.3.

**Tor dejó de arrancar.** Una limpieza dejó `UseBridges 1` sin ninguna línea `Bridge`, y Tor se niega a iniciar en ese estado. Además, los puentes incorporados estaban saturados (obfs4), muertos (los WebTunnel por defecto, uno con certificado vencido) o pasaban por Azure de Microsoft (meek), que el propietario rechazó. Hoy `puentes.sh` mide y ordena los puentes por velocidad real.

**Trampas de Windows que costaron tiempo.** Un `.ps1` en UTF-8 sin BOM rompe las tildes en PowerShell 5, por eso los scripts se escriben en ASCII. Filtrar procesos por `CommandLine -match` sin limitar el nombre atrapa la propia consola y la cierra. `netsh wlan show interfaces` exige el permiso de ubicación que el blindaje cierra. El modo de edición rápida congela la consola elevada si se hace clic en ella; se libera con Esc. La comprobación de conectividad de Microsoft falla en redes que inspeccionan TLS, por lo que toda prueba de internet usa TCP crudo al 443.

**Errores del 4 de octubre, al construir el enrutado.** La primera versión del bloque de avisos pulsaba «Aceptar», cuando el propietario no quería aceptar nada. La segunda borraba los nodos de la página: Twitch, hecho con React, puede romperse cuando le quitan nodos desde fuera, y además subía hasta la primera capa fija, que en Twitch puede ser la columna entera del chat. Desde entonces el bloque solo oculta, y nunca un bloque con más contenido que el propio aviso. Se dio por hecho un cambio de puente que no había ocurrido, porque el puente en uso era el mismo, y se diagnosticó un fallo en la renovación de puentes que el código no tenía; los dos errores se corrigieron en la bitácora. Recortar cifrados del saludo TLS para «blindar» TLS 1.2 cambió la huella del navegador y lo hacía parecer un programa automático; se volvió al saludo de Firefox y la protección pasó a aplicarse después del saludo. La primera versión de esa protección cortaba la página sin mostrar nada; ahora explica qué pasó. Llevar el vídeo por un circuito propio rompió el reproductor de Twitch; una prueba con `curl` del permiso de vídeo había parecido indicar lo contrario, y la lección es probar con el navegador real. Por último, los textos largos escritos en la consola de Bash se cortaban o perdían barras invertidas: los cambios se aplican desde archivos de parche.

**Errores de la tarde del 4 de octubre, en las pruebas de velocidad.** Una prueba de diagnóstico interrumpida dejó `SafeLogging 0` en el motor Tor de uso, y durante unas dos horas su registro local anotó los nombres de los sitios visitados; se quitó la línea y se borraron esos nombres del registro. Desde entonces los diagnósticos se hacen en un Tor de pruebas aparte, nunca en el de uso. Una orden `pkill -f` se mató a sí misma porque su propia línea de comando contenía el texto buscado, y dejó vivo un Tor de pruebas; se busca con `pgrep -f "[t]exto"`. Y se propuso bajar `CircuitStreamTimeout` sin comprobar antes que Tor admitiera ese valor: el registro mostró que lo sube a 10 s.

**Errores de la noche del 4 de octubre, en la auditoría.** Se anunció como fallo serio que los temporizadores del bloque de avisos retenían las páginas viejas en memoria, y una prueba con control lo descartó: Firefox ya los cortaba al desconectar la página. Desde entonces, antes de dar algo por fallo se reproduce con una prueba que también falle sin el arreglo. La auditoría encontró además tres defectos reales. El lanzador moría sin abrir el navegador si faltaba el archivo de sesión, y como corre sin ventana nadie veía el error. La puerta directa probaba una sola dirección con veinte segundos de plazo. Y el lanzador contaba como Buscador abierto cualquier `librewolf.exe`, incluidos los de las pruebas. También se comprobó que `parent.lock` sigue en el perfil con el navegador cerrado: la señal fiable es que Windows no deje abrirlo. Tres pruebas fallaban por sí mismas, porque dependían de la velocidad de la red o de una decisión ya cambiada, y una cuarta porque `check.torproject.org` no permite que otras páginas lean su respuesta (CORS).

**Una petición que no se atendió.** Se pidió disfrazar la IP de salida de Tor como un equipo propio para hacer perder el tiempo a quien la escaneara. Esa IP pertenece a un voluntario que opera el relevo: convertirla en señuelo dirige los escaneos contra un tercero que no lo autorizó, y nada de lo configurado en este equipo cambia lo que ese relevo muestra.

## 11. Aspectos que conviene revisar

El más urgente es actualizar LibreWolf: la versión instalada es la 156.0.1 y la 157.0-1 se publicó el 28 de septiembre. Se hace con `ACTUALIZAR BUSCADOR.bat`, con el Buscador cerrado, y después conviene pasar las pruebas de `Buscador\pruebas`. El requisito de velocidad no se alcanza con un puente público compartido (apartado 9.7); la candidata que entra por el puente y sale por relevos de Estados Unidos y Canadá se acercó al objetivo, pero fijar países reduce el anonimato y la decisión corresponde al propietario. Él decide también, sitio por sitio, si los que rechazan a toda la red Tor (Policía, SISBÉN, Stack Overflow, Falabella, Éxito) pasan a `directos.txt`, y cuál será el buscador predeterminado (Bing por Tor o DuckDuckGo). Falta confirmar en el navegador real que los avisos de términos y de reglas del chat ya no aparecen en Twitch; los avisos de cookies de TikTok y Twitch ya no aparecen en las pruebas. Las dos claves de OpenRouter siguen escritas en claro en el perfil de PowerShell (`Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`) y deben rotarse. La tarea `Centinela-Punto-Diario`, que crea un punto de restauración cada día a las 13:00, sigue activa a la espera de decisión, y las cuatro tareas de ASUS continúan activas por decisión propia. Por último, desde el 25 de septiembre el equipo deja de contestar al router por IPv6 a los pocos minutos de cada conexión; con IPv4 preferido no afecta, aunque la causa no se ha aislado.

Cada actualización importante debe ir seguida de una revisión. Tras actualizar LibreWolf se pulsa `CONFIGURAR BUSCADOR COMPLETO.bat`; tras actualizar el controlador gráfico de Intel se revisa el servicio del apartado 4.3; tras una actualización grande de Windows se pulsan `VER COMO ESTA MI PC.bat` y `CONFIGURAR CORTAFUEGOS.bat`.

## 12. Botones disponibles

| Botón en `Downloads\` | Función |
|---|---|
| `BLINDAR MI PC` | Endurecimiento base en nueve capas |
| `PROTECCION NIVEL PELICULA` / `QUITAR NIVEL PELICULA` | DNS local, informes de error en local, MAC aleatoria |
| `CONFIGURAR CORTAFUEGOS` | Cortafuegos completo con reversor de 10 minutos |
| `CONFIGURAR BUSCADOR COMPLETO` | Buscador, Edge paralizado, Tor siempre, salida elegida, puerta directa y candado |
| `ACTUALIZAR BUSCADOR` | Actualiza LibreWolf verificando la firma y repone lo propio |
| `COMPROBAR MI PROTECCION` | Verificación de TLS, anuncios, conexiones, telemetría, las tres salidas del Buscador y la puerta directa |
| `VER COMO ESTA MI PC` / `VER QUE BLOQUEARIA` | Auditoría y simulacro sin cambios |
| `VER MIS INFORMES DE ERRORES` | Monitor de confiabilidad |
| `SI ME QUEDO SIN INTERNET` | Restaura red y cortafuegos desde el respaldo |
| `BLOQUEAR NODE` / `DESBLOQUEAR NODE` | Node.js solo cuando una tarea lo necesita |
| `ACTUALIZAR DRIVERS INTEL` | Asistente de Intel bajo demanda |
