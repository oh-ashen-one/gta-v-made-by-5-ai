extends Node
## Data-only parent-run native QA; not rendered ground, actors or hydrology.
const Terrain = preload("res://src/world/geography/source_terrain.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const ACTUAL := "res://data/geography/terrain/mapzen-skadi-2026-10-28"
const IDENTITY := "5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841"
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var qa := ""
var finished := false

func check(label: String,ok: bool,detail: String = "") -> bool:
	checks += 1
	print("[source-terrain] %s %s %s" % ["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok
func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _write(path: String,bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
func _seal(fixture: Dictionary) -> void:
	var raw: PackedByteArray = JSON.stringify(fixture.manifest).to_utf8_buffer()
	_write(fixture.base.path_join("manifest.json"),raw)
	var identity := {"schema":Terrain.IDENTITY_SCHEMA,"version":1,"manifest":{"file":"manifest.json","bytes":raw.size(),"sha256":_sha(raw)},
		"snapshot_manifest_sha256":"a".repeat(64),"vertical_reference":Terrain.VERTICAL,"chunk_count":fixture.manifest.chunks.size()}
	var bytes: PackedByteArray = JSON.stringify(identity).to_utf8_buffer()
	_write(fixture.base.path_join("identity.json"),bytes)
	fixture["identity"] = identity
	fixture["identity_sha"] = _sha(bytes)

func _fixture(name: String,void_post: bool = false) -> Dictionary:
	var base: String = qa.path_join(name)
	DirAccess.make_dir_absolute(base)
	var chunks: Array = []
	for tx in [-1,0,1]:
		var stream := StreamPeerBuffer.new()
		stream.big_endian = false
		for rz in 43:
			for cx in 43:
				var x: float = float(tx*40-1+cx)*25.0
				var z: float = float(-1+rz)*25.0
				var height: float = 20.0+x*.125+z*.25
				if void_post and tx == 0 and cx == 21 and rz == 21: height = NAN
				stream.put_float(height)
		var raw: PackedByteArray = stream.data_array
		var filename: String = "%d_0.f32" % tx
		_write(base.path_join(filename),raw)
		chunks.append({"file":filename,"chunk_xz":[tx,0],"bytes":raw.size(),"sha256":_sha(raw),
			"core_global_index_min_xz":[tx*40,0],"stored_global_index_min_xz":[tx*40-1,-1]})
	var manifest := {"schema":Terrain.MANIFEST_SCHEMA,"version":1,"provider_id":"SYNTHETIC/fixture-not-ground","vertical_reference":Terrain.VERTICAL,
		"bindings":{"snapshot_manifest_sha256":"a".repeat(64),"country_wgs84_sha256":"b".repeat(64),"pbf_sha256":"c".repeat(64),"projection_implementation_sha256":"d".repeat(64),"georeference":Domain.FRAME.duplicate(true)},
		"grid":{"spacing_metres":25,"chunk_metres":1000,"cells_per_chunk":40,"core_samples":41,"halo_samples":1,"stored_samples":43,"native_posting_arcseconds":1,
			"encoding":"float32_little_endian_row_z_ascending_column_x_ascending","void_encoding":"canonical float32 NaN","derived_spacing_is_new_measurement_resolution":false},
		"chunks":chunks,"sources":[],"attribution":{"credit":"Synthetic QA; no actual DEM measurement"},"limitations":["Synthetic plane, not terrain or hydrology"]}
	var result := {"base":base,"manifest":manifest}
	_seal(result)
	return result
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
		push_error("Source-terrain QA requires private --qa-session")
		get_tree().quit(2)
		return
	qa = args[at+1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/"+qa.trim_prefix("/tmp/")
	qa = qa.path_join("source-terrain-fixtures")
	if not _owned(qa) or DirAccess.dir_exists_absolute(qa) or FileAccess.file_exists(qa) or DirAccess.make_dir_recursive_absolute(qa) != OK:
		push_error("Source-terrain QA refuses unsafe/existing evidence")
		get_tree().quit(2)
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.ignore_time_scale = true
	add_child(timer)
	timer.timeout.connect(func():
		if not finished:
			check("bounded source-terrain completion",false,"45-second watchdog")
			_finish())
	timer.start(45.0)
	_run.call_deferred()
func _run() -> void:
	var good: Dictionary = _fixture("good")
	var provider := Terrain.new()
	if not check("synthetic explicit terrain configures",provider.configure(good.base,good.identity_sha,"a".repeat(64),1),provider.last_error):
		_finish()
		return
	var sample: Dictionary = provider.sample([100.0,-1000.0,100.0])
	check("known LE binary/bilinear plane height",sample.state == "sampled_dem" and absf(sample.height_m_egm96-57.5)<1e-7,str(sample))
	var length: float = sqrt(1.0+.125*.125+.25*.25)
	check("halo centraldifference normal matches plane",sample.normal_state == "derived_dem" and absf(sample.normal_source_xyz[0]+.125/length)<1e-6 and absf(sample.normal_source_xyz[1]-1.0/length)<1e-6 and absf(sample.normal_source_xyz[2]+.25/length)<1e-6)
	check("source elevation neverclaims currentground/worldY/hydrology",not sample.provenance.world_y_alignment_verified and not sample.provenance.surveyed_ground and not sample.provenance.physical_support and not sample.provenance.hydrology)
	var left: Dictionary = provider.sample([999.999,0.0,123.0])
	var right: Dictionary = provider.sample([1000.001,0.0,123.0])
	check("seam heights continuous without snapping",left.state == "sampled_dem" and right.state == "sampled_dem" and absf((right.height_m_egm96-left.height_m_egm96)-.00025)<1e-6)
	var normals_agree := true
	for axis in 3:
		if absf(left.normal_source_xyz[axis]-right.normal_source_xyz[axis]) > 1e-10: normals_agree = false
	check("seam normals agree from exact shared halo",normals_agree)
	var a: Dictionary = provider.chunk_grid(0,0)
	var b: Dictionary = provider.chunk_grid(1,0)
	var edges_equal := true
	for row in 43:
		if a.heights_egm96_m[row*43+41] != b.heights_egm96_m[row*43+1]: edges_equal = false
	check("shared global edge nodes have identical heights",edges_equal and a.core_global_index_min_xz == [0,0] and b.core_global_index_min_xz == [40,0])
	provider.sample([-500.0,0.0,100.0])
	check("bounded LRU evicts and retainscapacity",provider.metadata().stats.max_cached_chunks <= 1 and provider.metadata().stats.evictions > 0)
	provider.sample([100.0,0.0,100.0])
	var before: Dictionary = provider.metadata().stats
	for i in 200: provider.sample([100.0,float(i),100.0])
	var after: Dictionary = provider.metadata().stats
	check("cached sampling does not rereadtiles",after.file_reads == before.file_reads and after.queries == before.queries+200)
	var grid: Dictionary = provider.chunk_grid(0,0)
	grid.heights_egm96_m[5*43+5] = -999.0
	check("returned grid cannotmutate cachedheight",absf(provider.sample([100.0,0.0,100.0]).height_m_egm96-57.5)<1e-7)
	var absent: Dictionary = provider.sample([5000000.0,0.0,5000000.0])
	check("uncompiled coverage isunknown notzero/outsidecity",absent.ok and absent.state == "unknown" and absent.height_m_egm96 == null)
	for invalid in [Vector3.ZERO,PackedFloat32Array([0,0,0]),[true,0,0],[0,0],[INF,0,0],[NAN,0,0],[1e30,0,0]]:
		check("invalidcanonical input rejected "+str(typeof(invalid)),not provider.sample(invalid).ok)
	check("immutable provider cannot reconfigure",not provider.configure(good.base,good.identity_sha,"a".repeat(64),1))
	check("wrong trusted identity fails",not Terrain.new().configure(good.base,"0".repeat(64),"a".repeat(64)))
	check("wrong snapshot fails",not Terrain.new().configure(good.base,good.identity_sha,"b".repeat(64)))
	var void_fixture: Dictionary = _fixture("void",true)
	var void_provider := Terrain.new()
	check("void fixture configures",void_provider.configure(void_fixture.base,void_fixture.identity_sha,"a".repeat(64)))
	var unknown: Dictionary = void_provider.sample([500.0,0.0,500.0])
	check("NaNvoid neverbecomeszeroground",unknown.ok and unknown.state == "unknown" and unknown.height_m_egm96 == null)
	var partial: Dictionary = void_provider.sample([475.0,0.0,500.0])
	check("validheight withvoidnormal stencil keepsnormalunknown",partial.state == "sampled_dem" and partial.normal_state == "unknown" and partial.normal_source_xyz == null)
	var corrupt: Dictionary = _fixture("corrupt")
	var bad_provider := Terrain.new()
	check("corruptionfixture configures metadata",bad_provider.configure(corrupt.base,corrupt.identity_sha,"a".repeat(64)))
	_write(corrupt.base.path_join("0_0.f32"),PackedByteArray([0,0,0,0]))
	check("corrupttile rejected bysize/hash",not bad_provider.sample([100.0,0.0,100.0]).ok and bad_provider.sample([100.0,0.0,100.0]).state == "unknown")
	var bad_frame: Dictionary = _fixture("bad-frame")
	bad_frame.manifest.bindings.georeference.origin_easting = true
	_seal(bad_frame)
	check("boolframe origin rejected withoutmixedtypecomparison",not Terrain.new().configure(bad_frame.base,bad_frame.identity_sha,"a".repeat(64)))
	var bad_path: Dictionary = _fixture("bad-path")
	bad_path.manifest.chunks[0].file = "../outside.f32"
	_seal(bad_path)
	check("tilepathtraversal refused",not Terrain.new().configure(bad_path.base,bad_path.identity_sha,"a".repeat(64)))
	_actual()
	_finish()
func _actual() -> void:
	var provider := Terrain.new()
	if not check("actual nationalDEM identity configures",provider.configure(ACTUAL,IDENTITY,SNAPSHOT,2),provider.last_error): return
	var sample: Dictionary = provider.sample([500.0,0.0,-1000.0])
	check("actual derivedposting matches independentPython binaryreference",sample.ok and sample.state == "sampled_dem" and absf(sample.height_m_egm96-5.989349365234375)<1e-7,str(sample))
	check("actual DEMdatum explicit andsource notsurveyedfloor",sample.vertical_reference == Terrain.VERTICAL and not sample.provenance.surveyed_ground and not sample.provenance.world_y_alignment_verified)
	var start: int = Time.get_ticks_usec()
	for i in 200: provider.sample([500.0,float(i),-1000.0])
	metrics["actual200queries_us"] = Time.get_ticks_usec()-start
	metrics["actual_sample"] = sample
	metrics["actual_metadata"] = provider.metadata()
	metrics["scope"] = "DEMdata decoding/interpolation/cache/normal only; not current surveyed ground, worldYalignment, terraincollision, MBSL1, hydrology or gameplay/renderperformance"
func _finish() -> void:
	if finished: return
	finished = true
	var report := {"checks":checks,"failures":failures,"metrics":metrics}
	_write(qa.path_join("report.json"),JSON.stringify(report,"\t").to_utf8_buffer())
	print("[source-terrain] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
