# Manual del kit de blindaje y privacy para Windows 11

## 1. Qué es

El kit endurece Windows 11 Home o Pro en nueve capas, reduce la telemetría sin romper las actualizaciones, cierra el cortafuegos, resuelve los nombres de dominio en el propio equipo sin pasar por terceros y añade un navegador privado, el Browser, que sale a internet por la red Tor. Se maneja con buttons de doble clic. Cada script ofrece simulacro, guarda un respaldo antes de cambiar nada, y los que tocan la red se deshacen solos a los diez minutos si el usuario no confirma que conserva la conexión.

El kit no contiene credentials, claves, direcciones de equipo ni datos de ninguna persona. Las rutas se calculan en cada equipo a partir de la carpeta del usuario.

## 2. Estructura del paquete

```
kit-blindaje-windows\
├── INSTALL-KIT.bat          copia todo a su lugar (paso único de instalación)
├── MANUAL.md                 este documento
├── PROTECTION-GUIDE.md   detalle técnico de cada medida
├── Run-All.ps1                  orquestador del blindaje completo
├── Install.ps1              registra los lanzadores del sistema
├── Harden.ps1 · Restore.ps1 · Audit.ps1 · Audit-Admin.ps1
├── Movie-Grade.ps1        DNS local, MAC aleatoria, informes de error locales
├── Remaining-Telemetry.ps1 · Windows-Services.ps1 · Disable-Microsoft.ps1 · Disable-Edge.ps1
├── Setup-Firewall.ps1 · Network-Blocker.ps1 · Paranoia.ps1 · IP-Always-Hidden.ps1
├── Find-Backdoors.ps1 · Migrate-Launchers.ps1 · Checker.py
├── Setup-Browser.ps1 · Smiley-Browser.ps1 · Update-LibreWolf.ps1
├── lib\                      núcleo compartido (bitácora, respaldos, reversor)
├── Browser\                 lanzador, motores Tor, página de inicio y configuración
└── buttons\                  los once accesos de doble clic
```

Los respaldos, bitácoras e informes se crean en el equipo del usuario, dentro de `%USERPROFILE%\Security`, y nunca forman parte del paquete.

## 3. Requisitos

- Windows 11 Home o Pro y una cuenta de administrador.
- Python 3.11 o superior, para el Browser y el comprobador.
- Para el Browser: WSL con una distribución Ubuntu y el paquete `tor` instalado dentro de ella (`sudo apt install tor`). LibreWolf lo instala la propia configuración mediante `winget`.

## 4. Instalación

1. Cree un punto de restauración de Windows.
2. Haga doble clic en `INSTALL-KIT.bat`. Copia el kit a `%USERPROFILE%\Security` y los buttons a una carpeta «Kit de blindaje» en el Escritorio. No pide permisos de administrador ni cambia ninguna configuración.
3. Abra la carpeta del Escritorio y ejecute primero **WHAT WOULD IT BLOCK**.
4. Si el resumen le parece bien, ejecute **HARDEN MY PC**.

## 5. Los buttons

| Botón | Qué hace | Cambia el equipo |
|---|---|---|
| WHAT WOULD IT BLOCK | Simulacro del blindaje completo | No |
| HOW IS MY PC | Auditoría con puntaje por área | No |
| CHECK MY PROTECTION | Verifica DNS, cortafuegos, Tor y Browser | No |
| HARDEN MY PC | Aplica las nueve capas, con reversor de diez minutos | Sí |
| REPAIR WHAT WAS MISSED | Reaplica lo que Windows haya revertido | Sí |
| SET UP FIREWALL | Entrada cerrada y salida mínima | Sí |
| MOVIE-GRADE PROTECTION | DNS local (Unbound), MAC aleatoria, informes de error locales | Sí |
| REMOVE MOVIE-GRADE PROTECTION | Deshace el nivel película | Sí |
| SET UP BROWSER | Instala y configura el Browser | Sí |
| UPDATE BROWSER | Actualiza LibreWolf y conserva la configuración | Sí |
| IF I LOSE INTERNET | Restaura cortafuegos y servicios desde el último respaldo | Sí |

Todos piden permiso de administrador por sí solos cuando lo necesitan.

## 6. Uso manual, sin buttons

Abra PowerShell como administrador y sitúese en la carpeta del kit:

```powershell
cd $env:USERPROFILE\Security
Set-ExecutionPolicy -Scope Process Bypass
```

Sin `-Apply`, los scripts que lo admiten solo muestran lo que harían.

| Tarea | Comando |
|---|---|
| Simulacro del blindaje completo | `.\Run-All.ps1 -DryRun` |
| Blindaje completo | `.\Run-All.ps1` |
| Blindar solo algunas capas | `.\Harden.ps1 -Apply -Layers defender,ports,privacy` |
| Cambiar el plazo del reversor | `.\Harden.ps1 -Apply -RevertMinutes 15` |
| Auditoría | `.\Audit.ps1` |
| Restaurar desde un respaldo | `.\Restore.ps1 -ListBackups` y luego `.\Restore.ps1 -Backup <nombre>` |
| Restauración de emergencia | `.\Restore.ps1 -Emergency` |
| Nivel película | `.\Movie-Grade.ps1 -Apply` (solo DNS: `-DnsOnly`) |
| Remove nivel película | `.\Movie-Grade.ps1 -Revert` |
| Telemetría restante | `.\Remaining-Telemetry.ps1 -Apply` |
| Servicios de Windows | `.\Windows-Services.ps1 -Apply` |
| Cortafuegos | `.\Setup-Firewall.ps1` |
| Buscar puertas traseras | `.\Find-Backdoors.ps1` |
| Configurar el Browser | `.\Setup-Browser.ps1` |

Casi todos los scripts que cambian algo aceptan `-Revert` para deshacerlo: `Apagar-Edge`, `Apagar-Microsoft`, `Bloqueador-Red`, `Smiley-Browser`, `Configurar-Cortafuegos`, `IP-Siempre-Oculta`, `Paranoia`, `Servicios-Windows` y `Telemetria-Restante`.

## 7. El Browser

El Browser es LibreWolf con una configuración propia y una smiley amarilla como ícono. Sale a internet por Tor, que corre dentro de WSL, y no usa el DNS del proveedor. Borra cookies y caché al cerrar, salvo las de los dominios listados en `CONSERVAR`, dentro de `Browser\launch_browser.pyw`, donde el usuario agrega los sitios cuya sesión quiere mantener.

Viene con la entrada directa a Tor. Para usar puentes WebTunnel, péguelos en `~/.smiley/bridges.sh` dentro de WSL y cambie `"entrada": "puente"` en `Browser\speed.json`. Los sitios que rechazan a toda la red Tor se anotan en `Browser\direct.txt` (salen con la IP real, solo esos), y los que bloquean por país, en `Browser\chosen_exit.txt`.

## 8. Advertencias: consecuencias de usarlo

- **Cambia la configuración del sistema.** El kit toca el cortafuegos, servicios, el registro y políticas locales. Cada cambio deja respaldo, pero si algo falla el equipo puede quedarse sin internet hasta pulsar **IF I LOSE INTERNET**.
- **Algunas funciones dejan de servir.** Compartir archivos e impresoras en red, transmitir a un televisor, Wi-Fi Direct, Escritorio remoto, Teléfono vinculado, la Xbox Game Bar y las aplicaciones que abren Edge por su cuenta pueden fallar o pedir que se reactiven a mano.
- **Reducir la telemetría tiene un precio.** Microsoft puede limitar funciones o pedir verificaciones adicionales en cuentas que reportan poco. Por eso el kit no bloquea los dominios de Microsoft, y aun así el riesgo no es cero.
- **Tor no es para todo.** Muchos sitios piden captcha o bloquean la red Tor. Bancos, billeteras y plataformas de pago pueden bloquear o congelar una cuenta a la que se entra desde Tor: no los use desde el Browser. Tor oculta la IP, pero no hace anónimo a quien inicia sesión con su nombre, y lo ilegal sigue siendo ilegal. Compruebe que usar Tor sea legal en su país.
- **La MAC aleatoria** hace que las redes con filtrado por MAC o con portal de acceso traten al equipo como nuevo y pidan entrar otra vez.
- **El DNS local** depende de que Unbound esté en marcha. Si se detiene, las páginas no abren hasta reiniciarlo o quitarlo con **REMOVE MOVIE-GRADE PROTECTION**.
- **No lo use en equipos de trabajo, de estudio ni administrados por terceros** sin autorización escrita del administrador.
- **Sin garantía.** El kit se entrega tal cual. Quien lo aplica asume las consecuencias de los cambios en su equipo.

## 9. Donaciones

El kit es gratuito para uso personal. Quien quiera apoyarlo puede donar a estas direcciones de recepción:

- **Bitcoin**, solo por la red **Bitcoin (BTC)**: `1ED8zqpXYS4MspjZn29s2Bo4WQLgnMM5yi`
- **Ethereum**, solo por la red **Ethereum (ERC20)**: `0x1e47c2a6f0401f4df82bf2c83238608a354da696`

Antes de donar, tenga en cuenta lo siguiente:

- **Use exactamente la red indicada.** Un envío por otra red (BEP20, TRC20, Arbitrum u otra) o de otra moneda a estas direcciones se pierde y no se puede recuperar.
- **Copie la dirección de este repositorio oficial y compruebe los primeros y los últimos caracteres** antes de enviar. Hay programas maliciosos que cambian la dirección copiada en el portapapeles.
- **Las donaciones son voluntarias y no reembolsables.** No compran soporte, garantía ni prioridad.
- **Nadie del proyecto le pedirá jamás** frases semilla, claves privadas, contraseñas ni códigos de verificación. Quien lo haga en nombre del proyecto es un estafador.
- Las direcciones pertenecen a una cuenta de un exchange. Si alguna cambia, la vigente será siempre la de este manual en el repositorio oficial.

## 10. Desinstalar

1. Pulse **REMOVE MOVIE-GRADE PROTECTION** si lo aplicó.
2. En PowerShell como administrador, desde `%USERPROFILE%\Security`, ejecute `.\Restore.ps1 -ListBackups` y restaure el respaldo anterior al blindaje con `.\Restore.ps1 -Backup <nombre>`.
3. Quite los lanzadores registrados con `.\Install.ps1 -Remove`.
4. Borre la carpeta `%USERPROFILE%\Security` y la carpeta «Kit de blindaje» del Escritorio.
