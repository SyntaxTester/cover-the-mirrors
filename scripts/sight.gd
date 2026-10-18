class_name Sight
extends RefCounted
## "Is the player looking at this?" — used by doubles (they only move when
## unseen) and by the event director (apparitions vanish when looked at).

const HALF_FOV_COS := 0.82   # ~35°: roughly the middle of a 70° view


static func camera(n: Node) -> Camera3D:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_viewport().get_camera_3d()


## True when `pos` is inside the player's view, close enough and not behind a wall.
static func sees(n: Node, pos: Vector3, max_dist := -1.0, cos_limit := HALF_FOV_COS) -> bool:
	var cam := camera(n)
	if cam == null:
		return false
	if max_dist < 0.0:
		max_dist = Config.sight_dist
	var to := pos - cam.global_position
	var dist := to.length()
	if dist > max_dist or dist < 0.01:
		return dist < 0.01
	if (-cam.global_basis.z).dot(to / dist) < cos_limit:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, pos, 1)   # walls only
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or cam.global_position.distance_to(hit.position) > dist - 0.35


## Is the player looking straight at it (for "look at it and it's gone").
static func stares_at(n: Node, pos: Vector3, max_dist := 8.0) -> bool:
	return sees(n, pos, max_dist, 0.97)
