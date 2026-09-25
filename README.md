# Acompañamiento SED · Encuesta de Clima de Aula (2026)

Página para que el personal de la SED **se apunte** a acompañar las aplicaciones de la
encuesta. La SED pidió que a cada aplicación asista una persona suya. Son cientos de
funcionarios y ~110 visitas: repartirlas a mano no es viable, así que cada quien escoge.

**Es un aplicativo independiente.** No toca la consola de reservas ni sus tablas. Solo
**lee** la agenda de visitas del aplicativo de reservas, para que las fechas nunca queden
desactualizadas aquí.

## Cómo funciona

1. La persona abre la página y escribe nombre, correo institucional, dependencia y
   **equipo**. **No hay contraseña.** El correo debe terminar en `.gov.co`; eso es lo
   único que filtra quién puede apuntarse.
2. **Escoge el día y la hora**, y abajo quedan los colegios de ese momento. Las horas del
   selector son las que realmente existen ese día, no una rejilla inventada. Si deja día y
   hora en «Todas», ve **toda** la agenda: todos los días, todos los colegios, con la
   **dirección y el barrio** de cada sede. También puede filtrar por localidad o por nombre.
3. Pulsa **«Me apunto»**. Puede cancelar cuando quiera.
4. Se lleva sus visitas al calendario con un archivo `.ics` (Outlook, Google, Apple).

Reglas que impone el servidor:

| Regla | Por qué |
|---|---|
| **Una sola** persona por visita | Es lo que pidió la SED; y así nadie amontona acompañantes en las visitas cómodas |
| No se puede estar en **dos visitas a la misma hora** | Error humano frecuente |
| Correo institucional `.gov.co` | Evita que se apunte cualquiera |

Las dos primeras se cambian en la tabla `sed_config`, sin migración:

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
| `exportar.sh` | Lista de acompañamientos **con equipo, correo y celular** (no sale por la página) |
| `huecos.sh` | Qué visitas siguen sin acompañante |

## De dónde sale cada dato

- **Agenda de visitas** → `rpc/api_get` del aplicativo de reservas (`clima2026`). Solo
  lectura, y ese endpoint no devuelve ningún dato de estudiantes.
- **Dirección de la sede** → `data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv`, el
  directorio oficial de sedes. Cruce por DANE12 del establecimiento + nombre de sede;
  para las revisitas de Ronda 3 (`dane = EXTRA-R3REV`) el cruce es por nombre de colegio.
  106 de 107 sedes quedan con dirección; la que falta viene como código, no como nombre.
- **Quién acompaña** → tablas `sed_*` de este aplicativo.

Regenerar direcciones si cambia la agenda:

```bash
/usr/bin/python3 construir_sedes.py
```

## Privacidad

- La página **no tiene ningún dato de estudiantes**. Ni nombres, ni códigos, ni roles.
- De las otras personas apuntadas se muestra **solo nombre y equipo** (o dependencia si no
  hay equipo). Nunca el correo ni el celular; esos salen únicamente por `exportar.sh`.
- Las tablas `sed_*` tienen RLS **sin políticas**: la anon key no puede leerlas. Todo pasa
  por `sed_get` / `sed_post`, que son `SECURITY DEFINER` y devuelven solo lo anterior.
- `sed_log` guarda cada acción (quién se apuntó o canceló y cuándo), para auditoría.

⚠ **La página no dice el nombre de la intervención ni menciona tratamiento/control.** Se
llama solo *Encuesta de Clima de Aula*, igual que el resto del material que circula por
fuera del equipo. Mantenerlo así.

## Publicar

Repo propio, GitHub Pages, con el skill `github-oscar`. No mezclar con el repo de reservas:
la idea es que este aplicativo se pueda tumbar o rehacer sin tocar el operativo.

## Probar en local

```bash
python3 -m http.server 8793 --directory acompanamiento-sed-2026
```

(o `preview_start` con la configuración `acompanamiento-sed` de `.claude/launch.json`)

## Pendientes

1. **Publicar** el repo y mandar el enlace a la SED.
2. **Empujar los huecos**: `huecos.sh` dice qué falta. Falta decidir quién persigue y cada
   cuánto — un correo semanal con las visitas sin acompañante sería lo natural.
3. Un panel interno con las estadísticas por dependencia, si la SED lo pide.
