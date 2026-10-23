extends RefCounted
## downtown-fill (wave T) regression checks (run by self_test._downtown_plan_checks).

func run(world: WorldBuilder, suite: Node) -> void:
	await suite.get_tree().process_frame
	var stats: Dictionary = world.get_meta("downtown_map_stats", {})
	var fill: Dictionary = stats.get("fill", {})
	var can: Dictionary = fill.get("canopy", {})
	# 1. park canopy: thousands of trees in >= 4 crown species, no species dominating
	var species := 0
	for sp: String in ["rain", "angsana", "tembusu", "flame"]:
		if int(can.get(sp, 0)) >= 300:
			species += 1
	suite._check("downtown-fill: varied park canopy (>= 3000 crowns, >= 4 species with >= 300 each, shrub masses)",
		int(can.get("total", 0)) >= 3000 and species >= 4 and int(can.get("shrub", 0)) >= 300, str(can))
	# 2. no open lawn block: every 48 m lawn cell carries trees
	suite._check("downtown-fill: no flat lawn larger than a block (0 treeless 48 m lawn cells)",
		int(fill.get("lawn_blocks", 0)) >= 25 and int(fill.get("empty_lawn_blocks", -1)) == 0, "blocks=%s empty=%s" % [fill.get("lawn_blocks"), fill.get("empty_lawn_blocks")])
	# 3. shared procedural lawn material on the downtown turf
	suite._check("downtown-fill: downtown turf uses the varied lawn shader (>= 50000 lawn cells)", int(fill.get("lawn_cells", 0)) >= 50000, "cells=%s" % fill.get("lawn_cells"))
	# 4. roof plant on the podium / mid-rise roofs
	var roofs: Dictionary = fill.get("roofs", {})
	suite._check("downtown-fill: roof plant on >= 15 downtown roofs", int(roofs.get("roofs", 0)) >= 15, str(roofs))
	# 5. dressed arrival points
	var pz: Dictionary = fill.get("plazas", {})
	suite._check("downtown-fill: MBS arrival, NS Square and Merlion Park dressed (palms, cafe umbrellas, kiosks)",
		int(pz.get("mbs", 0)) >= 10 and int(pz.get("ns_square", 0)) >= 15 and int(pz.get("merlion", 0)) >= 3 and int(pz.get("umbrella_tables", 0)) >= 12 and int(pz.get("palms", 0)) >= 30, str(pz))
	# 6. rotor reads as blades: the disc shader draws blade smears
	var heli := world.get_tree().current_scene.get_node_or_null("Helicopter")
	var fx: Node = heli.get_node_or_null("HeliFX") if heli != null else null
	var code := ""
	if fx != null and fx.get("_main_mat") != null:
		code = (fx.get("_main_mat") as ShaderMaterial).shader.code
	suite._check("downtown-fill: helicopter rotor disc draws motion-blurred blade streaks", code.contains("smear") and code.contains("blade_col"), "fx=%s" % (fx != null))
	# 7. original names only, and lettering fits its plates
	var blocks := load("res://src/world/downtown/blocks.gd")
	var names: Array = []
	names.append_array(blocks.SHOP_NAMES)
	names.append_array(blocks.TOWER_NAMES)
	var bad := []
	for n: String in names:
		for real: String in ["SALAD STOP", "KINOKUNI", "SUSHI EXPRESS", "7-DAY", "OCEAN FINANCIAL", "CAPITAL SQUARE", "MARINA SQUARE", "KEPPEL BAY", "STRAITS TRADING", "MARINA ONE", "ROBINSON 77", "MAXWELL CHAMBERS"]:
			if n.contains(real):
				bad.append(n)
	suite._check("downtown-fill: no shop / tower name echoes a real chain or building", bad.is_empty(), str(bad))
	var fk := load("res://src/world/downtown/block_kits/frontage_kit.gd")
	var helix_w: float = fk.text_width("HELIX BRIDGE", 96) * fk.fit_pixel("HELIX BRIDGE", 96, 0.01, 2.3)
	var mono_w: float = fk.text_width("STRAITS MERCHANT TOWER", 64) * fk.fit_pixel("STRAITS MERCHANT TOWER", 64, 0.0105, 4.1)
	suite._check("downtown-fill: sign lettering fits its plate (Helix 2.6 m plate, 4.6 m name monolith)", helix_w <= 2.35 and mono_w <= 4.15, "helix=%.2f mono=%.2f" % [helix_w, mono_w])
	# 8. the Jubilee landing leaves the Esplanade waterfront paving flat
	var bridges := load("res://src/world/downtown/bridges.gd")
	suite._check("downtown-fill: Esplanade waterfront paving beside the Jubilee landing is flat", float(bridges.height_at(-650.0, -392.0)) < 0.01 and float(bridges.height_at(-645.0, -410.0)) < 0.01,
		"h=%.3f/%.3f" % [bridges.height_at(-650.0, -392.0), bridges.height_at(-645.0, -410.0)])
