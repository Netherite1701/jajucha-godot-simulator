class_name CourseData
extends RefCounted

const TILE_SIZE: float = 0.9
const PANEL_THICKNESS: float = 0.003
const ROWS_FROM_TOP: Array[String] = [
	"GAAAFFNPPQ.",
	"A.....QPPO.",
	"ALBK.....JI",
	"CDJK......B",
	"DDJK......A",
	"JJ.HDDAMAAM",
]

# Counterclockwise quarter-turns for each occupied panel as it appears in the
# manual's assembly map. Empty cells use 0. Keeping rotation per cell lets one
# clean texture per panel type produce the road orientation shown in the plan.
const ROTATIONS_FROM_TOP: Array[String] = [
	"00000000000",
	"10000022200",
	"10000000000",
	"00330000003",
	"20000000003",
	"01003320223",
]

const TILE_NAMES: Array[String] = [
	"A", "B", "C", "D", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q",
]

const INVENTORY_TILE_COUNTS := {
	"A": 9, "B": 2, "C": 1, "D": 5, "F": 2, "G": 1, "H": 1, "I": 1,
	"J": 5, "K": 3, "L": 1, "M": 2, "N": 1, "O": 1, "P": 4, "Q": 2,
}

const BOARD_COLUMNS: int = 11
const BOARD_ROWS: int = 6
const BOARD_SIZE_METERS := Vector2(9.9, 5.4)


static func panel_atlas_rows() -> Dictionary:
	var atlas := {}
	for row_index in ROWS_FROM_TOP.size():
		var row: String = ROWS_FROM_TOP[row_index]
		for column_index in BOARD_COLUMNS:
			var letter: String = row.substr(column_index, 1)
			if letter != ".":
				if not atlas.has(letter):
					atlas[letter] = []
				atlas[letter].append(Vector2i(column_index, row_index))
	return atlas


static func build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var atlas := panel_atlas_rows()
	for letter in TILE_NAMES:
		var tile_id: int = TILE_NAMES.find(letter)
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(TILE_SIZE, TILE_SIZE)
		mesh.orientation = PlaneMesh.FACE_Y
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/panels/%s.png" % letter) as Texture2D
		material.roughness = 1.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material = material
		library.create_item(tile_id)
		library.set_item_name(tile_id, "Panel %s (900 x 900 mm)" % letter)
		library.set_item_mesh(tile_id, mesh)
		# Panel artwork sits at y=0.000 and the collision slab below it has a
		# top face at y=0; the chassis travels on the drawing surface.
		var shape := BoxShape3D.new()
		shape.size = Vector3(TILE_SIZE, PANEL_THICKNESS, TILE_SIZE)
		library.set_item_shapes(tile_id, [shape, Transform3D(Basis.IDENTITY, Vector3(0, -PANEL_THICKNESS * 0.5, 0))])
	return library


static func fill_grid(grid: GridMap) -> void:
	grid.clear()
	grid.cell_size = Vector3(TILE_SIZE, PANEL_THICKNESS, TILE_SIZE)
	grid.cell_center_x = true
	grid.cell_center_y = false
	grid.cell_center_z = true
	grid.collision_layer = 1
	grid.collision_mask = 0
	var letter_to_id: Dictionary = {}
	var orientation_grid := GridMap.new()
	for tile_id in TILE_NAMES.size():
		letter_to_id[TILE_NAMES[tile_id]] = tile_id
	for row_index in ROWS_FROM_TOP.size():
		var row: String = ROWS_FROM_TOP[row_index]
		var rotations: String = ROTATIONS_FROM_TOP[row_index]
		for column_index in BOARD_COLUMNS:
			var letter: String = row.substr(column_index, 1)
			if letter == ".":
				continue
			var x: int = column_index
			var z: int = row_index
			var quarter_turns := int(rotations.substr(column_index, 1))
			var angle := float(quarter_turns) * PI * 0.5
			var basis := Basis(Vector3.UP, angle)
			var orientation := orientation_grid.get_orthogonal_index_from_basis(basis)
			grid.set_cell_item(Vector3i(x, 0, z), int(letter_to_id[letter]), orientation)

