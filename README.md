# Kit de blindaje y privacidad para Windows 11

Endurecimiento de Windows 11 Home o Pro en nueve capas, reducción de telemetría sin romper las actualizaciones, cortafuegos estricto, resolución de nombres local sin terceros y un navegador privado («Buscador») que sale a internet por la red Tor. Todo funciona con botones de doble clic. Ningún cambio se aplica sin respaldo previo, y los que tocan la red se deshacen solos a los diez minutos si usted no confirma que sigue teniendo internet.

## Qué trae

| Botón (carpeta `botones`) | Qué hace |
|---|---|
| VER QUE BLOQUEARIA | Simulacro: muestra lo que cambiaría, sin tocar nada |
| BLINDAR MI PC | Aplica las nueve capas: Defender, puertos, cerrojos, privacidad, sigilo, máquinas virtuales, controladores, credenciales y ransomware |
| VER COMO ESTA MI PC | Auditoría con puntaje por área |
| CONFIGURAR CORTAFUEGOS | Bloquea la entrada y deja salir solo lo necesario |
| PROTECCION NIVEL PELICULA | Resolución de nombres local (Unbound), MAC aleatoria e informes de error guardados en el equipo |
| QUITAR NIVEL PELICULA | Deshace lo anterior |
| CONFIGURAR BUSCADOR COMPLETO | Instala y configura el navegador privado |
| ACTUALIZAR BUSCADOR | Actualiza LibreWolf y conserva la configuración |
| COMPROBAR MI PROTECCION | Verifica que todo siga en pie |
| REPARAR LO QUE FALTO | Vuelve a aplicar lo que Windows haya revertido |
| SI ME QUEDO SIN INTERNET | Restaura cortafuegos y servicios desde el último respaldo |

La guía completa, con cada medida, su comando y cómo se deshace, está en `GUIA-PROTECCION-DEL-EQUIPO.md`.

## Requisitos

- Windows 11 Home o Pro, con una cuenta de administrador.
- Python 3.11 o superior, para el Buscador y el comprobador.
- Para el Buscador: WSL con una distribución Ubuntu y el paquete `tor` instalado dentro (`sudo apt install tor`). LibreWolf se instala con `winget` durante la configuración.

## Instalación

1. Copie el contenido de este paquete a `%USERPROFILE%\Seguridad`. Los botones y los scripts buscan esa carpeta.
2. Copie los archivos de `botones` al lugar donde quiera tenerlos (Escritorio o Descargas).
3. Ejecute primero **VER QUE BLOQUEARIA** y lea el resumen.
4. Si está de acuerdo, ejecute **BLINDAR MI PC**. Los botones piden permiso de administrador por sí solos.

## Lo que conviene saber antes

- Defender sigue activo. El kit lo refuerza, no lo reemplaza.
- La telemetría de Windows se reduce, pero no se bloquean los dominios de Microsoft: hacerlo puede romper las actualizaciones y la activación.
- El Buscador viene con la entrada directa a Tor. Los puentes (WebTunnel) son opcionales: se pegan en `~/.carita/puentes.sh` dentro de WSL y se cambia `"entrada": "puente"` en `Buscador\velocidad.json`.
- Los sitios que deben salir sin Tor se anotan en `Buscador\directos.txt`, y los que bloquean por país, en `Buscador\salida_elegida.txt`.

## Advertencias: consecuencias de usarlo

Lea esto antes de pulsar cualquier botón que no sea un simulacro.

- **Cambia la configuración del sistema.** Toca el cortafuegos, servicios de Windows, el registro y políticas locales. Cada cambio deja respaldo, pero si algo sale mal usted puede quedarse sin internet hasta pulsar **SI ME QUEDO SIN INTERNET**.
- **Algunas funciones dejan de servir.** Compartir archivos e impresoras en red, transmitir a un televisor, Wi-Fi Direct, Escritorio remoto, Teléfono vinculado, la Xbox Game Bar y las aplicaciones que abren Edge por su cuenta (widgets, ayuda) pueden fallar o pedir que se reactiven a mano.
- **Reducir la telemetría tiene un precio.** Microsoft puede limitar funciones o pedir verificaciones adicionales en cuentas que reportan poco. Por eso el kit no bloquea los dominios de Microsoft, y aun así el riesgo no es cero.
- **Tor no es para todo.** Muchos sitios piden captcha o bloquean la red Tor. Los bancos, las billeteras y las plataformas de pago pueden bloquear o congelar una cuenta a la que se entra desde Tor: no los use desde el Buscador. Tor oculta su IP, no lo vuelve anónimo si inicia sesión con su nombre, y lo que sea ilegal sigue siéndolo. Verifique que usar Tor sea legal donde usted vive.
- **La MAC aleatoria** hace que las redes con filtrado por MAC o con portal de acceso (hoteles, universidades) lo traten como un equipo nuevo y le pidan entrar otra vez.
- **La resolución de nombres local** depende de que Unbound esté corriendo. Si se detiene, las páginas no abren hasta que se reinicie o se quite con **QUITAR NIVEL PELICULA**.
- **No lo use en equipos de trabajo, de estudio ni administrados por otra persona** sin autorización escrita del administrador: puede violar sus políticas y dejar el equipo fuera de su gestión.
- **Haga un punto de restauración** de Windows antes de empezar.

## Licencia y donaciones

Gratis para uso personal en sus propios equipos. Puede modificarlo para usted, pero no venderlo. Se entrega tal cual, sin garantía de ningún tipo: usted asume las consecuencias de los cambios que aplique.

Si le sirvió, puede apoyar el proyecto con una donación. Solo se publican direcciones para **recibir**: nadie de este proyecto le pedirá jamás frases semilla, claves ni contraseñas, y cualquiera que lo haga a nombre del proyecto es un estafador.
