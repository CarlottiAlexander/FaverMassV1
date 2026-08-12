# Faver Mass v1

FPS de supervivencia por oleadas hecho en **Godot 4.6**. Arena cerrada, 8 tipos de
enemigo, 10 armas con rarezas, y un sistema de XP ("Éxtasis") que te va rotando el
arsenal mientras el cielo se pone cada vez más rojo.

Es el sucesor de [FaverMass](../FaverMass), la versión original en C++17 + raylib
con render 100% procedural. Esta versión se reconstruyó desde cero en Godot para
poder usar modelos y texturas importados de verdad.

> **Estado:** jugable y completo en su loop (oleadas → matar → XP → mejor arma →
> oleadas más duras), en fase de playtest. **Todavía no tiene audio.** Ver
> [Lo que falta](#lo-que-falta).

---

## Requisitos

Uno solo:

| Dependencia | Versión | Notas |
|---|---|---|
| **Godot Engine** | **4.6.x** (probado en 4.6.3 stable) | Build **estándar**, NO la de .NET/C# — el proyecto es 100% GDScript |

No hay que compilar nada, no hay que instalar SDKs, no hay paquetes de terceros ni
`godot-cpp`/SCons. El editor de Godot es un único ejecutable portable: lo descargás,
lo descomprimís y listo.

Descarga oficial: <https://godotengine.org/download>

**Hardware:** el juego llega a 160+ enemigos animados en oleadas altas. Está tuneado
para andar a ~140 FPS en una RTX 2060 con SSAO, glow, sombras 2K y MSAA 2x. Usa el
renderer **Forward+**, así que necesita una GPU con Vulkan (cualquier placa dedicada
de la última década anda; con gráficos integrados va a sufrir en oleadas altas).

**Sistema operativo:** desarrollado en Windows 10, pero no hay nada específico de
Windows en el código — debería correr igual en Linux y macOS con el Godot de esa
plataforma.

---

## Cómo levantarlo

### 1. Bajá el proyecto

```bash
git clone https://github.com/CarlottiAlexander/FaverMassV1.git
```

O desde la web: botón verde **Code → Download ZIP**, y lo descomprimís.

### 2. Bajá Godot 4.6

De <https://godotengine.org/download> — elegí **Godot Engine** (la estándar, no la
".NET"). Es un `.zip` con un ejecutable adentro; lo descomprimís donde quieras.

### 3. Abrí el proyecto

**Opción A — desde el editor (recomendado la primera vez):**

1. Abrí el ejecutable de Godot.
2. **Import** → buscá la carpeta del proyecto → seleccioná `project.godot` → **Import & Edit**.
3. Esperá a que termine de importar los assets (la primera vez tarda un rato: hay
   ~42 MB de modelos `.glb` que tiene que procesar).
4. **F5** para jugar.

**Opción B — directo por línea de comandos, sin abrir el editor:**

```bash
godot --path /ruta/a/FaverMassV1
```

En Windows, con el ejecutable portable:

```bash
"C:\ruta\a\Godot_v4.6.3-stable_win64.exe" --path "C:\ruta\a\FaverMassV1"
```

> **Ojo con la primera corrida:** Godot genera la carpeta de caché `.godot/` (~38 MB)
> al importar. No está en el repo a propósito. Si algo se ve raro la primera vez,
> cerrá, borrá `.godot/` y volvé a abrir.

---

## Controles

| Tecla | Acción |
|---|---|
| **W A S D** | Moverse |
| **Mouse** | Mirar |
| **Espacio** | Saltar |
| **Shift** | Correr |
| **Ctrl** | Agacharse |
| **Click izquierdo** | Disparar |
| **Click derecho** | Ráfaga de 3 (solo con la Pistola) |
| **G** | Gastar Éxtasis → arma nueva |
| **ESC** | Pausa / liberar el cursor |

Los controles están **hardcodeados a teclas físicas**, no hay remapeo ni soporte de
gamepad todavía.

---

## Cómo se juega

**El loop:** matás enemigos → ganás Éxtasis (XP) y un poco de vida → gastás el Éxtasis
con **G** para cambiar de arma → llega la oleada siguiente, más grande.

**Éxtasis (la barra de abajo a la izquierda).** Matar es la *única* forma de curarse:
cada muerte da entre 1 y 3 HP según lo duro que fuera el bicho. La tecla **G** siempre
gasta el escalón más alto que te alcance:

| XP | Te da | Cuesta |
|---|---|---|
| 100 | **Railgun Legendary** | 100 |
| 75+ | Arma random Legendary | 75 |
| 50+ | Arma random Rare | 50 |
| 25+ | Arma random Common | 25 |

Si te quedás sin balas, el cambio de arma es **gratis** (si no, quedarías atrapado sin
nada), pero la rareza que te toca depende del XP que tengas en ese momento.

**Rarezas.** Cada arma sale con una de 5, y cambia daño y munición:

| Rareza | Daño | Munición |
|---|---|---|
| Common (blanco) | 1.0× | 1.0× |
| Rare (azul) | 1.3× | 1.3× |
| Epic (púrpura) | 1.7× | 1.5× |
| Legendary (dorado) | 2.5× | 2.0× |
| **Cursed (rojo)** | **3.5×** | **0.5×** |

Cursed es riesgo/recompensa puro: pega como un camión pero con la mitad de balas.

**Las 10 armas:** Pistol, Revolver, SMG, AK-47, Shotgun, Sniper, LMG, Minigun,
Rocket Launcher y Railgun. Sniper y Revolver **perforan** hasta 10 enemigos en fila; el
Revolver además duplica su daño por cada tier de rareza. El Railgun es un haz continuo
que mata cualquier cosa al contacto, dura 5 segundos de uso y al agotarse te cura y te
da un envión de velocidad.

**Tech de movilidad (esto no está explicado en el juego):** disparándole al piso con la
**Escopeta** o el **Rocket Launcher** *estando en el aire* conseguís un segundo salto más
un empujón horizontal hacia donde estés mirando. Se puede encadenar, y sí, se puede
saltar por encima del muro de la arena. Si te caés al vacío el juego te devuelve adentro.

**Headshot = muerte instantánea**, salvo contra el Knight y contra los alphas.

**Los 8 enemigos.** Cada uno tiene su propia IA, no son todos "correr hacia el jugador":

| Enemigo | Aparece en | Qué hace |
|---|---|---|
| **Hollow** | Oleada 1 | Zombi lento, va derecho |
| **Thrall** | 2 | Rápido, va derecho |
| **Dire Bat** | 3 | Vuela, 1 HP, molesta |
| **Blood Lord** | 4 | Esquiva de costado; **al morir suelta 2 murciélagos** |
| **Knight** | 5 | 500 HP, dash lateral, **te agarra Hollows y te los tira por el aire** |
| **Capra** | 6 | Estilo SCP-173: **está congelada hasta que la mirás**, después carga en cuatro patas y salta |
| **Sorceress** | 7 | No te ataca: orbita como un satélite y **genera cráneos sin parar** — matala primero |
| **Demon Skull** | 8 | Vuela errático |

El primer enemigo de cada oleada múltiplo de 5 es un **alpha**: ×5 vida, ×2 daño, más
grande y con un aura. Da ×3 XP.

La oleada avanza cuando queda ≤20% de enemigos vivos. Los murciélagos del Blood Lord y
los cráneos de la Sorceress **no cuentan en el total** de la oleada, así que hay que
matarlos igual — es a propósito.

**El mundo reacciona.** A medida que sube el `chaos_level`, el cielo va de violeta calmo
a rojo infernal, la niebla se espesa, aparecen la luna y los escombros, y el muro que
rodea la arena **crece** de 3 a 9 metros.

---

## Estructura del proyecto

```
FaverMassV1/
├── project.godot        Config: Forward+, 3 autoloads, sin InputMap
├── scenes/
│   ├── main.tscn          Escena principal (piso, luces, post-proceso, jugador)
│   ├── enemy.tscn         Enemigo genérico — el modelo lo elige el script
│   └── fx/                Gibs, sangre, números de daño, explosiones, balas, cohetes
├── scripts/
│   ├── game_data.gd       AUTOLOAD — constantes, tablas de armas/enemigos, fórmulas
│   ├── game_state.gd      AUTOLOAD — máquina de estados y pausa global
│   ├── fx_manager.gd      AUTOLOAD — efectos efímeros con topes globales
│   ├── player.gd          Movimiento, las 10 armas, headshot, Railgun, Éxtasis
│   ├── enemy.gd           Los 8 tipos + alpha en un solo script
│   ├── wave_manager.gd    Composición y ritmo de las oleadas
│   ├── world.gd           Arena, obstáculos y cielo generados por código (semilla 42)
│   └── ui.gd              HUD y los 4 menús, construidos 100% por código
├── assets/              Modelos importados (todos CC0 — ver los LICENSE_*.txt)
│   ├── enemies/           Un .glb por tipo de enemigo, riggeado y animado
│   ├── weapons/           Las 10 armas
│   ├── monsters_q/        45 monstruos sin usar (banco para cambiar enemigos)
│   └── weapons_q/         25 armas sin usar (banco para cambiar armas)
└── tools/               Escenas de diagnóstico, no forman parte del juego
```

Un par de decisiones que llaman la atención si mirás el código:

- **El HUD y los menús están hechos por código**, no con escenas `.tscn` de UI. El
  proyecto se desarrolló sin abrir el editor gráfico, y armar árboles de `Control` a
  mano en XML sin poder verlos es peor que generarlos en `_ready()`.
- **No hay `InputMap`.** Las teclas se leen directo con `Input.is_key_pressed()`.
- **Los sistemas se encuentran por grupos y señales**, no por referencias `@export`
  cruzadas.

Si vas a tocar hitboxes o cambiar modelos de enemigo, corré `tools/hitbox_report.tscn`
y `tools/hit_test.tscn` — miden en vez de adivinar.

---

## Lo que falta

- **Audio.** Nada, cero. Es lo que más se nota. Los sliders de volumen ya están
  cableados al bus Master, así que en cuanto haya sonidos van a funcionar solos.
- **Muzzle flash.** El arma se ve y tiene retroceso, pero no hay fogonazo ni humo.
- **Balance.** Los números salen tal cual de la versión original en raylib. Es un punto
  de partida conocido, no el balance final.
- **Remapeo de controles y gamepad.**

---

## Créditos

Todos los assets son **CC0** (dominio público, uso libre incluso comercial). La
atribución no es obligatoria, pero se la merecen:

- **[Kay Lousberg](https://www.kaylousberg.com)** — KayKit Character Packs (Skeletons,
  Adventurers): los modelos de Hollow, Thrall, Capra, Sorceress, Blood Lord y Knight,
  con sus 90+ animaciones.
- **[Quaternius](https://quaternius.com)** — Ultimate Guns Pack (8 de las 10 armas) y
  Ultimate Monsters Pack (Dire Bat y Demon Skull).
- **[Kenney](https://kenney.nl)** — Blaster Kit (Railgun y Rocket Launcher).

Las licencias completas están en `assets/enemies/LICENSE_*.txt` y
`assets/weapons/LICENSE_*.txt`.

> **Nota para quien clone esto:** los `.glb` de Kenney referencian su textura
> (`assets/weapons/Textures/colormap.png`) por **ruta relativa externa**, no la traen
> embebida. Si movés esos modelos de carpeta, se ven blancos.
