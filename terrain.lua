local C = ColGen.cfg
local perlin2 = ColGen.perlin2
local smoothstep = ColGen.smoothstep

local geometryCache = {}
local geometryKeys = {}
local GEOMETRY_CACHE_LIMIT = (2 * C.CACHE_RADIUS_MAX + 1) ^ 2

local function fbm(x, y, octaves, scale)
	local total, amp, freq, sum = 0, 1, scale, 0
	for _ = 1, octaves do
		sum = sum + amp * perlin2(x * freq, y * freq)
		total = total + amp
		amp = amp * 0.5
		freq = freq * 2
	end
	return sum / total
end

local function rawHeightAt(x, y)
	local wx = x + C.WARP_AMOUNT * perlin2(x * C.WARP_SCALE + 811, y * C.WARP_SCALE + 233)
	local wy = y + C.WARP_AMOUNT * perlin2(x * C.WARP_SCALE + 457, y * C.WARP_SCALE + 619)
	local base = C.BASE_HEIGHT * fbm(wx, wy, C.BASE_OCTAVES, C.BASE_SCALE)
	local hills = C.HILL_HEIGHT * fbm(wx, wy, 2, C.HILL_SCALE)
	local ravineNoise = math.abs(perlin2(wx * C.RAVINE_SCALE + 37, wy * C.RAVINE_SCALE + 91))
	local ravineMask = math.max(0, 1 - ravineNoise / C.RAVINE_WIDTH)
	ravineMask = ravineMask * smoothstep(C.RAVINE_MASK_LOW, C.RAVINE_MASK_HIGH, fbm(x, y, 2, C.RAVINE_MASK_SCALE))
	return base + hills - C.RAVINE_DEPTH * ravineMask, ravineMask
end

local function heightAt(x, y)
	local h, ravine = rawHeightAt(x, y)
	return ColGen.applyRoad(x, y, h), ravine
end

local function layerWeights(z, ravine)
	local sand = smoothstep(C.SAND_RAVINE - C.BLEND_RAVINE, C.SAND_RAVINE + C.BLEND_RAVINE, ravine)
	return 0, 0, sand
end

local function buildChunk(cx, cy)
	local half = C.CHUNK_SIZE / 2
	local centerX = cx * C.CHUNK_SIZE + half
	local centerY = cy * C.CHUNK_SIZE + half
	local cells = C.CHUNK_CELLS
	local stride = cells + 1
	local verts, points = {}, {}
	for j = 0, cells do
		for i = 0, cells do
			local lx = i * C.CELL - half
			local ly = j * C.CELL - half
			local lz, ravine = heightAt(cx * C.CHUNK_SIZE + i * C.CELL, cy * C.CHUNK_SIZE + j * C.CELL)
			verts[#verts + 1] = {lx, ly, lz}
			points[#points + 1] = {centerX + lx, centerY + ly, C.BASE_Z + lz, ravine}
		end
		ColGen.yieldIfOver()
	end
	local faces = {}
	for j = 0, cells - 1 do
		for i = 0, cells - 1 do
			local a = j * stride + i + 1
			local b = a + 1
			local c = a + stride
			local d = c + 1
			faces[#faces + 1] = {a, b, d}
			faces[#faces + 1] = {a, d, c}
		end
	end
	return verts, faces, points, stride, centerX, centerY
end

function ColGen.getGeometry(cx, cy)
	local key = cx .. ":" .. cy
	local cached = geometryCache[key]
	if not cached then
		cached = {buildChunk(cx, cy)}
		geometryCache[key] = cached
		geometryKeys[#geometryKeys + 1] = key
		if #geometryKeys > GEOMETRY_CACHE_LIMIT then
			geometryCache[table.remove(geometryKeys, 1)] = nil
		end
	end
	return unpack(cached)
end

ColGen.rawHeightAt = rawHeightAt
ColGen.heightAt = heightAt
ColGen.layerWeights = layerWeights
