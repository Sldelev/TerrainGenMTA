local C = ColGen.cfg
local S = ColGen.state
local heightAt = ColGen.heightAt

local function channel(v)
	return math.floor(v * 255 + 0.5)
end

local function emitVertex(list, p, shade, u, v)
	local stone, snow, sand = ColGen.layerWeights(p[3], p[4])
	list[#list + 1] = {p[1], p[2], p[3], tocolor(channel(stone), channel(snow), channel(sand), shade), u, v}
end

local function emitTriangle(list, p1, p2, p3, light, skirt)
	local shade = ColGen.faceShade(p1, p2, p3, light)
	for _, p in ipairs({p1, p2, p3}) do
		if skirt then
			emitVertex(list, p, shade, (p[1] + p[2]) / C.TEXTURE_TILE, p[3] / C.TEXTURE_TILE)
		else
			emitVertex(list, p, shade, p[1] / C.TEXTURE_TILE, p[2] / C.TEXTURE_TILE)
		end
	end
end

local function buildVertices(points, faces, light)
	local list = {}
	for _, f in ipairs(faces) do
		emitTriangle(list, points[f[1]], points[f[2]], points[f[3]], light, false)
	end
	return list
end

local function buildFarVertices(cx, cy, light)
	local n = C.CHUNK_CELLS / C.LOD_FAR_STEP
	local stride = n + 1
	local points = {}
	for j = 0, n do
		for i = 0, n do
			local wx = cx * C.CHUNK_SIZE + i * C.LOD_FAR_STEP * C.CELL
			local wy = cy * C.CHUNK_SIZE + j * C.LOD_FAR_STEP * C.CELL
			local h, ravine = heightAt(wx, wy)
			points[j * stride + i + 1] = {wx, wy, C.BASE_Z + h, ravine}
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
	local list = buildVertices(points, faces, light)

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
		local ad = {a[1], a[2], a[3] - C.SKIRT_DEPTH, a[4]}
		local bd = {b[1], b[2], b[3] - C.SKIRT_DEPTH, b[4]}
		emitTriangle(list, a, b, bd, light, true)
		emitTriangle(list, a, bd, ad, light, true)
	end
	return list
end

function ColGen.getChunkDraw(chunk, lod)
	local draw = chunk.draw[lod]
	if not draw then
		if lod == 1 then
			draw = buildVertices(chunk.points, chunk.faces, S.light)
		else
			draw = buildFarVertices(chunk.cx, chunk.cy, S.light)
		end
		chunk.draw[lod] = draw
	end
	return draw
end
