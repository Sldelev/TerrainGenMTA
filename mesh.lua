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

local function sampleGrid(x0, y0, n, step)
	local stride = n + 1
	local points = {}
	for j = 0, n do
		for i = 0, n do
			local wx = x0 + i * step
			local wy = y0 + j * step
			local h, ravine = heightAt(wx, wy)
			points[j * stride + i + 1] = {wx, wy, C.BASE_Z + h, ravine}
		end
	end
	return points, stride
end

local function gridFaces(n, stride)
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
	return faces
end

local function emitSkirt(list, points, n, stride, light)
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
end

local function buildFarVertices(cx, cy, light, step)
	local n = C.CHUNK_CELLS / step
	local points, stride = sampleGrid(cx * C.CHUNK_SIZE, cy * C.CHUNK_SIZE, n, step * C.CELL)
	local list = buildVertices(points, gridFaces(n, stride), light)
	emitSkirt(list, points, n, stride, light)
	return list
end

local function coarseError(points, stride, step)
	local worst = 0
	for cj = 0, C.CHUNK_CELLS - step, step do
		for ci = 0, C.CHUNK_CELLS - step, step do
			local a = points[cj * stride + ci + 1][3]
			local b = points[cj * stride + ci + step + 1][3]
			local c = points[(cj + step) * stride + ci + 1][3]
			local d = points[(cj + step) * stride + ci + step + 1][3]
			for j = 0, step do
				for i = 0, step do
					local u, v = i / step, j / step
					local h
					if v <= u then
						h = a + (b - a) * u + (d - b) * v
					else
						h = a + (d - c) * u + (c - a) * v
					end
					worst = math.max(worst, math.abs(points[(cj + j) * stride + ci + i + 1][3] - h))
				end
			end
		end
	end
	return worst
end

function ColGen.flatLod(chunk)
	if not chunk.flatLod then
		local dist = ColGen.roadDistance(chunk.cx, chunk.cy, C.TERRAIN_NEAR_ROAD + C.TERRAIN_FALLOFF)
		local t = math.min(1, math.max(0, (dist - C.TERRAIN_NEAR_ROAD) / C.TERRAIN_FALLOFF))
		local tol = C.TERRAIN_FLAT_TOL + (C.TERRAIN_FAR_TOL - C.TERRAIN_FLAT_TOL) * t
		local best = 1
		for k = 2, #C.LOD_LEVELS do
			if coarseError(chunk.points, chunk.stride, C.LOD_LEVELS[k].step) <= tol then
				best = k
			end
		end
		chunk.flatLod = best
	end
	return chunk.flatLod
end

function ColGen.getChunkDraw(chunk, lod)
	local draw = chunk.draw[lod]
	if not draw then
		local t0 = getTickCount()
		if lod == 1 then
			draw = buildVertices(chunk.points, chunk.faces, S.light)
		else
			draw = buildFarVertices(chunk.cx, chunk.cy, S.light, C.LOD_LEVELS[lod].step)
		end
		ColGen.probeTerrain(getTickCount() - t0)
		chunk.draw[lod] = draw
	end
	return draw
end
