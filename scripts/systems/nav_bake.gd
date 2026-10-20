extends Node
## Bakes the navigation mesh for the house, the yard and the lane when a
## night starts, so guests (and worse things) walk around walls and
## furniture instead of through them. See scripts/nav.gd.

const SOURCES := ["House", "Floor", "Trim", "CoffinRoom", "Hall", "Bedroom", "Outside/Ground",
	"Outside/Fence", "Outside/Lamppost", "church", "shrek-house", "houses"]
const AREA := AABB(Vector3(-4.0, -0.5, -24.0), Vector3(52.0, 3.5, 50.0))
const GROUP := "nav_source"

var region: NavigationRegion3D
var navmesh: NavigationMesh


func _ready() -> void:
	add_to_group("debug")
	Nav.is_baked = false
	var level := get_node("../../Level") as Node3D
	for path in SOURCES:
		var n := level.get_node_or_null(path)
		if n:
			n.add_to_group(GROUP)
	for n in level.get_children():
		if String(n.name).begins_with("tree"):
			n.add_to_group(GROUP)
	navmesh = NavigationMesh.new()
	navmesh.cell_size = 0.1
	navmesh.cell_height = 0.05
	navmesh.agent_radius = 0.28
	navmesh.agent_height = 1.6
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 40.0
	navmesh.region_min_size = 4.0
	navmesh.filter_baking_aabb = AREA
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = GROUP
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, src, level)
	# the ground outside comes from the terrain plugin, which the parser can't
	# read: lay a flat floor under everything instead
	var a := AREA.position
	var b := AREA.end
	src.add_faces(PackedVector3Array([
		Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, a.z), Vector3(b.x, 0.0, b.z),
		Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z), Vector3(a.x, 0.0, b.z)]), Transform3D.IDENTITY)
	region = NavigationRegion3D.new()
	region.name = "NavRegion"
	level.add_child(region)
	var m := level.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(m, navmesh.cell_size)
	NavigationServer3D.map_set_cell_height(m, navmesh.cell_height)
	NavigationServer3D.bake_from_source_geometry_data_async(navmesh, src, _baked.bind(m))


func _baked(m: RID) -> void:
	if not is_instance_valid(region):
		return
	region.navigation_mesh = navmesh
	Nav.map = m
	# the map takes the region in a few syncs later; wait until it answers
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(region):
			return
		if NavigationServer3D.map_get_closest_point(m, Vector3(10, 0, 5)) != Vector3.ZERO:
			Nav.is_baked = navmesh.get_polygon_count() > 0
			return


func _exit_tree() -> void:
	Nav.is_baked = false


func debug_line() -> String:
	return "nav %s polys %d" % ["ready" if Nav.is_baked else "baking", navmesh.get_polygon_count() if navmesh else 0]
