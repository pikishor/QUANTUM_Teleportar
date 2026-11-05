# BALANCE (pass v2, wave 79)

Tables printed by `godot/tools/balance_sim.sh` (combat model, also `-s res://tools/balance_sim.gd`) and `godot/tools/economy_sim.sh` (economy). The maths is `scripts/progress/balance_model.gd`
(combat) and `balance_economy.gd` (pacing); the bands below are asserted by `tests/test_balance2.gd`. Chapters are 1-12 (9-12 = the sequel). Model: the hero lands a per-weapon share of rounds,
holds the shop damage level and crafted mods a chapter implies (0.7 damage levels per chapter, +3 % mods per chapter from chapter 4), three operatives shoot at once with 35 % of rounds landing.
`fight` = share of hero health lost clearing three operatives one after the other with the carbine in the open (no cover, no regeneration). Job durations in the economy tables are estimates
(time limit x 0.75 plus 150 s to reach, brief and collect), so rates are relative.

## What the first table showed and what changed

| Spike / inconsistency | Constant | Before | After |
|---|---|---|---|
| FLUX SMG, PLASMA MINIGUN, TWIN PISTOLS, GRAVITY LAUNCHER at 0.46-0.56 of carbine dps, 6-10 kills per full reserve | `WeaponDefs` flux dmg / reserve | 6 / 180 | 7.5 / 260 |
| | minigun dmg / reserve | 5 / 360 | 6.5 / 480 |
| | akimbo dmg / reserve | 11 / 144 | 13.5 / 200 |
| | gravity dmg / well_dps | 45 / 10 | 65 / 16 |
| ARC WHIP 1.6x carbine, QUANTUM BLADE 3.5x (model now counts melee reach at 40 % uptime: whip 0.82x, blade 1.41x) | whip dmg | 24 | 30 |
| ARC cast could not kill a 55 hp flanker | `QuantumVerbs.ARC_DMG` | 55 | 70 |
| STORY 1 % fight cost vs NORMAL 25 % (25x step), QUANTUM 161 % (not winnable in the open) | `HeroPower` STORY dmg / taken | 4.0 / 0.5 | 1.4 / 0.9 |
| | `Difficulty` STORY dmg | 0.55 | 0.65 |
| | `Difficulty` QUANTUM hp / dmg / spread / aggr | 1.8 / 1.8 / 0.5 / 1.45 | 1.6 / 1.65 / 0.6 / 1.35 |
| Boss fights: SMELTER 56 s, chapter 7 two bosses 85 s, chapter 10 two bosses 87 s, finale 60 s with 117 % health loss | campaign `hp_mult` smelter | 1.0 | 0.8 |
| | bulwark / hound (chapter 7) | 1.0 / 1.0 | 0.85 / 0.85 |
| | hound alpha / phasewright prime (chapter 10) | 1.0 / 1.2 | 0.85 / 0.95 |
| | bulwark prime (chapter 12) | 1.2 | 1.0 |
| Side jobs: SMUGGLER 2.5x the sector rate per minute, ARENA / HUNT / BLACKOUT / ROOFTOP 1.9-2.0x, PHOTO 0.8x | `Economy.SIDE_PAY` (and the mirrored `SideMissions.DEFS` pay) | smuggler 680, arena 640, hunt 600, blackout 560, rooftop 440, photo 260 | 500, 600, 560, 540, 410, 290 |
| Loud heists 2.1-2.2x the sector rate | `Economy.HEIST_APPROACH` loud | 1.4 | 1.25 |
| Safehouses cost 0.4-0.7 hours of income (the bunker less than the penthouse in hours) | `Economy.SAFEHOUSE_PRICE` | 1800 / 3600 / 6500 / 9000 | 2400 / 5400 / 9000 / 13000 |

The chapter curves themselves (`Difficulty.chapter_hp` +10 %, `chapter_dmg` +6 %, `boss_hp` +9 % per chapter, `Progress.difficulty` reward +20 %) are unchanged: time-to-kill moves 4 % or less per chapter on every mode, chapters 9-12 included.
Not changed on purpose: STORY keeps near-free coherence and short cooldowns (test_hero_power requires it), so its ability cadence is the one place the abilities table is not bounded.

## Bands (tests/test_balance2.gd)

- Every weapon's sustained dps within 0.62-1.7x of the carbine; a full reserve of a limited weapon kills at least 5.5 operatives; gear lifts each weapon 1.4-2.4x from chapter 1 to 12.
- Time-to-kill and survival change by at most 12 % per chapter on every mode, ttk stays within 0.6-2.2x of chapter 1, three operatives never cost more than 130 % of the health.
- The fight cost grows 1.5-5.5x per step STORY < NORMAL < HARD < QUANTUM; NORMAL costs 15-40 %. HeroPower rows are monotone; STORY hero damage at most 2x.
- Bosses: 14-52 s of carbine fire on NORMAL (at most twice on QUANTUM), at most ~100 % health lost, two-boss chapters under 80 s, the finale is the longest single boss of the sequel.
- Abilities: cadence never speeds up with the difficulty, none is spammable on NORMAL, none out-damages the carbine, 0.7+ damage per coherence, the bar refills in 8-16 s on NORMAL.
- Skill tree: rises every chapter by at most 6 levels, nearly full (36+) by chapter 12, adds at most 35 % damage. Faction hostile <= 1.7x pressure, wanted level 5 <= 2.6x, companion 5-25 % of hero dps.
- Economy: side jobs 0.55-1.9x of the sector average per minute (best / worst <= 2.6x), heists 0.8-2.2x, stealth 0.7-1.9x, safehouses 0.4-1.6 hours of income, one craft <= 0.5 hours, full gear tree 8-13 hours.

## Weapons (14)

```
## WEAPONS  sustained dps at chapter 1 / 6 / 12 (NORMAL), ttk of an operative (s), ammo kills (mag + reserve at chapter 1)
weapon      ac   dps1   dps6  dps12  ttk1  ttk6  ttk12  vs_carbine  kills_per_ammo
carbine    0.45     42     64     79  1.88  1.87   2.12       1.00  inf
scatter    0.55     35     54     66  2.26  2.24   2.53       0.83  20.8
lance      0.70     49     74     92  1.63  1.62   1.83       1.16  26.2
grenade    0.80     31     46     57  2.62  2.60   2.94       0.72  6.0
burst      0.50     30     45     56  2.68  2.66   3.01       0.70  8.1
rail       0.70     40     60     74  2.02  2.00   2.26       0.93  20.8
flux       0.35     30     45     56  2.69  2.67   3.02       0.70  10.0
gravity    0.80     29     44     54  2.77  2.75   3.11       0.68  10.1
minigun    0.35     30     46     57  2.64  2.62   2.96       0.71  17.1
akimbo     0.42     27     41     51  2.92  2.90   3.27       0.65  15.9
arc        0.50     31     47     58  2.59  2.58   2.91       0.73  10.5
revolver   0.55     29     43     54  2.78  2.76   3.12       0.68  15.8
whip       0.85     35     53     65  2.29  2.28   2.57       0.82  inf
blade      0.85     60     90    112  1.34  1.33   1.50       1.41  inf
```

## Time to kill and survival per chapter and difficulty

```
## TIME TO KILL (carbine, one operative, s) and SURVIVAL against 3 operatives (s) per chapter and mode
chapter  STORY   ttk  surv  fight  NORMAL  ttk  surv  fight  HARD    ttk  surv  fight  QUANTUM ttk  surv  fight
      1   0.94  36.5  0.05    1.88  15.0  0.25    2.68   8.6  0.63    3.35   5.8  1.15
      2   0.96  35.9  0.05    1.91  14.7  0.26    2.72   8.4  0.65    3.40   5.7  1.18
      3   0.97  35.4  0.05    1.94  14.5  0.27    2.75   8.3  0.66    3.44   5.7  1.21
      4   0.96  35.2  0.05    1.91  14.4  0.26    2.71   8.2  0.66    3.40   5.6  1.21
      5   0.94  35.1  0.05    1.89  14.4  0.26    2.68   8.2  0.65    3.36   5.6  1.20
      6   0.94  35.1  0.05    1.87  14.4  0.26    2.66   8.2  0.65    3.33   5.6  1.19
      7   0.93  35.3  0.05    1.86  14.5  0.26    2.64   8.3  0.64    3.30   5.6  1.17
      8   0.92  35.7  0.05    1.84  14.7  0.25    2.62   8.4  0.63    3.28   5.7  1.15
      9   0.95  36.3  0.05    1.90  14.9  0.26    2.71   8.5  0.64    3.39   5.8  1.17
     10   0.99  37.1  0.05    1.98  15.2  0.26    2.81   8.7  0.65    3.52   5.9  1.19
     11   1.02  38.0  0.05    2.05  15.6  0.26    2.91   8.9  0.65    3.64   6.1  1.20
     12   1.06  36.7  0.06    2.12  15.0  0.28    3.01   8.6  0.70    3.76   5.9  1.28
largest chapter-to-chapter change: 3.8 %
```

## Bosses (campaign steps, chapters 9-12 included)

```
## BOSSES  hp, carbine ttk (s), hero hp share lost while killing it (half the fire lands on the hero)
chapter  boss         STORY   hp   ttk  lost  NORMAL  hp   ttk  lost  HARD    hp   ttk  lost  QUANTUM hp   ttk  lost
      2  phasewright   1221  18.9   12%   1744  37.9   58%   2354  53.8  144%   2790  67.3  265%
      3  overseer      1239  17.8   16%   1770  35.7   75%   2390  50.7  186%   2832  63.4  339%
      4  smelter       1707  22.4   18%   2438  44.8   88%   3292  63.6  218%   3901  79.6  400%
      5  skimmer       1809  21.8   19%   2584  43.6   91%   3488  61.9  223%   4134  77.5  407%
      6  overseer      1522  17.0   15%   2175  33.9   72%   2936  48.2  178%   3480  60.3  325%
      7  bulwark       1833  19.0   16%   2618  38.0   77%   3534  53.9  191%   4189  67.5  349%
      7  hound         1649  17.1   11%   2356  34.2   56%   3181  48.5  138%   3770  60.7  253%
      8  overseer      1712  16.6   14%   2445  33.1   69%   3301  47.1  171%   3912  58.9  312%
     10  hound         1939  18.0   11%   2769  36.0   56%   3739  51.2  139%   4431  64.0  255%
     10  phasewright   1926  17.9   11%   2751  35.8   53%   3714  50.9  132%   4402  63.6  242%
     12  bulwark       2786  25.1   20%   3980  50.1   98%   5373  71.2  243%   6368  89.1  444%
```

## Abilities (7)

```
## ABILITIES  coherence cost, cooldown, sustained period (s) and dps per mode (STORY / NORMAL / HARD / QUANTUM)
QUANTUM TELEPORT  cost   15  cd  0.3  dmg    0   0.03s/0  1.88s/0  2.43s/0  3.21s/0
ENTANGLE LINK     cost   25  cd  0.8  dmg    0   0.08s/0  3.12s/0  4.04s/0  5.36s/0
ENTANGLE SWAP     cost   25  cd  4.0  dmg    0   0.40s/0  4.00s/0  4.40s/0  5.36s/0
SUPERPOSITION     cost   35  cd  6.0  dmg   25   0.60s/58  6.00s/4  6.60s/4  7.50s/3
COLLAPSE          cost    0  cd  1.5  dmg   50   0.15s/467  1.50s/33  1.65s/29  1.80s/25
WAVE              cost   50  cd  8.0  dmg   55   0.80s/96  8.00s/7  8.80s/6  10.71s/5
ARC               cost   30  cd  6.0  dmg   70   0.60s/163  6.00s/12  6.60s/10  7.20s/9
```

## Skill tree

```
## SKILL TREE  level / damage factor by chapter (STORY, NORMAL, HARD, QUANTUM)
      1  L11 x1.09   L09 x1.05   L09 x1.04   L09 x1.04
      2  L16 x1.14   L13 x1.07   L13 x1.06   L14 x1.07
      3  L21 x1.18   L17 x1.10   L17 x1.09   L18 x1.09
      4  L25 x1.18   L20 x1.11   L20 x1.10   L21 x1.11
      5  L28 x1.18   L23 x1.12   L23 x1.11   L24 x1.11
      6  L32 x1.18   L26 x1.12   L26 x1.11   L27 x1.11
      7  L35 x1.18   L28 x1.12   L28 x1.11   L30 x1.11
      8  L38 x1.18   L31 x1.12   L31 x1.11   L33 x1.11
      9  L40 x1.18   L34 x1.12   L34 x1.11   L35 x1.11
     10  L40 x1.18   L36 x1.12   L36 x1.11   L38 x1.11
     11  L40 x1.18   L38 x1.12   L38 x1.11   L40 x1.11
     12  L40 x1.18   L40 x1.12   L40 x1.11   L40 x1.11
```

## Factions, wanted, companion

```
## FACTIONS / WANTED / COMPANION
faction pressure  hostile x1.53  neutral x1.00  allied x0.70
wanted pressure   L0 x1.00  L1 x1.20  L2 x1.45  L3 x1.70  L4 x2.00  L5 x2.40
companion dps 7.5; share of hero carbine dps at chapters 11 / 12 (NORMAL): 10 % / 9 %
```

## HeroPower rows

```
## HEROPOWER rows  hero dps factor, incoming damage factor, energy regen /s, teleport hops
STORY    dmg x1.40  taken x0.59  regen 48.0  hops 6  cooldown x0.10
NORMAL   dmg x1.00  taken x1.00  regen 8.0  hops 2  cooldown x1.00
HARD     dmg x0.95  taken x1.35  regen 6.8  hops 1  cooldown x1.10
QUANTUM  dmg x0.90  taken x1.65  regen 5.6  hops 1  cooldown x1.20
```

## Economy: gear tree and credits per hour

```
## ECONOMY  gear items 82, total 119710 cr, first upgrade 10.0 min, full tree 11.7 h
hour  sector  credits/h  cum_income  cum_cost_bought  items
   1       1       4428        4428             3925      8
   2       2       5286        9714             9300     16
   3       3       6776       16491            15850     24
   4       4       7844       24335            24045     32
   5       5       8871       33206            32210     39
   6       5       9989       43195            41755     46
   7       6      11024       54219            52765     53
   8       7      12059       66278            65400     60
   9       8      13094       79373            77330     66
  10       9      14129       93502            93290     73
  11      10      15164      108667           106285     78
  12      11      16199      124867           119710     82
  13      12      17235      142102           119710     82
  14      13      18270      160372           119710     82

```

## Side missions (20)

```
## SIDE MISSIONS  pay at the unlock chapter, estimated minutes, credits per minute, rate = per minute over the sector average (band 0.55-1.90)
courier      ch 1  pay   248   3.5 min   70.7 cr/min  rate 0.96
photo        ch 1  pay   328   5.0 min   65.5 cr/min  rate 0.89
relay        ch 1  pay   360   4.0 min   90.0 cr/min  rate 1.22
rescue       ch 2  pay   405   3.9 min  104.5 cr/min  rate 1.19
car_drop     ch 2  pay   512   3.6 min  141.4 cr/min  rate 1.60
turf         ch 3  pay   662   4.4 min  151.4 cr/min  rate 1.34
rooftop      ch 3  pay   648   3.4 min  191.9 cr/min  rate 1.70
heist        ch 4  pay   935   4.2 min  220.0 cr/min  rate 1.68
hunt         ch 5  pay  1135   4.4 min  259.4 cr/min  rate 1.75
smuggler     ch 5  pay  1012   3.8 min  270.0 cr/min  rate 1.83
bounty       ch 2  pay   485   4.1 min  117.6 cr/min  rate 1.33
sniper       ch 3  pay   630   4.2 min  148.2 cr/min  rate 1.31
swarm        ch 3  pay   725   4.2 min  170.6 cr/min  rate 1.51
car_theft    ch 4  pay   900   3.9 min  232.3 cr/min  rate 1.78
hostage      ch 4  pay   972   4.4 min  222.3 cr/min  rate 1.70
blackout     ch 4  pay   972   4.1 min  235.8 cr/min  rate 1.80
data_courier ch 2  pay   445   4.0 min  111.2 cr/min  rate 1.26
arena        ch 5  pay  1215   4.4 min  277.7 cr/min  rate 1.88
demolition   ch 1  pay   315   3.5 min   90.0 cr/min  rate 1.22
anomaly      ch 3  pay   662   5.0 min  132.5 cr/min  rate 1.17

```

## Heists and stealth

```
## HEISTS  pay (first run / replay), minutes, rate (band 0.8-2.2)
vault      stealth  ch 3  pay  1260  replay   755  10.0 min  rate 1.12
vault      loud     ch 3  pay  1575  replay   945   8.0 min  rate 1.74
vault      quantum  ch 3  pay  1510  replay   905  12.0 min  rate 1.11
convoy     stealth  ch 5  pay  1800  replay  1080  10.0 min  rate 1.22
convoy     loud     ch 5  pay  2250  replay  1350   8.0 min  rate 1.90
convoy     quantum  ch 5  pay  2160  replay  1295  12.0 min  rate 1.22
datacenter stealth  ch 7  pay  2530  replay  1520  10.0 min  rate 1.26
datacenter loud     ch 7  pay  3165  replay  1900   8.0 min  rate 1.97
datacenter quantum  ch 7  pay  3035  replay  1820  12.0 min  rate 1.26

```

```
## STEALTH MISSIONS  clean-run pay, rate
infiltrate ch 1  pay   485  rate 0.94
plant      ch 2  pay   715  rate 1.16
datatheft  ch 3  pay   985  rate 1.25
takedown   ch 4  pay  1035  rate 1.13

```

## Safehouses and crafting

```
## SAFEHOUSES  price in hours of income at the unlock chapter (band 0.4-1.6 h), upgrades in hours
loft       ch 1    2400 cr  0.54 h   upgrades  5400 cr  1.22 h
depot      ch 3    5400 cr  0.80 h   upgrades  5400 cr  0.80 h
penthouse  ch 5    9000 cr  1.01 h   upgrades  5400 cr  0.61 h
bunker     ch 7   13000 cr  1.08 h   upgrades  5400 cr  0.45 h

```

```
## CRAFTING  one craft (fee + parts) in credits and in hours at chapter 5, blueprint price apart (max 0.5 h)
mod_basic        blueprint     0  craft   401 cr  0.05 h
mod_arc          blueprint  1400  craft   590 cr  0.07 h
mod_phase        blueprint  1820  craft   758 cr  0.09 h
mod_singularity  blueprint  2520  craft  1878 cr  0.21 h
var_carbine      blueprint     0  craft  1008 cr  0.11 h
var_scatter      blueprint  1260  craft  1008 cr  0.11 h
var_lance        blueprint  1765  craft  1175 cr  0.13 h
var_grenade      blueprint  1510  craft  1008 cr  0.11 h
var_burst        blueprint  1090  craft  1008 cr  0.11 h
var_rail         blueprint  2015  craft  1175 cr  0.13 h
var_flux         blueprint  1430  craft  1008 cr  0.11 h
var_gravity      blueprint  2270  craft  2295 cr  0.26 h
var_minigun      blueprint  2770  craft  2295 cr  0.26 h
var_akimbo       blueprint  1595  craft  1008 cr  0.11 h
var_arc          blueprint  1850  craft  1175 cr  0.13 h
var_revolver     blueprint  1680  craft  1008 cr  0.11 h
var_whip         blueprint  1430  craft  1008 cr  0.11 h
var_blade        blueprint  1930  craft  1175 cr  0.13 h
```

## Open follow-ups

- Enemy specialists, drones and elites are not in the table (only the operative and the bosses): a per-type table would need the spawn mix per chapter.
- Hit rates and job durations are model estimates; replace them with measured values from `bot_full_game` / owner telemetry once a run logs per-kill and per-job times.
- Crafted-mod and skill-tree damage are modelled as smooth ramps, not from a real build.
