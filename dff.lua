local DFF_VERSION = 0x1803FFFF
local ID_STRUCT, ID_STRING, ID_EXTENSION = 0x01, 0x02, 0x03
local ID_TEXTURE, ID_MATERIAL, ID_MATERIAL_LIST = 0x06, 0x07, 0x08
local TEXTURE_NAME = "terrain_tex"
local ID_GEOMETRY, ID_CLUMP, ID_ATOMIC = 0x0F, 0x10, 0x14
local ID_FRAME_LIST, ID_GEOMETRY_LIST = 0x0E, 0x1A
local ID_BIN_MESH = 0x050E
local ID_FRAME_NAME = 0x253F2FE
local NONE = 4294967295
local GEOMETRY_FLAGS = 0x1002F

local function u32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function f32(x)
	if x == 0 then
		return u32(0)
	end
	local signBit = 0
	if x < 0 then
		signBit = 2147483648
		x = -x
	end
	local m, e = math.frexp(x)
	local exp = e + 126
	local frac = math.floor((m * 2 - 1) * 8388608 + 0.5)
	if frac >= 8388608 then
		frac = 0
		exp = exp + 1
	end
	if exp <= 0 then
		return u32(0)
	end
	if exp >= 255 then
		return u32(signBit + 2139095039)
	end
	return u32(signBit + exp * 8388608 + frac)
end

local function chunk(id, body)
	return u32(id) .. u32(#body) .. u32(DFF_VERSION) .. body
end

local function nameChunk(name)
	local len = #name + 1
	local padded = len + (4 - len % 4) % 4
	return chunk(ID_STRING, name .. string.rep("\0", padded - #name))
end

local function u16(n)
	return string.char(n % 256, math.floor(n / 256) % 256)
end

local function emptyExtension()
	return chunk(ID_EXTENSION, "")
end

local function textureChunk()
	return chunk(ID_TEXTURE, chunk(ID_STRUCT, u32(0x1102)) .. nameChunk(TEXTURE_NAME) .. nameChunk("") .. emptyExtension())
end

local function materialChunk(textured)
	local st = u32(0) .. string.char(255, 255, 255, 255) .. u32(0) .. u32(textured and 1 or 0) .. f32(1) .. f32(0) .. f32(1)
	return chunk(ID_MATERIAL, chunk(ID_STRUCT, st) .. (textured and textureChunk() or "") .. emptyExtension())
end

local function materialListChunk(textured)
	return chunk(ID_MATERIAL_LIST, chunk(ID_STRUCT, u32(1) .. u32(NONE)) .. materialChunk(textured))
end

local function sphereRadius(vs)
	local r = 0
	for _, v in ipairs(vs) do
		r = math.max(r, math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
	end
	return r
end

local function frameChunk()
	local identity = f32(1) .. f32(0) .. f32(0) .. f32(0) .. f32(1) .. f32(0) .. f32(0) .. f32(0) .. f32(1)
	local frame = identity .. f32(0) .. f32(0) .. f32(0) .. u32(NONE) .. u32(0)
	return chunk(ID_FRAME_LIST, chunk(ID_STRUCT, u32(1) .. frame) .. chunk(ID_EXTENSION, chunk(ID_FRAME_NAME, "GAP")))
end

local function binMeshChunk(numIndices)
	local parts = {u32(0), u32(1), u32(numIndices), u32(numIndices), u32(0)}
	for i = 0, numIndices - 1 do
		parts[#parts + 1] = u32(i)
	end
	return chunk(ID_BIN_MESH, table.concat(parts))
end

local function geometryChunk(vs, tris)
	local colors, uvs, positions, faceData = {}, {}, {}, {}
	for i, v in ipairs(vs) do
		colors[i] = string.char(v.r, v.g, v.b, v.a)
		uvs[i] = f32(v.u) .. f32(v.v)
		positions[i] = f32(v.x) .. f32(v.y) .. f32(v.z)
	end
	for i, t in ipairs(tris) do
		faceData[i] = u16(t[2]) .. u16(t[1]) .. u16(0) .. u16(t[3])
	end
	local struct = u32(GEOMETRY_FLAGS) .. u32(#tris) .. u32(#vs) .. u32(1)
		.. table.concat(colors) .. table.concat(uvs) .. table.concat(faceData)
		.. f32(0) .. f32(0) .. f32(0) .. f32(sphereRadius(vs)) .. u32(1) .. u32(0)
		.. table.concat(positions)
	return chunk(ID_GEOMETRY, chunk(ID_STRUCT, struct) .. materialListChunk(true) .. chunk(ID_EXTENSION, binMeshChunk(#tris * 3)))
end

local function geometryListChunk(geometry)
	return chunk(ID_GEOMETRY_LIST, chunk(ID_STRUCT, u32(1)) .. geometry)
end

local function atomicChunk()
	local rightToRender = chunk(0x1F, u32(0x0) .. u32(0x0))
	return chunk(ID_ATOMIC, chunk(ID_STRUCT, u32(0) .. u32(0) .. u32(5) .. u32(0)) .. chunk(ID_EXTENSION, rightToRender))
end

local function clumpChunk(geometry)
	local body = chunk(ID_STRUCT, u32(1) .. u32(0) .. u32(0)) .. frameChunk() .. geometryListChunk(geometry) .. atomicChunk() .. emptyExtension()
	return chunk(ID_CLUMP, body)
end

local function channel(v)
	return math.floor(v * 255 + 0.5)
end

function ColGen.writeCache(fileName, data)
	local tmp = fileName .. ".tmp"
	local file = fileCreate(tmp)
	if not file then
		return false
	end
	fileWrite(file, data)
	fileClose(file)
	return fileRename(tmp, fileName)
end

function ColGen.chunkDff(chunk, centerX, centerY, zRef)
	local tile = ColGen.cfg.TEXTURE_TILE
	local light = ColGen.state.light
	local vs, tris = {}, {}
	for fi, f in ipairs(chunk.faces) do
		if fi % 16 == 0 then
			ColGen.yieldIfOver()
		end
		local a, b, c = chunk.points[f[1]], chunk.points[f[2]], chunk.points[f[3]]
		local shade = ColGen.faceShade(a, b, c, light)
		local base = #vs
		for _, p in ipairs({a, b, c}) do
			local stone, snow, sand = ColGen.layerWeights(p[3], p[4])
			vs[#vs + 1] = {
				x = p[1] - centerX, y = p[2] - centerY, z = p[3] - zRef,
				r = channel(stone), g = channel(snow), b = channel(sand), a = shade,
				u = p[1] / tile, v = p[2] / tile,
			}
		end
		tris[#tris + 1] = {base, base + 1, base + 2}
	end
	return clumpChunk(geometryChunk(vs, tris))
end

function ColGen.coarseChunkDff(chunk, step, centerX, centerY, zRef)
	local n = ColGen.cfg.CHUNK_CELLS / step
	local stride = n + 1
	local tile = ColGen.cfg.TEXTURE_TILE
	local light = ColGen.state.light
	local points = {}
	for j = 0, n do
		for i = 0, n do
			local p = chunk.points[(j * step) * chunk.stride + i * step + 1]
			points[j * stride + i + 1] = p
		end
	end
	local faces = {}
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local a = j * stride + i + 1
			local b, c = a + 1, a + stride
			local d = c + 1
			faces[#faces + 1] = {a, b, d}
			faces[#faces + 1] = {a, d, c}
		end
	end
	local vs, tris = {}, {}
	local function emit(a, b, c, skirt)
		local shade = ColGen.faceShade(a, b, c, light)
		local base = #vs
		for _, p in ipairs({a, b, c}) do
			local stone, snow, sand = ColGen.layerWeights(p[3], p[4])
			local u, v
			if skirt then
				u, v = (p[1] + p[2]) / tile, p[3] / tile
			else
				u, v = p[1] / tile, p[2] / tile
			end
			vs[#vs + 1] = {
				x = p[1] - centerX, y = p[2] - centerY, z = p[3] - zRef,
				r = channel(stone), g = channel(snow), b = channel(sand), a = shade,
				u = u, v = v,
			}
		end
		tris[#tris + 1] = {base, base + 1, base + 2}
	end
	for fi, f in ipairs(faces) do
		if fi % 16 == 0 then
			ColGen.yieldIfOver()
		end
		emit(points[f[1]], points[f[2]], points[f[3]], false)
	end
	local depth = ColGen.cfg.SKIRT_DEPTH
	local ring = {}
	for i = n, 0, -1 do
		ring[#ring + 1] = i + 1
	end
	for j = 1, n do
		ring[#ring + 1] = j * stride + 1
	end
	for i = 1, n do
		ring[#ring + 1] = n * stride + i + 1
	end
	for j = n - 1, 1, -1 do
		ring[#ring + 1] = j * stride + n + 1
	end
	local m = #ring
	for k = 1, m do
		local a = points[ring[k]]
		local b = points[ring[k % m + 1]]
		local ad = {a[1], a[2], a[3] - depth, a[4]}
		local bd = {b[1], b[2], b[3] - depth, b[4]}
		emit(a, b, bd, true)
		emit(a, bd, ad, true)
	end
	return clumpChunk(geometryChunk(vs, tris))
end

function ColGen.roadChunkDff(road, centerX, centerY, zRef)
	local vs, tris = {}, {}
	for ti, tri in ipairs(road) do
		if ti % 16 == 0 then
			ColGen.yieldIfOver()
		end
		local shade = ColGen.faceShade(tri[1], tri[2], tri[3], ColGen.state.light)
		local base = #vs
		for k = 1, 3 do
			local p = tri[k]
			vs[#vs + 1] = {
				x = p[1] - centerX, y = p[2] - centerY, z = p[3] - zRef,
				r = channel(p[6]), g = 255, b = 255, a = shade,
				u = p[4], v = p[5],
			}
		end
		tris[#tris + 1] = {base, base + 1, base + 2}
	end
	return clumpChunk(geometryChunk(vs, tris))
end
