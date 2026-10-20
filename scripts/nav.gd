class_name Nav
extends RefCounted
## Paths around walls, doorways, furniture, fences and the neighbours'
## houses. The navigation mesh is baked when a night starts
## (scripts/systems/nav_bake.gd); until it is ready, routes fall back to the
## straight lines between waypoints.

static var map := RID()
static var is_baked := false


## Waypoints -> a path that walks around things. Every waypoint is still
## visited (they mark the lane, the door, the chair); the legs between them
## follow the navigation mesh. Heights are flattened to the floor.
static func route(from: Vector3, waypoints: Array) -> Array:
	var out: Array = []
	if not is_baked or not map.is_valid():
		for w in waypoints:
			out.append(Vector3(w.x, 0.0, w.z))
		return out
	var cur := Vector3(from.x, 0.0, from.z)
	for w in waypoints:
		var tgt := Vector3(w.x, 0.0, w.z)
		var pts := NavigationServer3D.map_get_path(map, cur, tgt, true)
		for i in pts.size():
			var q := Vector3(pts[i].x, 0.0, pts[i].z)
			if i == 0 and q.distance_to(cur) < 0.3:
				continue
			if not out.is_empty() and (out[-1] as Vector3).distance_to(q) < 0.05:
				continue
			out.append(q)
		# the last stretch onto a chair or a mark the mesh can't reach
		if out.is_empty() or (out[-1] as Vector3).distance_to(tgt) > 0.05:
			out.append(tgt)
		cur = tgt
	return out


## The closest point people can actually stand on.
static func snap(p: Vector3) -> Vector3:
	if not is_baked or not map.is_valid():
		return p
	var q := NavigationServer3D.map_get_closest_point(map, p)
	return Vector3(q.x, 0.0, q.z)
