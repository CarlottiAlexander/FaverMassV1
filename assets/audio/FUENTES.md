# Fuentes del audio

**Todo lo que hay acá es CC0** (dominio público, sin atribución obligatoria). Se
deja registrado igual, por la misma razón que los `LICENSE_*.txt` de los modelos:
si mañana hay que reemplazar algo, o alguien pregunta de dónde salió, la respuesta
tiene que estar en el repo y no en la memoria de nadie.

| Origen | Licencia verificada en | Qué se usó |
|---|---|---|
| **Kenney** (espejo `iwenzhou/kenney`) | `LICENSE.md` → CC0 1.0 Universal | `weapon_switch`, `impact_*`, `footsteps/`, `enemies/generic_attack`, `weapons/railgun_shot`, `wave_start`, `victory`, `defeat`, `ecstasy` |
| **80 CC0 creature SFX** (OpenGameArt) | ficha del asset → CC0 | todas las voces de enemigo (`enemies/*`) y las del jugador (`player_*`) |
| **Gunshot Sounds** (OpenGameArt) | `sounds/creativecommons.txt` → CC0 | las 4 grabaciones de arma de fuego, ya recortadas |

## Las armas de fuego no vienen así: se cortaron acá

Las grabaciones originales son tomas de campo — varios disparos seguidos en un solo
archivo, con eco y ruido ambiente. `tools/gun_slicer.tscn` las parte en one-shots,
las normaliza y **mide cuál sirve**: pico del disparo contra el piso de ruido de
justo antes. Los cuatro que quedaron son los de mejor relación de cada toma:

| archivo | arma real | limpieza |
|---|---|---|
| `weapons/pistol_shot.wav` | CZ-52 | 24.2 dB sobre el ruido |
| `weapons/rifle_shot.wav` | SKS | 27.3 dB |
| `weapons/sniper_shot.wav` | Mosin Nagant | 25.6 dB |
| `weapons/shotgun_shot.wav` | escopeta | 17.2 dB |
| `explosion.wav` | Mosin Nagant | 24.9 dB (se reproduce a tono 0.5) |

Hay **cuatro muestras para diez armas**, y el resto salen cambiando el tono — ver
`ARMA_SONIDO` en `scripts/core/audio.gd`. Las asignaciones no son arbitrarias: el
SKS dispara el mismo cartucho 7.62x39 que el AK-47, y el Mosin es literalmente un
rifle de cerrojo de francotirador.

## Cómo agregar o cambiar un sonido

**No hay que tocar código.** El nombre del archivo ES el mapeo:

- `enemies/<tipo>_<ranura>.ogg` — `ranura` es `attack`, `hit` o `death`.
  Si un tipo no lo declara, hereda `enemies/generic_<ranura>`.
- `weapons/<muestra>_shot.ogg` — qué muestra usa cada arma sale de `ARMA_SONIDO`.
- Cualquiera de esos acepta **variantes numeradas**: `hollow_hit_00.ogg`,
  `_01`, `_02`… Se elige una al azar sin repetir la anterior. Poner un archivo más
  en la carpeta alcanza para sumar variación.

`tools/audio_report.tscn` dice qué resolvió cada tipo y qué quedó mudo.

## Ambiente y musica

| Archivo | Origen | Licencia |
|---|---|---|
| `ambience_calm.wav`, `ambience_chaos.wav` | **generados por `tools/ambience_gen.tscn`** | nuestros |
| `music_arena.ogg` | *Post Apocalyptic Wastelands* de Juhani Junkala (OpenGameArt) | CC0 verificado en la ficha |

Los dos lechos de ambiente **no salieron de un pack: los genera el motor**. Un
disparo o un rugido sintetizados suenan a juguete — por eso las armas salieron de
grabaciones reales. Pero el viento y un drone grave son ruido filtrado, que es
literalmente lo que un sintetizador hace bien, y así se consigue algo que ningún
pack da gratis: **un bucle exactamente sin costura**. La herramienta lo mide y lo
reporta (`costura: salto X | típico Y -> OK, no clickea`), así que no hay que
confiar en el oído para saberlo.

Regenerarlos da el MISMO archivo: la semilla del ruido es fija.

⚠ **`music_arena.ogg` tira un warning cosmético al cargar** — su encabezado Vorbis
trae un comentario mal formado del encoder de Sony (`"Sony Ogg Vorbis 1.0 Final"`,
sin el `=` que exige el formato). Es del archivo original y **no se puede parchear
editando bytes**: las páginas Ogg llevan CRC y cualquier cambio las invalida (se
probó, y rompió el archivo). Es un WARNING, no un error, y no afecta a nada. Para
sacarlo habría que reencodear, y Godot no encodea Ogg.
