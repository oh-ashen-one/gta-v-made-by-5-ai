extends Node
## Parent-run data-only QA. No actors, owner saves, engine launch or recovery.
const Domain = preload("res://src/world/geography/source_domain.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const ACTUAL_DIR := "res://data/geography/domain/osm-2026-10-27"
const ACTUAL_IDENTITY := "82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834"
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var qa := ""
var finished := false

func check(label: String,ok: bool,detail: String = "") -> bool:
	checks += 1
	print("[source-domain] %s %s %s" % ["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _write(path: String,text: String) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

func _descriptors(hash: String) -> Array:
	var result: Array = []
	for kind: String in ["territory","land","water"]:
		result.append({"kind":kind,"provider_id":"singapore-source-domain/"+kind+"/v1/"+hash,
			"source_reference":"source-domain/v1/"+hash,"registry_version":Domain.REGISTRY_VERSION})
	return result

func _rectangle(x: float,z: float,w: float,h: float) -> Array:
	return [x,z,x+w,z,x+w,z+h,x,z+h,x,z]

func _polygon(id: String,rings: Array) -> Dictionary:
	var ring: Array = rings[0]
	var bounds: Array = [INF,INF,-INF,-INF]
	for i in range(0,ring.size(),2):
		bounds[0] = minf(bounds[0],ring[i])
		bounds[1] = minf(bounds[1],ring[i+1])
		bounds[2] = maxf(bounds[2],ring[i])
		bounds[3] = maxf(bounds[3],ring[i+1])
	return {"id":id,"bounds_xz":bounds,"rings":rings}

func _inventory(polygons: Array) -> Dictionary:
	var rings := 0
	var vertices := 0
	for polygon: Dictionary in polygons:
		rings += polygon.rings.size()
		for ring: Array in polygon.rings: vertices += ring.size() >> 1
	return {"polygons":polygons.size(),"rings":rings,"vertices":vertices}

func _seal(fixture: Dictionary) -> void:
	var text: String = JSON.stringify(fixture.data)
	fixture.identity.dataset = {"file":"domain.json","sha256":_sha(text.to_utf8_buffer()),"bytes":text.to_utf8_buffer().size()}
	fixture.identity.counts = fixture.data.counts.duplicate(true)
	fixture.identity.bindings = fixture.data.bindings.duplicate(true)
	fixture.identity.provider_descriptors = _descriptors(fixture.identity.dataset.sha256)
	_write(fixture.base.path_join("domain.json"),text)
	var identity_text: String = JSON.stringify(fixture.identity)
	_write(fixture.base.path_join("identity.json"),identity_text)
	fixture["identity_sha"] = _sha(identity_text.to_utf8_buffer())

func _fixture(name: String) -> Dictionary:
	var base: String = qa.path_join(name)
	DirAccess.make_dir_absolute(base)
	var territory: Array = [_polygon("synthetic/main",[_rectangle(80000,80000,10,10),_rectangle(80003,80003,4,4)]),
		_polygon("synthetic/island",[_rectangle(80020,80020,1,1)]),_polygon("synthetic/millimetre",[_rectangle(80100,80100,.001,.001)])]
	var coast: Array = [_polygon("synthetic/coast",[_rectangle(80001,80001,1,1)])]
	var binding := {"snapshot_manifest_sha256":"a".repeat(64),"country_wgs84_sha256":"b".repeat(64),"coastline_sha256":"c".repeat(64),
		"coast_identity_sha256":"d".repeat(64),"pbf_sha256":"e".repeat(64),"projection_implementation_sha256":"f".repeat(64),"source_snapshot_utc":"SYNTHETIC_FIXTURE"}
	var data := {"schema":Domain.DATA_SCHEMA,"version":1,"registry_version":Domain.REGISTRY_VERSION,"georeference":Domain.FRAME.duplicate(true),
		"bindings":binding,"territory":territory,"coast_enclosure":coast,"counts":{"territory":_inventory(territory),"coast_enclosure":_inventory(coast)},
		"data_scope":"SYNTHETIC data-only test; not Singapore or a terrain build",
		"semantic_contract":{"territory_boundary":"inclusive","territory_is_land":false,"coast_enclosure_is_dryland":false,"land_state":"unknown","water_state":"unknown",
			"finite_water_columns_available":false,"inland_water_resolved":false,"terrain_elevation_resolved":false,"tides_resolved":false,"source_completeness_certified":false}}
	var fixture := {"base":base,"data":data,"identity":{"schema":Domain.IDENTITY_SCHEMA,"version":1,"registry_version":Domain.REGISTRY_VERSION}}
	_seal(fixture)
	return fixture

func _owned(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path != path.simplify_path(): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(parent)
		if folder != null and folder.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--qa-session")
	if at < 0 or at+1 >= args.size():
		push_error("Source-domain QA requires explicit private --qa-session")
		get_tree().quit(2)
		return
	qa = args[at+1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/"+qa.trim_prefix("/tmp/")
	qa = qa.path_join("source-domain-fixtures")
	if not _owned(qa) or DirAccess.dir_exists_absolute(qa) or FileAccess.file_exists(qa) or DirAccess.make_dir_recursive_absolute(qa) != OK:
		push_error("Source-domain QA refuses unsafe/existing evidence")
		get_tree().quit(2)
		return
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not finished:
			check("bounded source-domain completion",false,"45-second watchdog")
			_finish())
	watchdog.start(45.0)
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = _fixture("good")
	var domain := Domain.new()
	if not check("synthetic immutable dataset configures",domain.configure(fixture.base,fixture.identity_sha,"a".repeat(64)),domain.last_error):
		_finish()
		return
	for row: Array in [[80001.5,80001.5,"inside"],[80005.0,80005.0,"outside"],[80000.0,80005.0,"inside"],[80003.0,80005.0,"inside"],[80020.5,80020.5,"inside"],[80015.0,80015.0,"outside"]]:
		var result: Dictionary = domain.observe([row[0],-500.0,row[1]])
		check("territory holes/multipart/inclusive boundary "+str(row),result.get("ok",false) and result.territory.state == row[2],str(result))
	for point: Array in [[80000.0,0.0,80005.0],[80003.0,0.0,80005.0]]:
		check("source boundary identified independently",domain.observe(point).diagnostics.territory_relation == "boundary")
	check("millimetre region at80km stays inside",domain.observe([80100.0005,0.0,80100.0005]).territory.state == "inside")
	check("outside millimetre region does not round into it",domain.observe([80100.0011,0.0,80100.0005]).territory.state == "outside")
	var on_coast: Dictionary = domain.observe([80001.5,-1000.0,80001.5])
	check("coast enclosure is a separate diagnostic",on_coast.diagnostics.coast_enclosure_relation == "inside")
	check("coast enclosure invents neitherdryground norwatercolumn",on_coast.land.state == "unknown" and on_coast.water.state == "unknown" and on_coast.water.payload.is_empty())
	check("outside coast still has unresolved hydrology",domain.observe([80002.5,10000.0,80002.5]).water.state == "unknown")
	for bad in [Vector3(80001.5,0,80001.5),PackedFloat32Array([80001.5,0,80001.5]),[true,0,1],[0,0],[NAN,0,1],[INF,0,1],[1e30,0,1]]:
		var invalid: Dictionary = domain.observe(bad)
		check("malformed source remains unknown "+str(typeof(bad)),not invalid.ok and invalid.territory.state == "unknown")
	check("packed64source accepted",domain.observe(PackedFloat64Array([80001.5,0,80001.5])).ok)
	var before: Dictionary = domain.metadata().stats
	for i in 1000: domain.observe([80001.5,-100.0+float(i),80001.5])
	var after: Dictionary = domain.metadata().stats
	check("observe does not read/decode perframe",after.file_reads == before.file_reads and after.json_decodes == before.json_decodes and after.queries == before.queries+1000)
	var exposed: Dictionary = domain.metadata()
	exposed.identity.bindings.snapshot_manifest_sha256 = "changed"
	var descriptors: Array = domain.provider_descriptors()
	descriptors[0].provider_id = "changed"
	check("metadata/provider descriptions are detached",domain.metadata().identity.bindings.snapshot_manifest_sha256 == "a".repeat(64) and domain.provider_descriptors()[0].provider_id != "changed")
	check("live identity cannotbe replaced",not domain.configure(fixture.base,fixture.identity_sha,"a".repeat(64)))
	check("wrong expected snapshot is refused",not Domain.new().configure(fixture.base,fixture.identity_sha,"b".repeat(64)))
	check("wrong trusted identity hash is refused",not Domain.new().configure(fixture.base,"0".repeat(64),"a".repeat(64)))
	var corrupted: Dictionary = _fixture("corrupt-data")
	_write(corrupted.base.path_join("domain.json"),"{}")
	check("data corruption is refused",not Domain.new().configure(corrupted.base,corrupted.identity_sha,"a".repeat(64)))
	var bad_frame: Dictionary = _fixture("bad-frame")
	bad_frame.data.georeference.origin_easting = true
	_seal(bad_frame)
	check("boolframe value is rejected without mixedtype comparison",not Domain.new().configure(bad_frame.base,bad_frame.identity_sha,"a".repeat(64)))
	var bad_count: Dictionary = _fixture("bad-count")
	bad_count.data.counts.territory.vertices = "lots"
	_seal(bad_count)
	check("typed inventory mismatch is refused",not Domain.new().configure(bad_count.base,bad_count.identity_sha,"a".repeat(64)))
	var bad_semantics: Dictionary = _fixture("bad-semantics")
	bad_semantics.data.semantic_contract.territory_is_land = true
	_seal(bad_semantics)
	check("territory cannotbe promoted into land authority",not Domain.new().configure(bad_semantics.base,bad_semantics.identity_sha,"a".repeat(64)))
	var bad_registry: Dictionary = _fixture("bad-registry")
	bad_registry.identity.provider_descriptors[0].kind = "physics"
	var changed_identity: String = JSON.stringify(bad_registry.identity)
	_write(bad_registry.base.path_join("identity.json"),changed_identity)
	check("resealed wrong provider registry is refused",not Domain.new().configure(bad_registry.base,_sha(changed_identity.to_utf8_buffer()),"a".repeat(64)))
	var bad_path: Dictionary = _fixture("bad-path")
	bad_path.identity.dataset.file = "../domain.json"
	changed_identity = JSON.stringify(bad_path.identity)
	_write(bad_path.base.path_join("identity.json"),changed_identity)
	check("descriptor path traversal is refused",not Domain.new().configure(bad_path.base,_sha(changed_identity.to_utf8_buffer()),"a".repeat(64)))
	_context_composition(domain)
	_actual()
	_finish()

func _context_composition(domain: RefCounted) -> void:
	var frame := Frame.new()
	var context := Context.new()
	var profile := {"profile_id":"synthetic/domain-data-only","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0,.9,0],"min_support_normal_y":.7,"max_support_drop_m":.3,"max_support_rise_m":.1,"max_support_lateral_m":.5}
	var configured: bool = frame.configure(Domain.FRAME,[80000,0,80000],"a".repeat(64),{"status":"unknown","reference":"UNRESOLVED"})
	configured = configured and context.configure(frame,"b".repeat(64),"c".repeat(64),profile,null)
	for row: Dictionary in domain.provider_descriptors(): configured = configured and context.register_provider(row.kind,row.provider_id,row.source_reference)
	if not check("versioned descriptors register with actual context",configured): return
	var begun: Dictionary = context.begin_query([80001.5,-100,80001.5])
	if not check("data context query begins",begun.get("ok",false),str(begun)): return
	var rows: Dictionary = domain.observe(begun.query.source_xyz)
	var observations: Dictionary = {}
	for kind: String in ["territory","land","water"]:
		var bound: Dictionary = context.bind_observation(begun.query,kind,rows[kind].state,rows[kind].payload)
		if check("fresh domain row binds "+kind,bound.get("ok",false),str(bound)): observations[kind] = bound.observation
	var state: Dictionary = context.evaluate(begun.query,observations)
	check("context retains unknown water/residency/support",state.get("ok",false) and state.territory.state == "inside" and state.water.state == "unknown" and state.residency.state == "unknown" and state.support.state == "unknown",str(state))

func _actual() -> void:
	var domain := Domain.new()
	if not check("actual pinned national domain configures",domain.configure(ACTUAL_DIR,ACTUAL_IDENTITY,SNAPSHOT),domain.last_error): return
	for point: Array in [[500.0,-20.0,-1000.0],[500.0,5000.0,-1000.0]]:
		var row: Dictionary = domain.observe(point)
		check("actual MBSsource coverage preservesYindependent unknowns",row.ok and row.territory.state == "inside" and row.diagnostics.coast_enclosure_relation == "inside" and row.land.state == "unknown" and row.water.state == "unknown",str(row))
	check("actual distant coordinate is outside administrative coverage",domain.observe([1000000.0,0.0,1000000.0]).territory.state == "outside")
	var started: int = Time.get_ticks_usec()
	for i in 200: domain.observe([500.0,float(i),-1000.0])
	metrics["actual200queries_us"] = Time.get_ticks_usec()-started
	metrics["actual_domain_metadata"] = domain.metadata()
	metrics["scope"] = "Data-only exact-source XY classification and context rows; no actor, terrain, inland hydrology, dry volume, water level, streaming, rendering or performance acceptance"

func _finish() -> void:
	if finished: return
	finished = true
	var report := {"checks":checks,"failures":failures,"metrics":metrics,"scope":"Source-domain adapter only; full Singapore/MBS migration remains root work"}
	_write(qa.path_join("report.json"),JSON.stringify(report,"\t"))
	print("[source-domain] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
