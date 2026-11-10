ColGen = {}

ColGen.cfg = {
	SEED = 1337,
	OFFSET_BASE = 4,
	CELL = 8,
	CHUNK_CELLS = 4,
	CHUNK_SIZE = 32,
	BASE_Z = 500,
	CACHE_RADIUS = 4,
	VISUAL_PER_TICK = 2,
	COLLISION_PER_TICK = 1,
	STREAM_INTERVAL = 100,
	COLLISION_OFFSETS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}},

	GRID_COLOR = tocolor(0, 255, 120, 200),
	TEXTURE_PATHS = {
		grass = "Assets/Textures/Grass.png",
		sand = "Assets/Textures/sand.png",
		stone = "Assets/Textures/rock.png",
		snow = "Assets/Textures/snow.png",
	},
	TEXTURE_TILE = 8,

	SUN = {0.5, 0.35, 0.8},
	AMBIENT = 0.45,
	DIFFUSE_STRENGTH = 0.55,
	NIGHT_LIGHT = 0.2,
	LIGHT_EPSILON = 0.02,

	WARP_SCALE = 1 / 180,
	WARP_AMOUNT = 70,
	BASE_SCALE = 1 / 90,
	BASE_OCTAVES = 4,
	BASE_HEIGHT = 10,
	HILL_SCALE = 1 / 260,
	HILL_HEIGHT = 35,
	MOUNTAIN_MASK_SCALE = 1 / 350,
	MOUNTAIN_MASK_LOW = -0.05,
	MOUNTAIN_MASK_HIGH = 0.25,
	RIDGE_SCALE = 1 / 140,
	RIDGE_OCTAVES = 4,
	MOUNTAIN_HEIGHT = 150,
	RAVINE_SCALE = 1 / 150,
	RAVINE_WIDTH = 0.1,
	RAVINE_DEPTH = 14,

	SAND_RAVINE = 0.3,
	BLEND_RAVINE = 0.1,
	STONE_HEIGHT = 30,
	SNOW_HEIGHT = 75,
	BLEND_HEIGHT = 10,

	LOD_NEAR_RADIUS = 2,
	LOD_FAR_STEP = 2,
	SKIRT_DEPTH = 12,

	CULL_RADIUS = 32 * math.sqrt(0.5) + 60,
	CULL_HALF_ANGLE = math.rad(75),
}

ColGen.state = {
	light = 1,
	chunks = {},
	gridVisible = false,
	playerCX = 0,
	playerCY = 0,
	terrainShader = nil,
	terrainTextures = {},
}
