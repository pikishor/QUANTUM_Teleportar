extends "res://tests/bot_blast_arsenal.gd"
## Look-dev bot of the wave 113 critic (lens LOOK): the blast arsenal bot plus a table entry that is REGISTERED at run time (what a wave 115 snake bomb does), so the
## "registered entry" blast can be looked at beside the built-in rows. Same variables as bot_blast_arsenal.gd (BX_OUT, BX_IDS, BX_DIST, BX_SPOT, BX_CAR, BX_FOES, QUALITY, BOT_RES).
##   BX_OUT=/tmp/x BX_IDS=gr_frag,crit_snake BX_DIST=6,14,28 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_critic_blasts.gd /tmp/x/seq 100000 1


func _setup() -> void:
	BlastTable.register(&"crit_snake", {"cat": &"ordnance", "name": "SNAKE BOMB", "radius": 5.0, "core": 1.0, "enemy": 140.0, "vehicle": 160.0, "element": &"quantum", "knock": 8.0, "lift": 8.0,
		"status": {"k": &"stun", "t": 1.5, "p": 1.0}, "fx": &"default", "deliver": {"mode": &"drop"}})
	super._setup()
