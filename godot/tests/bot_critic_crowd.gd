extends "res://tests/bot_blast_arsenal.gd"
## Look-dev bot of the wave 113 critic (lens LOOK): the blast arsenal bot with the CROWD ALIVE (the original freezes the ambient city), so people on the pavement can be seen reacting to a blast: they run,
## the hit ones fall and dissolve. Same variables as bot_blast_arsenal.gd. A wide blast (BX_IDS=wb_gas_tank or ult_mega) reaches the pavements 11 m from the lane.
##   BX_OUT=/tmp/x BX_IDS=wb_gas_tank BX_DIST=4 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_critic_crowd.gd /tmp/x/seq 100000 1


func _setup() -> void:
	super._setup()
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(true)
