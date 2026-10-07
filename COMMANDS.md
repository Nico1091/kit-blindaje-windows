# Guía de comandos

Cada script del kit, qué hace, si cambia el equipo y qué significa cada opción. Todos se ejecutan desde PowerShell abierto como administrador, situado en la carpeta del kit:

```powershell
cd $env:USERPROFILE\Security
Set-ExecutionPolicy -Scope Process Bypass
```

La segunda línea permite ejecutar los scripts solo en esa ventana; al cerrarla, la política vuelve a ser la de siempre.

Regla general: los scripts que tienen la opción `-Apply` no cambian nada si no se la pasa, solo muestran lo que harían. Los que tienen `-Revert` deshacen sus propios cambios a partir del respaldo que guardaron al aplicarlos.

---

## Blindaje principal

### Run-All.ps1
Ejecuta el blindaje completo en el orden correcto: comprueba que haya internet antes de empezar, audita, aplica las nueve capas de `Harden.ps1`, registra el punto de restauración diario y pregunta al final si sigue habiendo conexión. Es lo que corre el botón **HARDEN MY PC**.

- `-DryRun`: recorre todo el proceso sin cambiar nada. Equivale al botón **WHAT WOULD IT BLOCK**.
- `-RevertMinutes <n>`: minutos que espera el reversor antes de deshacer los cambios de red si nadie confirma la conexión. Por defecto, 10.

```powershell
.\Run-All.ps1 -DryRun
.\Run-All.ps1
```

### Harden.ps1
Aplica el blindaje por capas, con respaldo previo, comprobación de conectividad después de cada capa y reversor temporizado. Sin `-Apply` no cambia nada.

Las nueve capas son: `defender` (Defender al máximo, acceso controlado a carpetas, reglas de reducción de la superficie de ataque), `ports` (cortafuegos estricto y cierre de WinRM y del servidor SMB), `locks` (UAC al máximo, Windows Script Host apagado, PowerShell 2 retirado, sin ejecución automática de USB), `privacy` (telemetría al mínimo, ubicación cerrada), `stealth` (el equipo deja de anunciarse en la red y de responder al ping), `vm` (las máquinas virtuales dejan de ver la red local), `drivers` (bloqueo de controladores vulnerables que usa el ransomware), `credentials` (sin contraseñas en claro en memoria, solo TLS moderno) y `ransomware` (carpetas protegidas y puntos de restauración).

- `-Apply`: aplica de verdad.
- `-Layers <lista>`: aplica solo las capas indicadas, separadas por comas.
- `-RevertMinutes <n>`: plazo del reversor de red. Por defecto, 10.
- `-NoPrompt`: no pide confirmaciones intermedias.
- `-RandomizeMAC`: además cambia la MAC del Wi-Fi. Desconecta y reconecta la red.
- `-CutMicrosoftProbe`: apaga la comprobación de conectividad de Windows. La ganancia de privacy es mínima y el ícono de red mostrará «sin internet» aunque navegue bien.
- `-Orchestrated`: lo usa `Run-All.ps1` al llamarlo; no hace falta escribirlo a mano.
- `-BlockOutbound`: está declarada pero el código no la usa todavía. No tiene efecto.

```powershell
.\Harden.ps1
.\Harden.ps1 -Apply
.\Harden.ps1 -Apply -Layers defender,credentials,ransomware
```

### Restore.ps1
Deshace lo que hizo `Harden.ps1`. Sin opciones, muestra los respaldos y restaura el último por completo: cortafuegos, registro y servicios.

- `-Emergency`: restaura solo la red, rápido y sin preguntas. Es lo que corre el botón **IF I LOSE INTERNET**.
- `-ListBackups`: muestra los respaldos disponibles sin restaurar ninguno.
- `-Backup <nombre>`: restaura un respaldo concreto.
- `-NoPrompt`: no pide confirmación.

```powershell
.\Restore.ps1 -ListBackups
.\Restore.ps1 -Backup <nombre>
.\Restore.ps1 -Emergency
```

### Audit.ps1
Revisa el estado de seguridad, lo puntúa por áreas y escribe un informe en `Informes\`. Solo lee: nunca cambia nada. Es lo que corre **HOW IS MY PC**.

- `-Cfa`: añade el registro de bloqueos del acceso controlado a carpetas.
- `-Days <n>`: cuántos días hacia atrás revisa ese registro.

```powershell
.\Audit.ps1
.\Audit.ps1 -Cfa -Days 7
```

### Install.ps1
Registra la única tarea programada del kit: un punto de restauración diario a las 13:00. No instala vigilancia ni procesos en segundo plano.

- `-Remove`: elimina esa tarea.

---

## Privacidad y telemetría

### Movie-Grade.ps1
Protección local de consumo casi nulo. Instala Unbound para resolver los nombres de dominio en el propio equipo, consultando directamente a los servidores raíz sin ningún DNS de terceros. También pone una MAC aleatoria por red Wi-Fi y guarda los informes de error en el equipo en lugar de enviarlos. Sin `-Apply` no cambia nada. No bloquea dominios de Microsoft: la activación, la Tienda y Windows Update siguen funcionando.

- `-Apply`: aplica, con reversor de red.
- `-Revert`: deja la red y los ajustes como estaban.
- `-DnsOnly`: solo reescribe la configuración de Unbound, sin tocar MAC ni DNS del adaptador.
- `-RevertMinutes <n>`: plazo del reversor. Por defecto, 10.
- `-NetworkOnly` y `-Auto`: los usa el reversor automático. No hace falta escribirlos.

```powershell
.\Movie-Grade.ps1
.\Movie-Grade.ps1 -Apply
.\Movie-Grade.ps1 -Revert
```

### Remaining-Telemetry.ps1
Apaga la telemetría que queda después del blindaje, usando solo interruptores oficiales. En el usuario: Office, consejos y sugerencias de Windows, PowerShell 7, .NET, VS Code y Claude Code. En el equipo: políticas de Edge y tareas de diagnóstico. No bloquea dominios ni toca la activación, la Tienda ni Windows Update. Sin `-Apply` no cambia nada.

- `-Apply` / `-Revert`.
- `-UserOnly`: aplica solo la parte del usuario, que no necesita administrador.

### Windows-Services.ps1
Apaga servicios que casi nadie usa: mapas sin conexión, rastreo de vínculos en red, asistente de compatibilidad de programas y el indexador de búsqueda, que guarda un índice con el nombre y el contenido de los archivos. Sin `-Apply` no cambia nada.

- `-Apply` / `-Revert`.

### Disable-Microsoft.ps1
Apaga la IA de Windows, la telemetría restante y los extras de Office sin tocar Word ni sus parches de seguridad. El estado anterior queda respaldado.

- `-Revert`: devuelve lo apagado.

### Disable-Edge.ps1
Deja Edge inservible sin desinstalarlo: cuando algo intenta abrirlo, se abre el Browser. WebView2 no se toca, porque lo usan otras aplicaciones.

- `-Revert`: devuelve Edge.

### Paranoia.ps1
Cierra lo que todavía salía del equipo hacia Microsoft, hacia internet o hacia la red local: historial de actividad, portapapeles en la nube y servicios similares. No toca la telemetría base ni bloquea dominios de Microsoft.

- `-Revert`: devuelve el estado original desde su respaldo.

---

## Red y cortafuegos

### Setup-Firewall.ps1
Configura el cortafuegos completo en una sola pasada: entrada cerrada, reglas sobrantes desactivadas, asistencia remota apagada y el candado del Browser. Exporta la configuración antes de tocar nada y se puede repetir sin daño. Es lo que corre **SET UP FIREWALL**.

- `-Revert`: importa la configuración exportada antes del cambio.
- `-NoPause`: no espera una tecla al terminar.

### Network-Blocker.ps1
Corta anuncios y dominios de malware en el DNS local (Unbound) para todo el equipo. No incluye dominios de Microsoft ni los sitios cuya sesión conserva el Browser. Requiere el nivel película aplicado.

- `-List <archivo>`: lista de dominios a bloquear, en formato de Unbound. Es obligatoria al aplicar.
- `-Revert`: quita el bloqueo.

### IP-Always-Hidden.ps1
Pone un candado en el cortafuegos: LibreWolf solo puede hablar con el propio equipo, donde está la entrada a Tor, y con la red local. Si un ajuste fallara o el navegador intentara una salida directa, el cortafuegos la corta y la IP sigue oculta.

- `-Revert`: quita el candado.

---

## Browser

### Setup-Browser.ps1
Deja el Browser completo en una sola pasada: instala LibreWolf, aplica su configuración y el ícono de la smiley, paraliza y redirige Edge, copia los motores de Tor a WSL, deja la salida por Tor siempre encendida y pone el candado del cortafuegos. Es lo que corre **SET UP BROWSER**.

- `-NoPause`: no espera una tecla al terminar.

### Smiley-Browser.ps1
Pone el ícono de la smiley en la ventana del Browser y hace que la búsqueda del menú Inicio no envíe lo escrito a Bing.

- `-Revert`: lo quita.

### Update-LibreWolf.ps1
Descarga la última versión oficial de LibreWolf y vuelve a colocar lo propio que el instalador puede borrar: la configuración del Browser, las políticas y los íconos. Es lo que corre **UPDATE BROWSER**.

- `-NoPause`: no espera una tecla al terminar.

### Checker.py
Verifica que todo siga en pie: DNS local, motores de Tor, puerta directa, carrera de circuitos y salida real por Tor. Solo lee. Es lo que corre **CHECK MY PROTECTION**.

```powershell
python .\Checker.py
```

### Archivos de configuración del Browser
- `Browser\launch_browser.pyw`, lista `CONSERVAR`: dominios cuya sesión se mantiene al cerrar.
- `Browser\direct.txt`: sitios que rechazan a toda la red Tor y salen con la IP real. Solo esos sitios.
- `Browser\chosen_exit.txt`: sitios que bloquean por país; salen por Tor, pero solo por relevos de los países de la línea `paises:`.
- `Browser\speed.json`: entrada a Tor (`directo` o `puente`) y parámetros de velocidad.

Después de cambiar cualquiera de ellos, cierre y abra el Browser.

---

## Diagnóstico

### Find-Backdoors.ps1
Busca puertas traseras y mecanismos de persistencia: cuentas, claves SSH autorizadas, paquetes de autenticación, entradas de inicio, tareas y servicios. Solo lee. Deja el informe en `Informes\`. Como administrador ve todo; sin permisos se salta lo protegido.

### Audit-Admin.ps1
Repite la auditoría de firmas digitales incluyendo los procesos protegidos del sistema, que sin permisos no muestran su ruta. Deja el informe en `Informes\`.

### Migrate-Launchers.ps1
Sustituye lanzadores `.vbs` conocidos por accesos directos que no necesitan Windows Script Host, para que la capa `locks` pueda apagarlo sin romperlos. Si no encuentra esos lanzadores, no hace nada. Sin `-Apply` solo muestra lo que haría.
