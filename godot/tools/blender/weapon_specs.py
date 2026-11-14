"""The spec table of the weapon kit: ONE row per weapon id of WeaponDefs.all_ids() (weapon_index.json is the list, dumped from the game): which recipe builds it, which faction palette it wears and the
parameters of its parts. A weapon's look follows from its row, so 229 weapons stay distinct in silhouette (receiver, handguard, muzzle, stock, magazine, optic, underbarrel) and in colour language
(factions: service olive, tactical black, desert tan, arctic white, sport blued + wood, industrial yellow, ordnance olive + orange, ceramic white + glow, quantum slate + violet ...).
Keywords of the names are honoured (SILENCED -> suppressor, DRUM -> drum magazine, BELT -> belt box, THERMAL -> thermal sight, TWIN -> two of them).
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = json.load(open(os.path.join(HERE, "weapon_index.json")))
BY_ID = {r["id"]: r for r in INDEX}

# hold offset: the weapon's pivot (shoulder / chest anchor) sits `reach` behind the muzzle, reach = right hand distance + hold (the carbine's right hand is 0.18 m in front of the pivot)
HOLD = {"rifle": 0.18, "pistol": 0.43, "smg": 0.22, "shotgun": 0.18, "sniper": 0.18, "lmg": 0.3, "launcher": 0.22, "melee": 0.14, "device": 0.36, "bow": 0.2, "energy": 0.2, "flamer": 0.24, "rotary": 0.24, "twin": 0.43}

S = {}


def put(id_, fn, fac="tactical", hold="rifle", **kw):
    S[id_] = dict(fn=fn, fac=fac, hold=hold, **kw)


def LG(id_, rec_, fac="tactical", hold="rifle", **kw):
    rec = kw.pop("rec", rec_)
    put(id_, "long", fac, hold, rec=rec, **kw)


def PI(id_, fac="tactical", **kw):
    put(id_, "pistol", fac, "pistol", **kw)


def EN(id_, fac="ceramic", hold="energy", **kw):
    put(id_, "energy", fac, hold, **kw)


def ME(id_, kind, fac="tactical", **kw):
    put(id_, "melee", fac, "melee", kind=kind, **kw)


def DV(id_, kind, fac="ordnance", **kw):
    put(id_, "device", fac, "device", kind=kind, **kw)


def LA(id_, kind, fac="ordnance", **kw):
    put(id_, "launcher", fac, "launcher", kind=kind, **kw)


# ------------------------------------------------------------------------------------------------------------------------------------------ PISTOLS
PI("pistol", "heritage", trim=True, slide_len=0.18)
PI("burst", "tactical", style="tac", muz="comp", cuts=True, mag="ext", trim=True)
PI("akimbo", "tactical", twin=True, style="std", trim=True)
PI("magnum", "chrome", style="heavy", slide_len=0.2, slide_h=0.042, slide_w=0.034, grip_w=0.038, muz="brake", rail=True)
PI("mpistol", "tactical", style="tac", slide_len=0.16, mag="long", brace=True, muz="flash", trim=True)
PI("p_spark", "tactical", style="compact", slide_len=0.14, grip_h=0.082, trim=True, muz="none")
PI("p_hush", "tactical", style="tac", mag="ext", muz="can", slide_len=0.178)
PI("p_flare", "industrial", style="heavy", slide_len=0.16, slide_h=0.04, slide_w=0.04, grip_w=0.04, muz="bell", rail=False)
PI("p_nail", "industrial", style="tac", slide_len=0.19, mag="long", muz="comp", rail=True, cuts=True)
PI("p_twin", "tactical", twin=True, style="tac", mag="ext", accent="teal", trim=True)
PI("p_mark", "riot", style="tac", optic="mini", laser=True, muz="none", trim=True)
PI("p_split", "ceramic", style="match", slide_len=0.2, cuts=True, muz="comp", trim=True)
put("revolver", "revolver", "sport", "pistol", bbl_len=0.13)
put("p_grit", "revolver", "heritage", "pistol", bbl_len=0.17, cyl_r=0.03, cyl_len=0.065, muz="brake")
EN("eplasma", "ceramic", hold="pistol", size="pistol", emitter="ring", front="rails", core="vial", profile="sleek", accent="orange")
EN("qblink", "quantum", hold="pistol", size="pistol", emitter="ring", front="rails", front_len=0.08, core="orb", profile="sleek")
EN("e_photon", "ceramic", hold="pistol", size="pistol", emitter="lens", front="tube", core="cell", profile="wedge", accent="slate")
EN("q_ppistol", "quantum", hold="pistol", size="pistol", emitter="twin", front="rails", core="crystal", profile="sleek", extras=["ghost"])
EN("stun", "riot", hold="pistol", size="pistol", emitter="fork", front="none", front_len=0.04, core="vial", profile="slab", stripe=True)

# ------------------------------------------------------------------------------------------------------------------------------------------ SMGs
SM = dict(rec="smg", rec_len=0.2, hg="short", hg_len=0.1, bbl=0.08, muz="comp", stock="fold", stock_len=0.22, mag="long", mag_len=0.13, optic="mini", rec_w=0.044)
LG("flux", "smg", "tactical", "smg", **{**SM, "trim": True})
LG("swarm", "smg", "desert", "smg", **{**SM, "rec_len": 0.15, "hg": "none", "hg_len": 0.02, "bbl": 0.06, "stock": "none", "optic": "reddot", "mag_len": 0.12, "trim": True})
LG("vector", "semi", "industrial", "smg", rec="semi", rec_len=0.2, hg="slotted", hg_len=0.12, bbl=0.07, muz="comp", stock="fold", stock_len=0.2, mag="box", mag_len=0.12, optic="reddot", trim=True)
LG("s_rivet", "smg", "service", "smg", **{**SM, "muz": "flash", "stock": "tele", "mag": "box", "optic": "reddot", "hg": "slotted", "hg_len": 0.12})
LG("s_hush", "smg", "tactical", "smg", **{**SM, "muz": "can", "stock": "fold", "optic": "mini", "hg": "short"})
LG("s_gale", "smg", "arctic", "smg", **{**SM, "rec_len": 0.14, "hg": "none", "hg_len": 0.03, "stock": "none", "bbl": 0.07, "mag_len": 0.1, "muz": "flash", "trim": True})
LG("s_cinder", "smg", "camo_desert", "smg", **{**SM, "hg": "slotted", "hg_len": 0.14, "muz": "flash", "stock": "tele", "mag": "curved", "optic": "iron", "accent": "orange", "trim": True})
LG("s_static", "smg", "ceramic", "smg", **{**SM, "hg": "ribbed", "hg_len": 0.12, "muz": "comp", "stock": "skeleton", "optic": "holo", "extras": ["arc"], "trim": True})
LG("s_brawl", "smg", "riot", "smg", **{**SM, "hg": "short", "hg_len": 0.1, "under": "vgrip", "muz": "brake", "stock": "none", "mag": "quad", "mag_len": 0.11, "optic": "iron"})
LG("s_double", "semi", "camo_urban", "smg", rec="semi", rec_len=0.21, hg="quad", hg_len=0.14, bbl=0.06, muz="flash", stock="tele", stock_len=0.2, mag="quad", mag_len=0.12, optic="reddot")
LG("s_drum", "smg", "carbon", "smg", **{**SM, "hg": "round", "hg_len": 0.14, "muz": "brake", "stock": "wire", "mag": "drum", "optic": "iron", "trim": True})
LG("s_lock", "smg", "tactical", "smg", **{**SM, "hg": "quad", "hg_len": 0.14, "muz": "comp", "stock": "tele", "optic": "holo", "extras": ["side_laser"], "accent": "red"})

# ------------------------------------------------------------------------------------------------------------------------------------------ ASSAULT, BATTLE, CARBINE
LG("carbine", "slab", "heritage", "rifle", rec_len=0.27, hg="wood", hg_len=0.24, bbl=0.09, muz="flash", stock="fixed", mag="banana", mag_len=0.17, optic="iron", hg_rails=False, trim=True)
LG("ranger", "ar", "service", "rifle", rec_len=0.27, hg="round", hg_len=0.26, bbl=0.07, muz="comp", stock="fixed", mag="box", optic="prism", extras=["carry"] if False else [], trim=True)
LG("bullpup", "bullpup", "camo_urban", "rifle", rec_len=0.28, hg="short", hg_len=0.16, bbl=0.09, muz="flash", stock="bullpup", stock_len=0.2, mag="curved", optic="holo", grip="slim", trim=True)
LG("battle", "ar", "service", "rifle", rec_len=0.3, hg="quad", hg_len=0.3, bbl=0.1, bbl_r=0.0105, muz="brake", stock="fixed", mag="long", mag_len=0.11, optic="prism", under="bipod", trim=True)
LG("a_pillar", "ar", "service", "rifle", rec_len=0.27, hg="quad", hg_len=0.26, bbl=0.07, muz="brake", stock="tele", mag="box", optic="reddot", under="vgrip", trim=True)
LG("a_flint", "ar", "camo_wood", "rifle", rec_len=0.27, hg="round", hg_len=0.24, bbl=0.08, muz="flash", stock="fixed", mag="box", optic="iron", under="launcher", trim=True)
LG("a_gravel", "slab", "service", "rifle", rec_len=0.26, hg="wood", hg_len=0.22, bbl=0.1, muz="comp", stock="fixed", mag="banana", mag_len=0.17, optic="iron", hg_rails=False, wood="dark")
LG("a_voltage", "ar", "ceramic", "rifle", rec_len=0.27, hg="slotted", hg_len=0.26, bbl=0.07, muz="comp", stock="tele", mag="box", optic="holo", extras=["arc"], trim=True)
LG("a_sable", "ar", "tactical", "rifle", rec_len=0.27, hg="quad", hg_len=0.24, bbl=0.06, muz="can", stock="tele", mag="box", optic="reddot")
LG("a_tempo", "semi", "desert", "rifle", rec_len=0.28, hg="slotted", hg_len=0.24, bbl=0.1, muz="brake", stock="thumb", mag="box", optic="prism", trim=True)
LG("a_ash", "slab", "camo_desert", "rifle", rec_len=0.26, hg="short", hg_len=0.2, bbl=0.1, muz="flash", stock="fold", stock_len=0.24, mag="banana", mag_len=0.17, optic="iron", accent="orange", trim=True)
LG("a_tundra", "slab", "arctic", "rifle", rec_len=0.27, hg="slotted", hg_len=0.25, bbl=0.08, muz="brake", stock="fixed", mag="curved", mag_len=0.16, optic="prism", accent="slate", trim=True)
LG("a_banner", "bullpup", "riot", "rifle", rec_len=0.28, hg="short", hg_len=0.16, bbl=0.1, muz="comp", stock="bullpup", stock_len=0.2, mag="box", optic="holo", extras=["side_laser"], trim=True)
LG("a_piercer", "ar", "carbon", "rifle", rec_len=0.28, hg="shroud", hg_len=0.3, bbl=0.1, muz="fin", stock="skeleton", mag="long", mag_len=0.11, optic="scope", under="bipod", trim=True)
LG("a_splinter", "slab", "camo_wood", "rifle", rec_len=0.26, hg="slotted", hg_len=0.22, bbl=0.09, muz="flash", stock="thumb", mag="curved", mag_len=0.15, optic="reddot", trim=True)
LG("a_gauntlet", "ar", "industrial", "rifle", rec_len=0.28, hg="ribbed", hg_len=0.24, bbl=0.09, bbl_r=0.0105, muz="brake", stock="fixed", mag="long", mag_len=0.14, optic="iron", extras=["carry"], under="stub")
LG("b_anvil", "semi", "service", "rifle", rec_len=0.3, hg="wood", hg_len=0.3, bbl=0.1, muz="brake", stock="fixed", mag="long", mag_len=0.11, optic="iron", hg_rails=False, wood="light")
LG("b_crest", "ar", "ceramic", "rifle", rec_len=0.3, hg="quad", hg_len=0.3, bbl=0.1, muz="comp", stock="tele", mag="box", optic="prism", trim=True)
LG("b_bastion", "ar", "ordnance", "rifle", rec_len=0.3, hg="shroud", hg_len=0.3, bbl=0.1, bbl_r=0.011, muz="brake", stock="fixed", mag="long", mag_len=0.12, optic="iron", under="bipod", extras=["carry"])
LG("b_meridian", "semi", "sport", "rifle", rec_len=0.3, hg="slotted", hg_len=0.34, bbl=0.12, muz="comp", stock="thumb", mag="long", mag_len=0.11, optic="scope", wood="dark", trim=True)
LG("b_scythe", "ar", "quantum", "rifle", rec_len=0.3, hg="round", hg_len=0.3, bbl=0.1, muz="flash", stock="skeleton", mag="curved", mag_len=0.16, optic="holo", trim=True)
LG("b_vanguard", "semi", "desert", "rifle", rec_len=0.3, hg="shroud", hg_len=0.32, bbl=0.12, bbl_r=0.0115, muz="fin", stock="fixed", mag="long", mag_len=0.12, optic="scope", under="bipod")
LG("c_scout", "ar", "service", "rifle", rec_len=0.25, hg="short", hg_len=0.18, bbl=0.06, muz="flash", stock="tele", stock_len=0.22, mag="box", mag_len=0.12, optic="iron")
LG("c_dash", "smg", "tactical", "rifle", rec="smg", rec_len=0.24, hg="short", hg_len=0.16, bbl=0.06, muz="comp", stock="skeleton", stock_len=0.22, mag="box", mag_len=0.13, optic="reddot", trim=True)
LG("c_quill", "ar", "tactical", "rifle", rec_len=0.25, hg="quad", hg_len=0.18, bbl=0.05, muz="can", stock="tele", stock_len=0.22, mag="box", mag_len=0.12, optic="mini", accent="slate")
LG("c_ember", "slab", "camo_desert", "rifle", rec_len=0.24, hg="short", hg_len=0.17, bbl=0.07, muz="flash", stock="fold", stock_len=0.24, mag="banana", mag_len=0.15, optic="iron", accent="orange", trim=True)
LG("c_tether", "ar", "quantum", "rifle", rec_len=0.25, hg="slotted", hg_len=0.2, bbl=0.06, muz="comp", stock="tele", stock_len=0.22, mag="curved", mag_len=0.14, optic="holo", trim=True)
LG("c_nimbus", "ar", "ceramic", "rifle", rec_len=0.25, hg="ribbed", hg_len=0.18, bbl=0.06, muz="flash", stock="tele", stock_len=0.22, mag="box", mag_len=0.12, optic="reddot", extras=["arc"], trim=True)

# ------------------------------------------------------------------------------------------------------------------------------------------ DMR and SNIPER
LG("marksman", "semi", "ceramic", "rifle", rec_len=0.28, hg="slotted", hg_len=0.32, bbl=0.1, muz="comp", stock="thumb", mag="long", mag_len=0.11, optic="scope", under="bipod", trim=True)
LG("dmr", "semi", "service", "sniper", rec_len=0.28, hg="shroud", hg_len=0.34, bbl=0.12, bbl_r=0.0105, muz="brake", stock="fixed", mag="long", mag_len=0.11, optic="scope", under="bipod")
LG("d_sentry", "semi", "camo_wood", "sniper", rec_len=0.28, hg="slotted", hg_len=0.34, bbl=0.12, muz="comp", stock="thumb", mag="long", mag_len=0.11, optic="scope", trim=True)
LG("d_arbiter", "semi", "quantum", "sniper", rec_len=0.28, hg="quad", hg_len=0.34, bbl=0.12, muz="flash", stock="skeleton", mag="long", mag_len=0.11, optic="scope_long", trim=True)
LG("d_tally", "ar", "industrial", "sniper", rec_len=0.28, hg="round", hg_len=0.32, bbl=0.12, muz="brake", stock="fixed", mag="box", optic="prism", under="bipod")
LG("d_whisper", "semi", "tactical", "sniper", rec_len=0.28, hg="quad", hg_len=0.32, bbl=0.1, muz="can", stock="tele", mag="long", mag_len=0.11, optic="scope")
LG("d_lancer", "bolt", "ceramic", "sniper", rec_len=0.24, hg="tube", hg_len=0.36, bbl=0.12, muz="comp", stock="sniper", stock_len=0.3, mag="box", mag_len=0.08, optic="scope_long", mag_d=0.58, trim=True)
LG("d_rook", "semi", "desert", "sniper", rec_len=0.28, hg="short", hg_len=0.3, bbl=0.14, muz="brake", stock="thumb", mag="long", mag_len=0.11, optic="reddot", under="vgrip", trim=True)
LG("rail", "bolt", "sport", "sniper", rec_len=0.24, hg="tube", hg_len=0.34, bbl=0.2, bbl_r=0.012, muz="comp", stock="thumb", stock_len=0.3, mag="box", mag_len=0.08, optic="scope_long", mag_d=0.6, trim=True)
LG("bolt", "bolt", "heritage", "sniper", rec_len=0.22, hg="wood", hg_len=0.3, bbl=0.2, bbl_r=0.012, muz="crown", stock="fixed", stock_len=0.3, mag="box", mag_len=0.08, optic="scope", mag_d=0.6, hg_rails=False, wood="dark", trim=True)
LG("amr", "bolt", "service", "sniper", rec_len=0.26, hg="shroud", hg_len=0.36, bbl=0.16, bbl_r=0.0145, muz="brake", stock="sniper", stock_len=0.28, mag="long", mag_len=0.1, optic="scope_long", under="bipod_open", mag_d=0.62)
LG("n_ridge", "bolt", "camo_wood", "sniper", rec_len=0.22, hg="tube", hg_len=0.32, bbl=0.22, bbl_r=0.012, muz="crown", stock="fixed", stock_len=0.3, mag="none", optic="scope", hg_rails=False)
LG("n_stride", "semi", "desert", "sniper", rec_len=0.28, hg="slotted", hg_len=0.36, bbl=0.14, bbl_r=0.0115, muz="brake", stock="sniper", stock_len=0.28, mag="long", mag_len=0.11, optic="scope_long", under="bipod")
LG("n_breaker", "bolt", "industrial", "sniper", rec_len=0.26, hg="shroud", hg_len=0.38, bbl=0.14, bbl_r=0.0155, muz="brake", stock="sniper", stock_len=0.3, mag="long", mag_len=0.1, optic="scope_long", under="bipod_open", mag_d=0.64)
LG("n_umbra", "bolt", "tactical", "sniper", rec_len=0.22, hg="tube", hg_len=0.34, bbl=0.18, bbl_r=0.0115, muz="can", stock="sniper", stock_len=0.3, mag="box", mag_len=0.08, optic="scope", accent="slate")
LG("n_lattice", "bolt", "quantum", "sniper", rec_len=0.24, hg="ribbed", hg_len=0.34, bbl=0.16, muz="flash", stock="skeleton", stock_len=0.3, mag="box", mag_len=0.08, optic="scope_long", trim=True)
LG("n_prism", "bolt", "carbon", "sniper", rec_len=0.24, hg="tube", hg_len=0.32, bbl=0.16, muz="comp", stock="thumb", stock_len=0.28, mag="box", mag_len=0.08, optic="thermal", trim=True)
LG("n_horizon", "bolt", "arctic", "sniper", rec_len=0.24, hg="shroud", hg_len=0.36, bbl=0.2, bbl_r=0.012, muz="brake", stock="sniper", stock_len=0.32, mag="long", mag_len=0.1, optic="scope_long", under="bipod", mag_d=0.62)
EN("lance", "ceramic", hold="sniper", size="rifle", emitter="prism", front="rails", front_len=0.56, core="crystal", profile="sleek", stock="fixed", optic="scope", accent="navy")
put("xbow", "bow", "sport", "bow", kind="cross", optic="scope")

# ------------------------------------------------------------------------------------------------------------------------------------------ SHOTGUNS
PU = dict(rec="pump", rec_len=0.2, hg="none", hg_len=0.0, bbl=0.42, bbl_r=0.0125, muz="choke", stock="fixed", stock_len=0.26, mag="none", tube=0.4, optic="iron", grip="none")
LG("scatter", "pump", "sport", "shotgun", **{**PU, "trim": True})
LG("breacher", "pump", "tactical", "shotgun", **{**PU, "bbl": 0.36, "tube": 0.32, "muz": "duck", "stock": "none", "grip": "std", "bbl_r": 0.014, "trim": True})
LG("sawn", "pump", "heritage", "shotgun", **{**PU, "bbl": 0.3, "tube": 0.0, "muz": "none", "stock": "fixed", "stock_len": 0.14, "grip": "std", "optic": "none", "sights": False, "trim": True})
LG("auto", "semi", "ordnance", "shotgun", rec="semi", rec_len=0.26, hg="short", hg_len=0.26, bbl=0.24, bbl_r=0.013, muz="choke", stock="fixed", mag="long", mag_len=0.12, optic="reddot", tube=0.3, trim=True)
LG("g_bulwark", "pump", "service", "shotgun", **{**PU, "bbl": 0.5, "stock": "fixed", "stock_len": 0.26, "optic": "iron", "muz": "choke", "grip": "none"})
LG("g_rampart", "semi", "camo_wood", "shotgun", rec="semi", rec_len=0.26, hg="slotted", hg_len=0.2, bbl=0.2, bbl_r=0.0135, muz="choke", stock="tele", mag="long", mag_len=0.12, optic="reddot", tube=0.28)
LG("g_twinbore", "pump", "heritage", "shotgun", **{**PU, "bbl": 0.55, "tube": 0.0, "muz": "none", "extras": ["double"], "optic": "none", "sights": True, "trim": False, "wood": "dark"})
LG("g_cyclone", "semi", "industrial", "shotgun", rec="semi", rec_len=0.26, hg="short", hg_len=0.22, bbl=0.22, bbl_r=0.014, muz="brake", stock="fixed", mag="drum", optic="iron", under="vgrip", tube=0.3)
LG("g_doorkick", "pump", "riot", "shotgun", **{**PU, "bbl": 0.3, "tube": 0.26, "muz": "duck", "stock": "none", "grip": "std", "optic": "none", "sights": False, "bbl_r": 0.014})
LG("g_slugger", "bolt", "desert", "shotgun", rec_len=0.26, hg="tube", hg_len=0.3, bbl=0.18, bbl_r=0.0135, muz="comp", stock="thumb", mag="box", mag_len=0.07, optic="scope", mag_d=0.5)
LG("g_triple", "semi", "quantum", "shotgun", rec="semi", rec_len=0.26, hg="short", hg_len=0.18, bbl=0.2, bbl_r=0.0135, muz="choke", stock="tele", mag="curved", mag_len=0.14, optic="holo", extras=["triple"], trim=True)
LG("g_flechette", "semi", "toxic", "shotgun", rec="semi", rec_len=0.26, hg="slotted", hg_len=0.2, bbl=0.2, bbl_r=0.0135, muz="comp", stock="skeleton", mag="long", mag_len=0.13, optic="reddot", tube=0.26, trim=True)

# ------------------------------------------------------------------------------------------------------------------------------------------ LMG and ROTARY
BX = dict(rec="box", rec_len=0.3, hg="shroud", hg_len=0.3, bbl=0.1, bbl_r=0.011, muz="brake", stock="fixed", stock_len=0.24, mag="belt", optic="prism", under="bipod", mag_d=0.62)
LG("lmg", "box", "service", "lmg", **{**BX, "trim": True})
LG("l_bastion", "box", "camo_wood", "lmg", **{**BX, "muz": "flash", "optic": "iron", "extras": ["carry"]})
LG("l_belt", "box", "desert", "lmg", **{**BX, "hg": "round", "hg_len": 0.26, "muz": "comp", "optic": "reddot"})
LG("l_cinder", "box", "ordnance", "lmg", **{**BX, "hg": "ribbed", "hg_len": 0.28, "optic": "iron", "accent": "orange", "under": "bipod_open"})
LG("l_anchor", "box", "industrial", "lmg", **{**BX, "bbl_r": 0.0125, "hg_len": 0.34, "stock": "skeleton", "optic": "scope", "mag": "belt"})
LG("l_volt", "box", "ceramic", "lmg", **{**BX, "mag": "drum", "extras": ["arc"], "optic": "holo", "trim": True})
LG("l_rampart", "box", "arctic", "lmg", **{**BX, "hg": "slotted", "stock": "tele", "mag": "belt", "optic": "prism", "accent": "slate"})
put("minigun", "rotary", "industrial", "rotary", barrels=6, feed="drum", electric=True)
put("chaingun", "rotary", "ordnance", "rotary", barrels=6, feed="belt", electric=True, bbl_len=0.38)
put("r_whirl", "rotary", "service", "rotary", barrels=6, feed="drum", bbl_len=0.36)
put("r_tempest", "rotary", "ceramic", "rotary", barrels=5, feed="cable", electric=True, bbl_len=0.4)
put("r_grinder", "rotary", "industrial", "rotary", barrels=6, feed="tank", bbl_len=0.34, housing_len=0.28)
put("r_swarm", "rotary", "toxic", "rotary", barrels=8, feed="belt", bbl_len=0.3, cluster_r=0.04)

# ------------------------------------------------------------------------------------------------------------------------------------------ BOWS and FLAMERS
put("bw_hunter", "bow", "heritage", "bow", kind="long", span=0.82, wood="light")
put("bw_recurve", "bow", "sport", "bow", kind="recurve", span=0.72)
put("bw_repeater", "bow", "tactical", "bow", kind="repeater", optic="reddot")
put("bw_fire", "bow", "camo_desert", "bow", kind="compound", span=0.6, accent="orange")
put("bw_heavybolt", "bow", "industrial", "bow", kind="heavy", optic="scope", span=0.78, len=0.72, heavy_stock=True)
put("flame", "flamer", "industrial", "flamer", tanks=2, nozzle_len=0.4)
put("f_torch", "flamer", "ordnance", "flamer", tanks=1, nozzle_len=0.36, tank_r=0.05)
put("f_gel", "flamer", "industrial", "flamer", tanks=2, nozzle_len=0.44, top_tank=True, tank_r=0.05)
put("f_cryo", "flamer", "arctic", "flamer", tanks=2, nozzle_len=0.42, top_tank=True, tank_r=0.042)
put("f_toxic", "flamer", "toxic", "flamer", tanks=3, nozzle_len=0.4, tank_r=0.036)

# ------------------------------------------------------------------------------------------------------------------------------------------ MELEE
ME("blade", "sabre", "quantum", blade=0.8, hilt=0.26)
ME("whip", "whip", "ceramic")
ME("knife", "dagger", "quantum", glow=True, blade=0.27, hilt=0.15)
ME("katana", "katana", "carbon", hilt=0.26)
ME("bat", "bat", "heritage")
ME("tknife", "knives", "tactical")
ME("eblade", "sabre", "ceramic", blade=0.9, hilt=0.28, width=0.04)
ME("emaul", "maul", "ceramic")
ME("q_blinkblade", "blink", "quantum", blade=0.82, hilt=0.26)
ME("m_dagger", "dagger", "tactical")
ME("m_hook", "hook", "service")
ME("m_machete", "machete", "service")
ME("m_twinkat", "katana", "carbon", xs=(0.07, -0.07), hilt=0.24, blade=0.66)
ME("m_hatchet", "hatchet", "heritage")
ME("m_axe", "axe", "heritage")
ME("m_greataxe", "greataxe", "ceramic")
ME("m_mallet", "mallet", "heritage")
ME("m_sledge", "sledge", "industrial")
ME("m_crowbar", "crowbar", "industrial")
ME("m_spear", "spear", "heritage")
ME("m_staff", "staff", "heritage")
ME("m_chainblade", "chainblade", "industrial")
ME("m_arcsabre", "arcsabre", "ceramic", blade=0.8)
ME("m_cutlass", "cutlass", "ceramic", glow=True)
ME("m_phaseblade", "phaseblade", "quantum", blade=0.84)
ME("m_baton", "baton", "riot")
ME("m_gauntlet", "gauntlet", "ceramic")
ME("m_chainwhip", "chainwhip", "tactical")
ME("m_shield", "shield", "riot")
ME("m_tonfa", "tonfa", "riot")
ME("m_scythe", "scythe", "quantum")

# ------------------------------------------------------------------------------------------------------------------------------------------ ENERGY, QUANTUM, EXOTIC
EN("arc", "ceramic", size="carbine", emitter="fork", front="coils", core="coil", profile="slab", stock="fixed", accent="slate")
EN("erepeat", "ceramic", size="rifle", emitter="ring", front="rails", core="cell", profile="hump", stock="fixed", optic="holo")
EN("espike", "ceramic", size="rifle", emitter="claw", front="spine", core="crystal", profile="wing", stock="fixed", accent="violet")
EN("ebeam", "ceramic", size="cannon", emitter="prism", front="lens", core="crystal", profile="sleek", stock="fixed", optic="scope", extras=["foregrip"])
EN("e_prifle", "ceramic", size="rifle", emitter="dish", front="rails", core="cell", profile="wedge", stock="fixed", accent="orange")
EN("e_splinter", "ceramic", size="carbine", emitter="needle", front="spine", core="crystal", profile="sleek", stock="none", accent="violet")
EN("e_ioncarb", "ceramic", size="carbine", emitter="lens", front="tube", core="orb", profile="hump", stock="fixed", optic="mini")
EN("e_pulse", "ceramic", size="rifle", emitter="ring", front="coils", core="coil", profile="slab", stock="fixed", accent="slate")
EN("e_shock", "ceramic", size="rifle", emitter="fork", front="fins", core="cell", profile="wing", stock="fixed", accent="navy")
EN("e_ioncan", "ceramic", size="cannon", emitter="funnel", front="lens", core="orb", profile="hump", stock="fixed", extras=["foregrip"])
EN("e_lance", "ceramic", size="rifle", emitter="prism", front="rails", front_len=0.4, core="crystal", profile="sleek", stock="fixed", optic="scope", accent="slate")
EN("e_scatter", "ceramic", size="carbine", emitter="bell", front="tube", core="vial", profile="wedge", stock="fixed", accent="orange")
EN("e_laser", "ceramic", size="rifle", emitter="lens", front="lens", core="cell", profile="wing", stock="fixed", optic="holo", extras=["cheek"])
EN("qsuper", "quantum", size="rifle", emitter="twin", front="rails", core="orb", profile="sleek", stock="fixed", extras=["ghost"])
EN("qlink", "quantum", size="rifle", emitter="fork", front="spine", core="vial", profile="hump", stock="fixed", extras=["link"])
EN("qcollapse", "quantum", size="cannon", emitter="funnel", front="tube", core="orb", profile="hump", stock="fixed", extras=["foregrip"])
EN("qphase", "quantum", size="rifle", emitter="claw", front="lens", core="coil", profile="sleek", stock="fixed", optic="holo")
EN("qstasis", "quantum", size="rifle", emitter="dish", front="tube", core="vial", profile="wedge", stock="fixed")
EN("q_ensmg", "quantum", size="smg", emitter="fork", front="rails", core="vial", profile="sleek", stock="none", extras=["link"])
EN("q_supershot", "quantum", size="carbine", emitter="twin", front="rails", front_len=0.16, core="cell", profile="wing", stock="fixed", extras=["ghost"])
EN("q_crifle", "quantum", size="rifle", emitter="funnel", front="rails", core="crystal", profile="wing", stock="fixed", optic="holo")
EN("q_decoh", "quantum", size="cannon", emitter="claw", front="fins", core="orb", profile="hump", stock="fixed", extras=["ghost", "antenna"])
EN("x_grav", "ceramic", size="rifle", emitter="plate", front="coils", core="orb", profile="hump", stock="fixed", accent="violet")
EN("x_frost", "arctic", size="rifle", emitter="bell", front="fins", core="vial", profile="wedge", stock="fixed", extras=["foregrip"])
EN("x_tesla", "ceramic", size="rifle", emitter="coilstack", front="coils", core="crystal", profile="slab", stock="none", extras=["heatsink"])
EN("x_sonic", "ceramic", size="cannon", emitter="bell", front="tube", core="cell", profile="slab", stock="fixed", extras=["foregrip"])
EN("x_repulse", "ceramic", size="rifle", emitter="plate", front="rails", core="orb", profile="hump", stock="fixed")
EN("x_prism", "ceramic", size="rifle", emitter="prism", front="lens", core="crystal", profile="sleek", stock="fixed", optic="holo")
EN("railgun", "ordnance", size="cannon", emitter="ring", front="rails", front_len=0.42, core="coil", profile="slab", stock="fixed", optic="scope", extras=["foregrip"])

# ------------------------------------------------------------------------------------------------------------------------------------------ LAUNCHERS
LA("rocket", "rocket", "ordnance", tube_len=0.85, tube_r=0.05)
LA("gravity", "plasma", "quantum", tube_len=0.8, tube_r=0.055)
LA("epod", "swarm", "ordnance", tubes=6, tube_len=0.5)
LA("cmissile", "cluster", "ordnance", tube_len=0.85, tube_r=0.058)
LA("napalm", "thermo", "industrial", tube_len=0.8, tube_r=0.06)
LA("sing", "plasma", "quantum", tube_len=0.9, tube_r=0.06)
LA("seeker", "guided", "service", tube_len=0.95, tube_r=0.05, optic="scope")
LA("la_pump", "pump", "tactical")
LA("la_revolver", "revolver", "ordnance")
LA("la_rotary", "rotary", "industrial")
LA("la_rocket", "rocket", "service", tube_len=0.9, tube_r=0.052)
LA("la_laser", "guided", "tactical", tube_len=0.95, tube_r=0.05, optic="prism")
LA("la_wire", "wire", "service", tube_len=0.92, tube_r=0.05)
LA("la_swarm", "swarm", "camo_wood", tubes=7, tube_len=0.55)
LA("la_antiair", "aa", "ceramic", tube_len=1.05, tube_r=0.045, optic="reddot")
LA("la_bunker", "bunker", "industrial", tube_len=0.8, tube_r=0.06)
LA("la_cluster", "cluster", "camo_desert", tube_len=0.78, tube_r=0.062, rack=True)
LA("la_recoilless", "recoilless", "desert", tube_len=1.0, tube_r=0.045, optic="scope")
LA("la_mortar", "mortar", "ordnance", tube_len=0.7, tube_r=0.045, front=0.04)
LA("la_plasma", "plasma", "ceramic", tube_len=0.85, tube_r=0.05)
LA("la_thermo", "thermo", "industrial", tube_len=0.82, tube_r=0.065)

# ------------------------------------------------------------------------------------------------------------------------------------------ GRENADES, MINES, STRIKES
for gid, kind, fac in (("gr_frag", "frag", "ordnance"), ("gr_tick", "tick", "tactical"), ("gr_scatter", "scatter", "ordnance"), ("gr_ember", "ember", "industrial"), ("gr_blinder", "blinder", "riot"),
                       ("gr_fog", "fog", "arctic"), ("gr_spark", "spark", "ceramic"), ("gr_well", "well", "quantum"), ("gr_still", "still", "ceramic"), ("gr_arc", "arc", "ceramic"),
                       ("gr_rattle", "rattle", "service"), ("gr_collapse", "collapse", "quantum"), ("grenade", "well", "quantum")):
    DV(gid, kind, fac)
for mid, kind, fac in (("mn_prox", "prox", "service"), ("mn_trip", "trip", "camo_wood"), ("mn_directional", "directional", "ordnance"), ("mn_gravity", "gravity", "quantum"), ("mn_c4", "c4", "ordnance"),
                       ("mn_remote", "remote", "tactical"), ("mn_satchel", "satchel", "desert"), ("mn_shaped", "shaped", "industrial"), ("mn_bounce", "bounce", "ordnance"), ("mn_emp", "emp", "ceramic")):
    DV(mid, kind, fac)
DV("st_artillery", "strike", "service", style="desig", variant=1)
DV("st_smokescreen", "fog", "arctic")
DV("st_air_s", "strike", "ordnance", style="beacon", variant=0)
DV("st_air_m", "strike", "ordnance", style="tablet", variant=0)
DV("st_air_l", "strike", "industrial", style="desig", variant=2)
DV("st_carpet", "strike", "tactical", style="tablet", variant=1)
DV("st_fireline", "strike", "industrial", style="beacon", variant=2)
DV("st_orbital", "strike", "quantum", style="beacon", variant=3)
DV("orbital", "strike", "ceramic", style="beacon", variant=3)
DV("st_emp", "strike", "ceramic", style="tablet", variant=2)
DV("st_supply", "strike", "desert", style="beacon", variant=1)

MISSING = [r["id"] for r in INDEX if r["id"] not in S]
EXTRA = [k for k in S if k not in BY_ID]
if MISSING or EXTRA:
    raise SystemExit("weapon_specs: missing %s, unknown %s" % (MISSING, EXTRA))
