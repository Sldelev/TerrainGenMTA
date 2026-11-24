local C = ColGen.cfg

local function u8(v) return string.char(v % 256) end
local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v)
	return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function i16(v)
	return u16(v < 0 and v + 65536 or v)
end
local function f32(x)
	if x == 0 then
		return u32(0)
	end
	local sign = 0
	if x < 0 then
		sign, x = 2147483648, -x
	end
	local m, e = math.frexp(x)
	local mant = math.floor((m * 2 - 1) * 8388608 + 0.5)
	local exp = e + 126
	if mant == 8388608 then
		mant, exp = 0, exp + 1
	end
	return u32(sign + exp * 8388608 + mant)
end

local function computeBounds(verts)
	local mn = {math.huge, math.huge, math.huge}
	local mx = {-math.huge, -math.huge, -math.huge}
	for _, v in ipairs(verts) do
		for k = 1, 3 do
			mn[k] = math.min(mn[k], v[k])
			mx[k] = math.max(mx[k], v[k])
		end
	end
	local center = {(mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, (mn[3] + mx[3]) / 2}
	local radius = 0
	for _, v in ipairs(verts) do
		local dx, dy, dz = v[1] - center[1], v[2] - center[2], v[3] - center[3]
		radius = math.max(radius, math.sqrt(dx * dx + dy * dy + dz * dz))
	end
	return {min = mn, max = mx, center = center, radius = radius}
end

local function makeHeader(modelId, bounds, faceCount, vertexOffset, faceOffset)
	local b = bounds
	local boundsBytes = f32(b.min[1]) .. f32(b.min[2]) .. f32(b.min[3]) .. f32(b.max[1]) .. f32(b.max[2]) .. f32(b.max[3])
		.. f32(b.center[1]) .. f32(b.center[2]) .. f32(b.center[3]) .. f32(b.radius)
	return "terrain" .. string.rep("\0", 15) .. u16(modelId) .. boundsBytes
		.. u16(0) .. u16(0) .. u16(faceCount) .. u8(0) .. u8(0)
		.. u32(0)
		.. u32(0) .. u32(0) .. u32(0) .. u32(vertexOffset) .. u32(faceOffset) .. u32(0)
		.. u32(0) .. u32(0) .. u32(0)
end

local function buildCol(modelId, verts, faces)
	local vertexBytes = {}
	for _, v in ipairs(verts) do
		for k = 1, 3 do
			vertexBytes[#vertexBytes + 1] = i16(math.floor(v[k] * 128 + 0.5))
		end
	end
	local faceBytes = {}
	for fi, f in ipairs(faces) do
		if fi % 64 == 0 then
			ColGen.yieldIfOver()
		end
		faceBytes[#faceBytes + 1] = u16(f[1] - 1) .. u16(f[2] - 1) .. u16(f[3] - 1) .. u8(0) .. u8(0)
	end
	local vertices = table.concat(vertexBytes)
	local faceData = table.concat(faceBytes)
	local bounds = computeBounds(verts)

	local placeholder = makeHeader(modelId, bounds, #faces, 0, 0)
	local bodyStart = 8 + #placeholder
	local vertexOffset = bodyStart - C.OFFSET_BASE
	local faceOffset = bodyStart + #vertices - C.OFFSET_BASE
	local header = makeHeader(modelId, bounds, #faces, vertexOffset, faceOffset)

	return "COL3" .. u32(#header + #vertices + #faceData) .. header .. vertices .. faceData
end

local function withRoads(cx, cy, verts, faces, centerX, centerY, zRef)
	local meshVerts, meshFaces = {}, {}
	for _, v in ipairs(verts) do
		meshVerts[#meshVerts + 1] = {v[1], v[2], v[3] + C.BASE_Z - zRef}
	end
	for _, f in ipairs(faces) do
		meshFaces[#meshFaces + 1] = f
	end

	local road, side = ColGen.getRoadTriangles(cx, cy)
	local list = road
	if C.ROAD_SIDE_COLLISION then
		list = {}
		for _, tri in ipairs(road) do
			list[#list + 1] = tri
		end
		for _, tri in ipairs(side) do
			list[#list + 1] = tri
		end
	end
	local index = {}
	local function vertexIndex(p)
		local x, y, z = p[1] - centerX, p[2] - centerY, p[3] - zRef
		local key = ((math.floor(x * 128 + 0.5) + 65536) * 131072 + math.floor(y * 128 + 0.5) + 65536) * 131072 + math.floor(z * 128 + 0.5) + 65536
		local idx = index[key]
		if not idx then
			meshVerts[#meshVerts + 1] = {x, y, z}
			idx = #meshVerts
			index[key] = idx
		end
		return idx
	end
	for ti, tri in ipairs(list) do
		if ti % 64 == 0 then
			ColGen.yieldIfOver()
		end
		local a, b, c = vertexIndex(tri[1]), vertexIndex(tri[2]), vertexIndex(tri[3])
		if a ~= b and b ~= c and a ~= c then
			meshFaces[#meshFaces + 1] = {a, b, c}
		end
	end
	return meshVerts, meshFaces
end

local function colProbeAdd(key, ms)
	ColGen.debugRecord("col " .. key, ms)
end

local function faceStatsAdd(terrain, total, reused)
	if reused then
		ColGen.debugValue("col faces reused", "yes")
		return
	end
	ColGen.debugValue("col faces terrain", terrain)
	ColGen.debugValue("col faces total", total)
end

local pool, poolOrder = {}, {}
local function evictFromPool()
	local key = table.remove(poolOrder, 1)
	local model = pool[key]
	pool[key] = nil
	engineRestoreCOL(model)
	engineFreeModel(model)
end

function ColGen.flushCollisionPool()
	while #poolOrder > 0 do
		evictFromPool()
	end
end

local function requestCollisionModel()
	local held = {}
	local model = engineRequestModel("object")
	while model and model >= C.WHEEL_MODEL_MIN and model <= C.WHEEL_MODEL_MAX do
		held[#held + 1] = model
		model = engineRequestModel("object")
	end
	for _, id in ipairs(held) do
		engineFreeModel(id)
	end
	return model
end

function ColGen.applyVisualBounds(chunk, model)
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local zRef = chunk.centerZ
	local lo, hi = {math.huge, math.huge, math.huge}, {-math.huge, -math.huge, -math.huge}
	for _, p in ipairs(chunk.points) do
		local rel = {p[1] - centerX, p[2] - centerY, p[3] - zRef}
		for k = 1, 3 do
			lo[k] = math.min(lo[k], rel[k])
			hi[k] = math.max(hi[k], rel[k])
		end
	end
	local corners = {}
	for i = 0, 7 do
		corners[#corners + 1] = {
			i % 2 == 0 and lo[1] or hi[1],
			math.floor(i / 2) % 2 == 0 and lo[2] or hi[2],
			math.floor(i / 4) % 2 == 0 and lo[3] or hi[3],
		}
	end
	local fileName = "Models/col/vis_v" .. C.CACHE_VERSION .. "_" .. C.SEED .. "_" .. chunk.cx .. "_" .. chunk.cy .. ".col"
	if not fileExists(fileName) and not ColGen.writeCache(fileName, buildCol(model, corners, {})) then
		return false
	end
	local col = engineLoadCOL(fileName)
	return col ~= nil and engineReplaceCOL(col, model)
end

local function colCacheName(chunk)
	return "Models/col/c_v" .. C.CACHE_VERSION .. "_" .. C.SEED .. "_" .. chunk.cx .. "_" .. chunk.cy .. ".col"
end

local function buildCollisionMesh(chunk)
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local verts, faces = ColGen.getGeometry(chunk.cx, chunk.cy)
	local terrainFaces = #faces
	verts, faces = withRoads(chunk.cx, chunk.cy, verts, faces, centerX, centerY, chunk.centerZ)
	return verts, faces, terrainFaces
end

local function collisionMesh(chunk)
	local m = chunk.colMesh
	if m then
		chunk.colMesh = nil
		return m.verts, m.faces, m.terrainFaces
	end
	return buildCollisionMesh(chunk)
end

function ColGen.prepareCollision(chunk)
	local key = chunk.cx .. ":" .. chunk.cy
	if chunk.colMesh or pool[key] or fileExists(colCacheName(chunk)) then
		return false
	end
	local verts, faces, terrainFaces = buildCollisionMesh(chunk)
	chunk.colMesh = {verts = verts, faces = faces, terrainFaces = terrainFaces}
	return true
end

function ColGen.attachCollision(chunk)
	local key = chunk.cx .. ":" .. chunk.cy
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local zRef = chunk.centerZ
	local model = pool[key]
	if model then
		pool[key] = nil
		for i, k in ipairs(poolOrder) do
			if k == key then
				table.remove(poolOrder, i)
				break
			end
		end
		faceStatsAdd(0, 0, true)
	else
		model = requestCollisionModel()
		if not model then
			return false
		end
		local t0 = getTickCount()
		local fileName = "Models/col/c_v" .. C.CACHE_VERSION .. "_" .. C.SEED .. "_" .. chunk.cx .. "_" .. chunk.cy .. ".col"
		if not fileExists(fileName) then
			local verts, faces, terrainFaces = collisionMesh(chunk)
			local data = buildCol(model, verts, faces)
			colProbeAdd("build", getTickCount() - t0)
			faceStatsAdd(terrainFaces, #faces, false)
			t0 = getTickCount()
			local written = ColGen.writeCache(fileName, data)
			colProbeAdd("write", getTickCount() - t0)
			if not written then
				engineFreeModel(model)
				return false
			end
		else
			faceStatsAdd(0, 0, true)
		end
		t0 = getTickCount()
		local col = engineLoadCOL(fileName)
		colProbeAdd("load", getTickCount() - t0)
		if not col or not engineReplaceCOL(col, model) then
			engineFreeModel(model)
			return false
		end
	end
	local obj = createObject(model, centerX, centerY, zRef)
	setElementFrozen(obj, true)
	setElementAlpha(obj, 0)
	chunk.model = model
	chunk.object = obj
	return true
end

function ColGen.detachCollision(chunk)
	if not chunk.model then
		return
	end
	if isElement(chunk.object) then
		destroyElement(chunk.object)
	end
	local key = chunk.cx .. ":" .. chunk.cy
	pool[key] = chunk.model
	poolOrder[#poolOrder + 1] = key
	chunk.model = nil
	chunk.object = nil
	while #poolOrder > C.COL_POOL_LIMIT do
		evictFromPool()
	end
end
