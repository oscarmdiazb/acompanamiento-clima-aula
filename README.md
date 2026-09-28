# Acompañamiento SED · Encuesta de Clima de Aula (2026)

**Sitio:** https://oscarmdiazb.github.io/acompanamiento-clima-aula/

Página para que el personal de la SED **se apunte** a acompañar las aplicaciones de la
encuesta. La SED pidió que a cada aplicación asista una persona suya. Son cientos de
funcionarios y ~110 visitas: repartirlas a mano no es viable, así que cada quien escoge.

**Es un aplicativo independiente.** No toca la consola de reservas ni sus tablas. Solo
**lee** la agenda de visitas del aplicativo de reservas, para que las fechas nunca queden
desactualizadas aquí.

## Cómo funciona

**La primera pantalla es el calendario.** No hay registro previo, ni contraseña, ni correo.

1. La persona abre el enlace y ve **toda** la agenda: todos los días, todos los colegios,
   con la **dirección y el barrio** de cada sede. Puede escoger un día y una hora y abajo
   quedan los colegios de ese momento; las horas del selector son las que realmente existen
   ese día, no una rejilla inventada. También puede filtrar por localidad o por nombre.
2. Pulsa **«Me apunto»** en la visita que quiera.
3. Se le piden **tres datos: nombre completo, equipo y celular de contacto.** Nada más.
   Confirma.
4. Queda apuntada y puede llevarse la cita a su calendario con un `.ics`
   (Outlook, Google, Apple).

La segunda vez los tres vienen puestos, así que es un clic y confirmar.
Puede cancelar cuando quiera.

**Quién puede cancelar:** quien se apuntó desde ese mismo navegador (se guarda un token
propio), o quien escriba el mismo nombre. Nadie puede tumbar la visita de otro.

### La coordinadora de cada visita

Cada visita muestra **quién la coordina y su celular**, para que la persona que se apunta
sepa a quién llamar si el día se cae o pasa algo. Sale en la tarjeta, en el globo del mapa,
en la ventana de confirmar y en el `.ics`.

- **El nombre** viene de `clima_facilitadores` (aplicativo de reservas), por la llave
  `DANE|JORNADA|CLASE`. El curso a veces trae ceros a la izquierda: se quitan en los dos
  lados (`llaveAula`). Hoy hay cuatro: Ana María, Andrea, Daniela, Diana.
- **El celular** no existía en ninguna fuente. Vive en la tabla nueva `sed_coordinadoras`
  y se llena a mano:

  ```bash
  cd ~/oscar-personal-apps && supabase db query --linked \
    "update sed_coordinadoras set telefono='3001234567' where nombre='Andrea'"
  ```

  Mientras esté vacío, la página muestra solo el nombre. Estos teléfonos **sí son públicos**:
  son el contacto de trabajo del rol, y mostrarlos es justo el punto.

### La consola del equipo

`sed_agenda(clave)` entrega la agenda completa **con el celular de quien acompaña**. No puede
salir por la anon key, así que va con clave compartida, igual que el `?tipo=contactos` de
clima2026. La clave vive en `Encuesta/seguimiento_largo_plazo_r1r2/seguimiento/.sed_key`
(modo 600, fuera de git) y en `sed_config.clave_agenda`; **este repo es público, así que la
migración solo deja un marcador**.

`consola.py` la baja en `bajar_acompanamiento_sed()` y pone en cada aula `sed_nombre`,
`sed_equipo`, `sed_telefono` y `acompana_sed`; el calendario muestra
«Acompaña de la SED: 300… · Nombre · Equipo» o «SIN acompañante de la SED».

### Nombres de colegio repetidos

Bogotá tiene colegios **distintos con el mismo nombre**. Hay dos «Colegio Guillermo León
Valencia (IED)»: el del estudio está en **Antonio Nariño** (DANE `111001011053`, Kr 22 # 16
- 03 Sur) y hay otro en **Engativá** (`111001034002`, Kr 93 A # 75 B - 80). Una persona de
la SED buscó el nombre en internet, le salió el de Engativá y escribió preocupada.

Por eso **la dirección de cada visita es un enlace a Google Maps por coordenadas**, nunca por
nombre: `?api=1&query=<lat>,<lon>`. El punto exacto no se puede confundir. El `.ics` también
lleva el enlace y un campo `GEO`.

Misma trampa que ya estaba documentada en `CLAUDE.md` para los volantes de rastreo: agrupar
por nombre de colegio en vez de por DANE mezcla dos establecimientos.

### Lista o mapa

Arriba de la agenda hay un interruptor **Lista / Mapa**. La lista es lo predeterminado.

El mapa pone un pin por **sede** con el número de visitas que tiene ahí, y el color dice
cómo va: **naranja** = alguna sin acompañante, **verde** = todas cubiertas, **azul** = una
es suya. Al tocar el pin sale el colegio, la dirección y cada visita con su botón, igual que
en la lista. Respeta los mismos filtros.

Detalles que costaron un rato:

- **Leaflet se baja solo cuando alguien abre el mapa**, no al cargar la página.
- Leaflet **corta la propagación del clic dentro del popup**, así que el listener global del
  documento nunca se entera. Los botones del popup se conectan en `popupopen`.
- Los paneles de Leaflet viven en `z-index` 400–700, así que la ventana de confirmación
  tuvo que subir a 1000: si no, quedaba **detrás** del mapa.
- La rueda del ratón no hace zoom, a propósito: si lo hiciera, bajar por la página se
  quedaría atrapado dentro del mapa.
- Las coordenadas salen de `sede_longitud` / `sede_latitud` del directorio oficial, y solo
  se guardan si caen dentro de Bogotá (el archivo trae algunas en cero). 110 de 112 visitas
  tienen punto; las otras salen contadas al lado del interruptor.

Reglas que impone el servidor:

| Regla | Por qué |
|---|---|
| **Una sola** persona por visita | Es lo que pidió la SED; y así nadie amontona acompañantes en las visitas cómodas |
| No se puede estar en **dos visitas a la misma hora** | Error humano frecuente |
| Nombre **y** apellido, y equipo | Un nombre suelto no sirve para saber quién va |
| Celular de al menos 7 dígitos | Es para poder llamar si hay un cambio de última hora |

La primera se cambia en la tabla `sed_config`, sin migración:

```bash
cd ~/oscar-personal-apps && supabase db query --linked "update sed_config set valor='2' where clave='cupo_por_visita'"
```

El texto de la página se adapta solo: con cupo 1 dice «Ya tiene acompañante».

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la página. HTML + CSS + JS en un solo archivo, sin build |
| `sb-config.js` | URL y anon key de Supabase. **Público a propósito** |
| `sedes.js` | Dirección y barrio de cada sede. Generado, no se edita a mano |
| `construir_sedes.py` | Regenera `sedes.js` desde el directorio oficial de sedes de la SED |
| `supabase/migrations/…sql` | Tablas `sed_*` y las funciones `sed_get` / `sed_post` |
| `exportar.sh` | Lista de acompañamientos: quién va a cada visita y de qué equipo |
| `publicar.sh` | Publica el sitio. **Úselo siempre** en vez de `git push` a secas |

El mapa usa Leaflet y teselas de OpenStreetMap, ambos desde internet. Es la única dependencia
externa de la página, aparte de las fuentes.
| `huecos.sh` | Qué visitas siguen sin acompañante |

## De dónde sale cada dato

- **Agenda de visitas** → `rpc/api_get` del aplicativo de reservas (`clima2026`). Solo
  lectura, y ese endpoint no devuelve ningún dato de estudiantes.
- **Dirección de la sede** → `data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv`, el
  directorio oficial de sedes. Cruce por DANE12 del establecimiento + nombre de sede.
  111 de 112 sedes quedan con dirección; la que falta viene como código (`S010`), no como
  nombre.

## Solo visitas de seguimiento

La agenda de reservas trae, además del seguimiento, filas del operativo de **Ronda 3** y
alguna suelta, todas con un `dane` sintético que empieza por `EXTRA` (`EXTRA`, `EXTRA-R3`,
`EXTRA-R3REV`). **Esta página las descarta**: solo muestra las visitas de seguimiento
(27-sep-2026, decisión de Oscar). Son 86 visitas, 66 por venir.

El interruptor es **una sola línea** de `index.html`:

```js
const esExtra = v => (v.dane || "").startsWith("EXTRA");
...
if (esExtra(v)) continue;                 // solo visitas de seguimiento
```

`huecos.sh` aplica la misma regla, para que los dos números coincidan.

⚠ Al aplicar el filtro, **una persona ya estaba apuntada a una visita de Ronda 3** (Julio
Flórez, 1-oct 07:00). Su fila **sigue en la base**, pero ya no se ve en la página ni en sus
«Mis acompañamientos». Si esa visita no va a ocurrir, hay que avisarle y cancelarla a mano.
- **Quién acompaña** → tablas `sed_*` de este aplicativo.

Regenerar direcciones si cambia la agenda:

```bash
/usr/bin/python3 construir_sedes.py
```

## Privacidad

- La página **no tiene ningún dato de estudiantes**. Ni nombres, ni códigos, ni roles.
- De cada persona existen **nombre, equipo y celular**. No se pide correo ni documento.
- ⚠ **El celular NO se muestra en la página.** La página es pública: cualquiera con el enlace
  la abre, así que un número personal no puede quedar a la vista. `sed_get` devuelve solo
  nombre, equipo y si la visita es suya — verificado: el teléfono no sale por ahí ni leyendo
  la tabla con la anon key. El celular sale **únicamente** por `exportar.sh`.
- Las filas anteriores al 27-sep-2026 no tienen celular: se pidió después.
- Las tablas `sed_*` tienen RLS **sin políticas**: la anon key no puede leerlas. Todo pasa
  por `sed_get` / `sed_post`, que son `SECURITY DEFINER` y devuelven solo lo anterior.
- `sed_log` guarda cada acción (quién se apuntó o canceló y cuándo), para auditoría.

⚠ **La página se llama solo *Encuesta de Clima de Aula*.** Nunca el nombre del programa,
igual que el resto del material que circula por fuera del equipo. Este repo es público:
mantenerlo así, aquí y en la página.

## Publicar

Repo propio (`oscarmdiazb/acompanamiento-clima-aula`), GitHub Pages desde `main` en la raíz.

```bash
./publicar.sh "Qué cambió"
```

**Publique siempre con ese script, no con `git push` a secas.** El script sube el `?v=` de
los `<script>` antes de empujar. Sin eso, un navegador que ya abrió la página sigue usando
su copia vieja de `sedes.js` y muestra los colegios sin dirección — ya pasó una vez en
desarrollo y costó un rato encontrarlo.

No se mezcla con el repo de reservas (`clima2026`) a propósito: así este aplicativo se puede
tumbar o rehacer sin tocar el operativo, que está en campo hasta el 30 de octubre de 2026.

## Probar en local

```bash
python3 -m http.server 8793 --directory acompanamiento-sed-2026
```

(o `preview_start` con la configuración `acompanamiento-sed` de `.claude/launch.json`)

## Pendientes

1. **Mandar el enlace a la SED** con una instrucción corta de una línea.
2. **Empujar los huecos**: `huecos.sh` dice qué falta. Falta decidir quién persigue y cada
   cuánto — un correo semanal con las visitas sin acompañante sería lo natural.
3. Un panel interno con las estadísticas por dependencia, si la SED lo pide.
