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
