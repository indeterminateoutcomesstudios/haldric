tool
extends Node2D

var YAML = preload("res://addons/godot-yaml/gdyaml.gdns").new()

export (Vector2) var map_size = Vector2(20, 20)
export (bool) var update = true setget set_update

enum DIRECTION { N = 0, NE = 1, SE = 2, S = 3, SW = 4, NW = 5}

const SHADER = preload("res://test/transitions/shaders/transition.shader")

const DIR = {}

var size = Vector2(0,0)

var terrain_table = {}
var decal_table = {}
var mask_table = []

var neighbor_table = [
	# EVEN col, ALL rows
    [
		Vector2(0, -1), # N
		Vector2(+1, -1), # NE
		Vector2(+1,  0), # SE
		Vector2(0, +1), # S
		Vector2(-1,  0), # SW
		Vector2(-1, -1) # NW
	],
	# ODD col, ALL rows
    [
		Vector2(0, -1), # N
		Vector2(+1,  0), # NE
		Vector2(+1, +1), # SE
		Vector2( 0, +1), # S
		Vector2(-1, +1), # SW
		Vector2(-1,  0) # NW
	]]

var terrain

var tiles = {}

var container

func set_update(value):
	if(Engine.is_editor_hint()):
		setup()
	update = value

func _ready():
	setup()

func setup():
	container = $Container

	for child in container.get_children():
			child.free()

	DIR[S] = "s"
	DIR[SW] = "sw"
	DIR[NW] = "nw"
	DIR[N] = "n"
	DIR[NE] = "ne"
	DIR[SE] = "se"

	terrain = TileMap.new()
	terrain.cell_size = Vector2(192, 256)
	terrain.cell_half_offset = TileMap.HALF_OFFSET_Y
	
	randomize()
	
	load_terrain("res://test/transitions/yaml/terrain.yaml")
	load_decals("res://test/transitions/yaml/decals.yaml")
	load_alpha_table()
	
	#load_terrain_dir("res://test/transitions/yaml")
	#load_decal_dir("res://test/transitions/yaml")
	
	generate_map(map_size.x, map_size.y)

func generate_map(width, height):
	size = Vector2(width, height)
	
	for y in range(height):
		var tile_map = add_tile_map()
		for x in range(width):
			var rand = randf()
			var code
			# var rand = randi() % terrain_table.values().size()
			if rand < 0.8:
				code = terrain_table.values()[1].id
			else:
				code = terrain_table.values()[0].id
			var map_id = flatten(x, y)

			tiles[map_id] = {
				terrain_code = code,
				variation = randi() % terrain_table[code].image.size(),
				layer = terrain_table[code].layer,
				map_id = map_id,
				row_id = x
			}

			add_tile(tile_map.tile_set, x, terrain_table[code])
			tile_map.set_cell(x, y, x)
			
	generate_decals()
	load_transitions()

func generate_decals():
	var y = 0
	for map_row in container.get_children():
		var x = 0
		for cell in map_row.get_used_cells():
			var id = flatten(x, y)
			var tile = tiles[id]
			var decals = get_decals(tile.terrain_code)
			# print(decals)
			for decal in decals:
				if randf() < decal.probability:
					var sprite = Sprite.new()
					# sprite.centered = false
					sprite.offset = Vector2(decal.offset.x, decal.offset.z)
					sprite.texture = decal.image
					sprite.position = map_to_world_centered(Vector2(x, y))
					add_child(sprite)
					# print("Decal added at ", sprite.position)
			x += 1
		y += 1

func map_to_world_centered(cell):
	var offset = terrain.cell_size / 2
	return terrain.map_to_world(cell) + offset

func get_decals(terrain_code):
	var decals = []
	for decal in decal_table.values():
		# print(decal.apply_to, " == ", terrain_code)
		if decal.apply_to == terrain_code:
			decals.append(decal)
	return decals

func load_transitions():
	var y = 0
	for map_row in container.get_children():
		var x = 0
		for cell in map_row.get_used_cells():
			var id = flatten(x, y)
			var tile = tiles[id]
			
			var mat = ShaderMaterial.new()
			mat.shader = SHADER
			
			var neighbors = get_neighbors(cell)
			var n = 0
			var chain = 0
			for n_cell in neighbors:
				var n_id = flattenv(n_cell)
				
				if !tiles.has(n_id) or n < chain:
					n += 1
					continue

				var n_tile = tiles[n_id]
				
				if tile.layer >= n_tile.layer:
					n += 1
					continue
				
				var cfg = terrain_table[tiles[n_id].terrain_code]
				# print("[", y, "][", x, "]")
				chain = chain(neighbors, n)
				mat = setup_shader(mat, cfg.image[n_tile.variation], n, chain)
				map_row.tile_set.tile_set_material(tile.row_id, mat)
				n += 1
			x += 1
		y += 1

func chain(neighbors, start):
	var code = tiles[flattenv(neighbors[start])].terrain_code

	for i in range(6):
		var cell = neighbors[(start + i + 1) % 6 ]
		var index = flattenv(cell)
		if !tiles.has(index):
			return i
		elif code != tiles[index].terrain_code:
			return i
	return 5

func setup_shader(mat, image, direction, chain):
	var rand = randi()%2
	mat.set_shader_param(str("tex", direction), image)
	mat.set_shader_param(str("mask", direction), mask_table[rand][direction][chain][1])
	# print(mask_table[rand][direction][chain][0], " on ",  DIR[direction])
	return mat

func load_alpha_table():
	for n in range(3):
		mask_table.append([])
		for i in range(6):
			mask_table[n].append([])
			for j in range(6):
				mask_table[n][i].append([])
				mask_table[n][i][j].append(null)
				mask_table[n][i][j].append(null)
	# print("[", mask_table.size(), "][", mask_table[0].size(), "][", mask_table[0][0].size(), "][", mask_table[0][0][0].size(), "]")
	
	for start in range(6):
		var append = ""
		for follow in range(6):
			if start != DIRECTION.N and follow == 5:
				continue
			if follow > 0:
				append += str("-", DIR[(start+follow)%6])
			else:
				append += DIR[(start+follow)%6]
			mask_table[0][start][follow][0] = append
			mask_table[0][start][follow][1] = load(str("res://test/transitions/images/alpha/Grass_abrupt_", append,".png"))
			mask_table[1][start][follow][0] = append
			mask_table[1][start][follow][1] = load(str("res://test/transitions/images/alpha/Grass_medium_", append,".png"))
			mask_table[2][start][follow][0] = append
			mask_table[2][start][follow][1] = load(str("res://test/transitions/images/alpha/Grass_long_", append,".png"))
			# mask_table[3][start][follow][0] = append
			# mask_table[3][start][follow][1] = load(str("res://test/transitions/images/alpha/Grass_", append,".png"))
			
			# print("[0]", "[", start, "]", "[", follow, "]", mask_table[0][start][follow][0])
			# print("[1]", "[", start, "]", "[", follow, "]", mask_table[1][start][follow][0])

func add_tile(tile_set, index, terrain):
	tile_set.create_tile(index)
	tile_set.tile_set_name(index, terrain.id)
	tile_set.tile_set_texture(index, terrain.image[randi()%terrain.image.size()])

func add_tile_map():
	var map = TileMap.new()
	map.cell_size = Vector2(192, 256)
	map.cell_half_offset = TileMap.HALF_OFFSET_Y
	map.tile_set = TileSet.new()
	container.add_child(map)
	return map

func get_neighbors(cell):
	var neighbors = []
	var parity = int(cell.x) & 1
	for n in neighbor_table[parity]:
		neighbors.append(Vector2(cell.x + n.x, cell.y+n.y))
	return neighbors

######################################################################
######################################################################

func flattenv(cell):
	return int(cell.y * size.x + cell.x)

func flatten(x, y):
	return int(y * size.x + x)

func load_terrain(path):
	var file = load_file(path)
	var config = YAML.parse(file.get_as_text())
	
	for key in config.keys():
		var terrain = config[key]
		terrain_table[key] = terrain
		terrain_table[key].id = key
		var image_array = get_image_array(terrain.image)
		terrain_table[key].image = []
		for i in range(image_array.size()):
			terrain_table[key].image.append(load(image_array[i]))

func load_decals(path):
	var file = load_file(path)
	var config = YAML.parse(file.get_as_text())
	
	for key in config.keys():
		var decal = config[key]
		decal_table[key] = decal
		decal_table[key].id = key
		# print(decal.image)
		decal_table[key].image = load(decal.image)

#func load_masks(path):
#	var file = load_file(path)
#	var config = YAML.parse(file.get_as_text())
#
#	for key in config.keys():
#		var mask = config[key]
#		mask_table[key] = mask
#		mask_table[key].id = key
#		print(mask.image)
#		mask_table[key].image = load(mask.image)

func load_terrain_dir(path):
	var files = []
	files = get_files_in_directory(path, files)
	for file in files:
		var config = YAML.parse(file.data.get_as_text())
		for key in config.keys():
			var terrain = config[key]
			terrain_table[key] = terrain
			terrain_table[key].id = key
			terrain_table[key].layer = terrain.layer
			#print(terrain.image)
			var image_array = get_image_array(terrain.image)
			terrain_table[key].image = []
			for i in range(image_array.size()):
				terrain_table[key].image.append(load(image_array[i]))

func load_file(path):
	var file = File.new()
	if file.open(path, file.READ) != OK:
		# print("File could not be laoded: ", path)
		return null
	return file

func get_image_array(image_string):
	var image_array = []
	var temp = image_string.split("[")
	var front = temp[0]
	var back = temp[1]
	#print("Front: ", front, " Back: ", back)
	temp = back.split("]")
	var list = temp[0]
	var PNG = temp[1]
	#print("List: ", list, " Extention: ", PNG)
	var from_to = list.split("-")
	var from = from_to[0]
	var to = from_to[1]
	#print("From: ", from, " To: ", to)
	for i in range(int(from), int(to)+1, 1):
		var s = str(front, i, PNG)
		image_array.append(s)
		# print(s)
	return image_array

func get_files_in_directory(path, files):
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin(true, true)
	var sub_path
	while true:
		sub_path = dir.get_next()
		if sub_path == "." or sub_path == "..":
			continue
		if sub_path == "":
			break
		if dir.current_is_dir():
			get_files_in_directory(dir.get_current_dir() + "/" + sub_path, files)
		else:
			var file = File.new()
			var file_id = sub_path.split(".")[0]
			# print("load file: ", dir.get_current_dir() + "/" + sub_path)
			if file.open(dir.get_current_dir() + "/" + sub_path, file.READ) == OK:
				files.append({ data = file, id = file_id })
	dir.list_dir_end()
	return files