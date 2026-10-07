# Guía de comandos

Cada script del kit, qué hace, si cambia el equipo y qué significa cada opción. Todos se ejecutan desde PowerShell abierto como administrador, situado en la carpeta del kit:

```powershell
cd $env:USERPROFILE\Seguridad
Set-ExecutionPolicy -Scope Process Bypass
```

La segunda línea permite ejecutar los scripts solo en esa ventana; al cerrarla, la política vuelve a ser la de siempre.

Regla general: los scripts que tienen la opción `-Aplicar` no cambian nada si no se la pasa, solo muestran lo que harían. Los que tienen `-Revertir` deshacen sus propios cambios a partir del respaldo que guardaron al aplicarlos.

---

## Blindaje principal

### Todo.ps1
Ejecuta el blindaje completo en el orden correcto: comprueba que haya internet antes de empezar, audita, aplica las nueve capas de `Blindar.ps1`, registra el punto de restauración diario y pregunta al final si sigue habiendo conexión. Es lo que corre el botón **BLINDAR MI PC**.

- `-SoloSimulacro`: recorre todo el proceso sin cambiar nada. Equivale al botón **VER QUE BLOQUEARIA**.
- `-MinutosReversor <n>`: minutos que espera el reversor antes de deshacer los cambios de red si nadie confirma la conexión. Por defecto, 10.

```powershell
.\Todo.ps1 -SoloSimulacro
.\Todo.ps1
```

### Blindar.ps1
Aplica el blindaje por capas, con respaldo previo, comprobación de conectividad después de cada capa y reversor temporizado. Sin `-Aplicar` no cambia nada.

Las nueve capas son: `defender` (Defender al máximo, acceso controlado a carpetas, reglas de reducción de la superficie de ataque), `puertos` (cortafuegos estricto y cierre de WinRM y del servidor SMB), `cerrojos` (UAC al máximo, Windows Script Host apagado, PowerShell 2 retirado, sin ejecución automática de USB), `privacidad` (telemetría al mínimo, ubicación cerrada), `sigilo` (el equipo deja de anunciarse en la red y de responder al ping), `vm` (las máquinas virtuales dejan de ver la red local), `drivers` (bloqueo de controladores vulnerables que usa el ransomware), `credenciales` (sin contraseñas en claro en memoria, solo TLS moderno) y `ransomware` (carpetas protegidas y puntos de restauración).

- `-Aplicar`: aplica de verdad.
- `-Capas <lista>`: aplica solo las capas indicadas, separadas por comas.
- `-MinutosReversor <n>`: plazo del reversor de red. Por defecto, 10.
- `-SinPreguntar`: no pide confirmaciones intermedias.
- `-AleatorizarMAC`: además cambia la MAC del Wi-Fi. Desconecta y reconecta la red.
- `-CortarSondeoMicrosoft`: apaga la comprobación de conectividad de Windows. La ganancia de privacidad es mínima y el ícono de red mostrará «sin internet» aunque navegue bien.
- `-Orquestado`: lo usa `Todo.ps1` al llamarlo; no hace falta escribirlo a mano.
- `-BloquearSalida`: está declarada pero el código no la usa todavía. No tiene efecto.

```powershell
.\Blindar.ps1
.\Blindar.ps1 -Aplicar
.\Blindar.ps1 -Aplicar -Capas defender,credenciales,ransomware
```

### Restaurar.ps1
Deshace lo que hizo `Blindar.ps1`. Sin opciones, muestra los respaldos y restaura el último por completo: cortafuegos, registro y servicios.

- `-Emergencia`: restaura solo la red, rápido y sin preguntas. Es lo que corre el botón **SI ME QUEDO SIN INTERNET**.
- `-Listar`: muestra los respaldos disponibles sin restaurar ninguno.
- `-Respaldo <nombre>`: restaura un respaldo concreto.
- `-SinPreguntar`: no pide confirmación.

```powershell
.\Restaurar.ps1 -Listar
.\Restaurar.ps1 -Respaldo <nombre>
.\Restaurar.ps1 -Emergencia
```

### Auditar.ps1
Revisa el estado de seguridad, lo puntúa por áreas y escribe un informe en `Informes\`. Solo lee: nunca cambia nada. Es lo que corre **VER COMO ESTA MI PC**.

- `-Cfa`: añade el registro de bloqueos del acceso controlado a carpetas.
- `-Dias <n>`: cuántos días hacia atrás revisa ese registro.

```powershell
.\Auditar.ps1
.\Auditar.ps1 -Cfa -Dias 7
```

### Instalar.ps1
Registra la única tarea programada del kit: un punto de restauración diario a las 13:00. No instala vigilancia ni procesos en segundo plano.

- `-Quitar`: elimina esa tarea.

---

## Privacidad y telemetría

### Nivel-Pelicula.ps1
Protección local de consumo casi nulo. Instala Unbound para resolver los nombres de dominio en el propio equipo, consultando directamente a los servidores raíz sin ningún DNS de terceros. También pone una MAC aleatoria por red Wi-Fi y guarda los informes de error en el equipo en lugar de enviarlos. Sin `-Aplicar` no cambia nada. No bloquea dominios de Microsoft: la activación, la Tienda y Windows Update siguen funcionando.

- `-Aplicar`: aplica, con reversor de red.
- `-Revertir`: deja la red y los ajustes como estaban.
- `-SoloDns`: solo reescribe la configuración de Unbound, sin tocar MAC ni DNS del adaptador.
- `-MinutosReversor <n>`: plazo del reversor. Por defecto, 10.
- `-SoloRed` y `-Auto`: los usa el reversor automático. No hace falta escribirlos.

```powershell
.\Nivel-Pelicula.ps1
.\Nivel-Pelicula.ps1 -Aplicar
.\Nivel-Pelicula.ps1 -Revertir
```

### Telemetria-Restante.ps1
Apaga la telemetría que queda después del blindaje, usando solo interruptores oficiales. En el usuario: Office, consejos y sugerencias de Windows, PowerShell 7, .NET, VS Code y Claude Code. En el equipo: políticas de Edge y tareas de diagnóstico. No bloquea dominios ni toca la activación, la Tienda ni Windows Update. Sin `-Aplicar` no cambia nada.

- `-Aplicar` / `-Revertir`.
- `-SoloUsuario`: aplica solo la parte del usuario, que no necesita administrador.

### Servicios-Windows.ps1
Apaga servicios que casi nadie usa: mapas sin conexión, rastreo de vínculos en red, asistente de compatibilidad de programas y el indexador de búsqueda, que guarda un índice con el nombre y el contenido de los archivos. Sin `-Aplicar` no cambia nada.

- `-Aplicar` / `-Revertir`.

### Apagar-Microsoft.ps1
Apaga la IA de Windows, la telemetría restante y los extras de Office sin tocar Word ni sus parches de seguridad. El estado anterior queda respaldado.

- `-Revertir`: devuelve lo apagado.

### Apagar-Edge.ps1
Deja Edge inservible sin desinstalarlo: cuando algo intenta abrirlo, se abre el Buscador. WebView2 no se toca, porque lo usan otras aplicaciones.

- `-Revertir`: devuelve Edge.

### Paranoia.ps1
Cierra lo que todavía salía del equipo hacia Microsoft, hacia internet o hacia la red local: historial de actividad, portapapeles en la nube y servicios similares. No toca la telemetría base ni bloquea dominios de Microsoft.

- `-Revertir`: devuelve el estado original desde su respaldo.

---

## Red y cortafuegos

### Configurar-Cortafuegos.ps1
Configura el cortafuegos completo en una sola pasada: entrada cerrada, reglas sobrantes desactivadas, asistencia remota apagada y el candado del Buscador. Exporta la configuración antes de tocar nada y se puede repetir sin daño. Es lo que corre **CONFIGURAR CORTAFUEGOS**.

- `-Revertir`: importa la configuración exportada antes del cambio.
- `-SinPausa`: no espera una tecla al terminar.

### Bloqueador-Red.ps1
Corta anuncios y dominios de malware en el DNS local (Unbound) para todo el equipo. No incluye dominios de Microsoft ni los sitios cuya sesión conserva el Buscador. Requiere el nivel película aplicado.

- `-Lista <archivo>`: lista de dominios a bloquear, en formato de Unbound. Es obligatoria al aplicar.
- `-Revertir`: quita el bloqueo.

### IP-Siempre-Oculta.ps1
Pone un candado en el cortafuegos: LibreWolf solo puede hablar con el propio equipo, donde está la entrada a Tor, y con la red local. Si un ajuste fallara o el navegador intentara una salida directa, el cortafuegos la corta y la IP sigue oculta.

- `-Revertir`: quita el candado.

---

## Buscador

### Configurar-Buscador.ps1
Deja el Buscador completo en una sola pasada: instala LibreWolf, aplica su configuración y el ícono de la carita, paraliza y redirige Edge, copia los motores de Tor a WSL, deja la salida por Tor siempre encendida y pone el candado del cortafuegos. Es lo que corre **CONFIGURAR BUSCADOR COMPLETO**.

- `-SinPausa`: no espera una tecla al terminar.

### Carita-Buscador.ps1
Pone el ícono de la carita en la ventana del Buscador y hace que la búsqueda del menú Inicio no envíe lo escrito a Bing.

- `-Revertir`: lo quita.

### Actualizar-LibreWolf.ps1
Descarga la última versión oficial de LibreWolf y vuelve a colocar lo propio que el instalador puede borrar: la configuración del Buscador, las políticas y los íconos. Es lo que corre **ACTUALIZAR BUSCADOR**.

- `-SinPausa`: no espera una tecla al terminar.

### Comprobador.py
Verifica que todo siga en pie: DNS local, motores de Tor, puerta directa, carrera de circuitos y salida real por Tor. Solo lee. Es lo que corre **COMPROBAR MI PROTECCION**.

```powershell
python .\Comprobador.py
```

### Archivos de configuración del Buscador
- `Buscador\lanzar_buscador.pyw`, lista `CONSERVAR`: dominios cuya sesión se mantiene al cerrar.
- `Buscador\directos.txt`: sitios que rechazan a toda la red Tor y salen con la IP real. Solo esos sitios.
- `Buscador\salida_elegida.txt`: sitios que bloquean por país; salen por Tor, pero solo por relevos de los países de la línea `paises:`.
- `Buscador\velocidad.json`: entrada a Tor (`directo` o `puente`) y parámetros de velocidad.

Después de cambiar cualquiera de ellos, cierre y abra el Buscador.

---

## Diagnóstico

### Buscar-Puertas-Traseras.ps1
Busca puertas traseras y mecanismos de persistencia: cuentas, claves SSH autorizadas, paquetes de autenticación, entradas de inicio, tareas y servicios. Solo lee. Deja el informe en `Informes\`. Como administrador ve todo; sin permisos se salta lo protegido.

### Auditoria-Admin.ps1
Repite la auditoría de firmas digitales incluyendo los procesos protegidos del sistema, que sin permisos no muestran su ruta. Deja el informe en `Informes\`.

### Migrar-Lanzadores.ps1
Sustituye lanzadores `.vbs` conocidos por accesos directos que no necesitan Windows Script Host, para que la capa `cerrojos` pueda apagarlo sin romperlos. Si no encuentra esos lanzadores, no hace nada. Sin `-Aplicar` solo muestra lo que haría.
