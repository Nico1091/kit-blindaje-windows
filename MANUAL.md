# Manual del kit de blindaje y privacidad para Windows 11

## 1. Qué es

El kit endurece Windows 11 Home o Pro en nueve capas, reduce la telemetría sin romper las actualizaciones, cierra el cortafuegos, resuelve los nombres de dominio en el propio equipo sin pasar por terceros y añade un navegador privado, el Buscador, que sale a internet por la red Tor. Se maneja con botones de doble clic. Cada script ofrece simulacro, guarda un respaldo antes de cambiar nada, y los que tocan la red se deshacen solos a los diez minutos si el usuario no confirma que conserva la conexión.

El kit no contiene credenciales, claves, direcciones de equipo ni datos de ninguna persona. Las rutas se calculan en cada equipo a partir de la carpeta del usuario.

## 2. Estructura del paquete

```
kit-blindaje-windows\
├── INSTALAR-KIT.bat          copia todo a su lugar (paso único de instalación)
├── MANUAL.md                 este documento
├── GUIA-PROTECCION-DEL-EQUIPO.md   detalle técnico de cada medida
├── Todo.ps1                  orquestador del blindaje completo
├── Instalar.ps1              registra los lanzadores del sistema
├── Blindar.ps1 · Restaurar.ps1 · Auditar.ps1 · Auditoria-Admin.ps1
├── Nivel-Pelicula.ps1        DNS local, MAC aleatoria, informes de error locales
├── Telemetria-Restante.ps1 · Servicios-Windows.ps1 · Apagar-Microsoft.ps1 · Apagar-Edge.ps1
├── Configurar-Cortafuegos.ps1 · Bloqueador-Red.ps1 · Paranoia.ps1 · IP-Siempre-Oculta.ps1
├── Buscar-Puertas-Traseras.ps1 · Migrar-Lanzadores.ps1 · Comprobador.py
├── Configurar-Buscador.ps1 · Carita-Buscador.ps1 · Actualizar-LibreWolf.ps1
├── lib\                      núcleo compartido (bitácora, respaldos, reversor)
├── Buscador\                 lanzador, motores Tor, página de inicio y configuración
└── botones\                  los once accesos de doble clic
```

Los respaldos, bitácoras e informes se crean en el equipo del usuario, dentro de `%USERPROFILE%\Seguridad`, y nunca forman parte del paquete.

## 3. Requisitos

- Windows 11 Home o Pro y una cuenta de administrador.
- Python 3.11 o superior, para el Buscador y el comprobador.
- Para el Buscador: WSL con una distribución Ubuntu y el paquete `tor` instalado dentro de ella (`sudo apt install tor`). LibreWolf lo instala la propia configuración mediante `winget`.

## 4. Instalación

1. Cree un punto de restauración de Windows.
2. Haga doble clic en `INSTALAR-KIT.bat`. Copia el kit a `%USERPROFILE%\Seguridad` y los botones a una carpeta «Kit de blindaje» en el Escritorio. No pide permisos de administrador ni cambia ninguna configuración.
3. Abra la carpeta del Escritorio y ejecute primero **VER QUE BLOQUEARIA**.
4. Si el resumen le parece bien, ejecute **BLINDAR MI PC**.

## 5. Los botones

| Botón | Qué hace | Cambia el equipo |
|---|---|---|
| VER QUE BLOQUEARIA | Simulacro del blindaje completo | No |
| VER COMO ESTA MI PC | Auditoría con puntaje por área | No |
| COMPROBAR MI PROTECCION | Verifica DNS, cortafuegos, Tor y Buscador | No |
| BLINDAR MI PC | Aplica las nueve capas, con reversor de diez minutos | Sí |
| REPARAR LO QUE FALTO | Reaplica lo que Windows haya revertido | Sí |
| CONFIGURAR CORTAFUEGOS | Entrada cerrada y salida mínima | Sí |
| PROTECCION NIVEL PELICULA | DNS local (Unbound), MAC aleatoria, informes de error locales | Sí |
| QUITAR NIVEL PELICULA | Deshace el nivel película | Sí |
| CONFIGURAR BUSCADOR COMPLETO | Instala y configura el Buscador | Sí |
| ACTUALIZAR BUSCADOR | Actualiza LibreWolf y conserva la configuración | Sí |
| SI ME QUEDO SIN INTERNET | Restaura cortafuegos y servicios desde el último respaldo | Sí |

Todos piden permiso de administrador por sí solos cuando lo necesitan.

## 6. Uso manual, sin botones

Abra PowerShell como administrador y sitúese en la carpeta del kit:

```powershell
cd $env:USERPROFILE\Seguridad
Set-ExecutionPolicy -Scope Process Bypass
```

Sin `-Aplicar`, los scripts que lo admiten solo muestran lo que harían.

| Tarea | Comando |
|---|---|
| Simulacro del blindaje completo | `.\Todo.ps1 -SoloSimulacro` |
| Blindaje completo | `.\Todo.ps1` |
| Blindar solo algunas capas | `.\Blindar.ps1 -Aplicar -Capas defender,puertos,privacidad` |
| Cambiar el plazo del reversor | `.\Blindar.ps1 -Aplicar -MinutosReversor 15` |
| Auditoría | `.\Auditar.ps1` |
| Restaurar desde un respaldo | `.\Restaurar.ps1 -Listar` y luego `.\Restaurar.ps1 -Respaldo <nombre>` |
| Restauración de emergencia | `.\Restaurar.ps1 -Emergencia` |
| Nivel película | `.\Nivel-Pelicula.ps1 -Aplicar` (solo DNS: `-SoloDns`) |
| Quitar nivel película | `.\Nivel-Pelicula.ps1 -Revertir` |
| Telemetría restante | `.\Telemetria-Restante.ps1 -Aplicar` |
| Servicios de Windows | `.\Servicios-Windows.ps1 -Aplicar` |
| Cortafuegos | `.\Configurar-Cortafuegos.ps1` |
| Buscar puertas traseras | `.\Buscar-Puertas-Traseras.ps1` |
| Configurar el Buscador | `.\Configurar-Buscador.ps1` |

Casi todos los scripts que cambian algo aceptan `-Revertir` para deshacerlo: `Apagar-Edge`, `Apagar-Microsoft`, `Bloqueador-Red`, `Carita-Buscador`, `Configurar-Cortafuegos`, `IP-Siempre-Oculta`, `Paranoia`, `Servicios-Windows` y `Telemetria-Restante`.

## 7. El Buscador

El Buscador es LibreWolf con una configuración propia y una carita amarilla como ícono. Sale a internet por Tor, que corre dentro de WSL, y no usa el DNS del proveedor. Borra cookies y caché al cerrar, salvo las de los dominios listados en `CONSERVAR`, dentro de `Buscador\lanzar_buscador.pyw`, donde el usuario agrega los sitios cuya sesión quiere mantener.

Viene con la entrada directa a Tor. Para usar puentes WebTunnel, péguelos en `~/.carita/puentes.sh` dentro de WSL y cambie `"entrada": "puente"` en `Buscador\velocidad.json`. Los sitios que rechazan a toda la red Tor se anotan en `Buscador\directos.txt` (salen con la IP real, solo esos), y los que bloquean por país, en `Buscador\salida_elegida.txt`.

## 8. Advertencias: consecuencias de usarlo

- **Cambia la configuración del sistema.** El kit toca el cortafuegos, servicios, el registro y políticas locales. Cada cambio deja respaldo, pero si algo falla el equipo puede quedarse sin internet hasta pulsar **SI ME QUEDO SIN INTERNET**.
- **Algunas funciones dejan de servir.** Compartir archivos e impresoras en red, transmitir a un televisor, Wi-Fi Direct, Escritorio remoto, Teléfono vinculado, la Xbox Game Bar y las aplicaciones que abren Edge por su cuenta pueden fallar o pedir que se reactiven a mano.
- **Reducir la telemetría tiene un precio.** Microsoft puede limitar funciones o pedir verificaciones adicionales en cuentas que reportan poco. Por eso el kit no bloquea los dominios de Microsoft, y aun así el riesgo no es cero.
- **Tor no es para todo.** Muchos sitios piden captcha o bloquean la red Tor. Bancos, billeteras y plataformas de pago pueden bloquear o congelar una cuenta a la que se entra desde Tor: no los use desde el Buscador. Tor oculta la IP, pero no hace anónimo a quien inicia sesión con su nombre, y lo ilegal sigue siendo ilegal. Compruebe que usar Tor sea legal en su país.
- **La MAC aleatoria** hace que las redes con filtrado por MAC o con portal de acceso traten al equipo como nuevo y pidan entrar otra vez.
- **El DNS local** depende de que Unbound esté en marcha. Si se detiene, las páginas no abren hasta reiniciarlo o quitarlo con **QUITAR NIVEL PELICULA**.
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

1. Pulse **QUITAR NIVEL PELICULA** si lo aplicó.
2. En PowerShell como administrador, desde `%USERPROFILE%\Seguridad`, ejecute `.\Restaurar.ps1 -Listar` y restaure el respaldo anterior al blindaje con `.\Restaurar.ps1 -Respaldo <nombre>`.
3. Quite los lanzadores registrados con `.\Instalar.ps1 -Quitar`.
4. Borre la carpeta `%USERPROFILE%\Seguridad` y la carpeta «Kit de blindaje» del Escritorio.
