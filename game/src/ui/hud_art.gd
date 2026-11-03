extends RefCounted
## Built-in image-generated production textures; region metadata never edits pixels.
const ROOT := "res://assets/ui/generated/"
static var _regions: Dictionary = {}
static var _textures: Dictionary = {}
static func texture(key: String) -> Texture2D:
	if _textures.has(key): return _textures[key]
	if _regions.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"regions.json"))
		if parsed is Dictionary: _regions=parsed
	if not _regions.has(key): return null
	var row: Dictionary=_regions[key]
	var atlas:=AtlasTexture.new()
	atlas.atlas=load(ROOT+String(row.file)) as Texture2D
	var r: Array=row.rect
	atlas.region=Rect2(r[0],r[1],r[2],r[3])
	atlas.filter_clip=true
	_textures[key]=atlas
	return atlas
static func style(key: String, tint: Color=Color.WHITE) -> StyleBoxTexture:
	var box:=StyleBoxTexture.new();box.texture=texture(key)
	box.texture_margin_left=22;box.texture_margin_right=22
	box.texture_margin_top=22;box.texture_margin_bottom=22
	box.content_margin_left=18;box.content_margin_right=18
	box.content_margin_top=12;box.content_margin_bottom=12
	box.modulate_color=tint
	return box
static func fit(item: Texture2D, area: Rect2) -> Rect2:
	var extent:=item.get_size()
	var scale:=minf(area.size.x/extent.x,area.size.y/extent.y)
	var result:=extent*scale
	return Rect2(area.position+(area.size-result)*.5,result)
