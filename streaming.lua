local C = ColGen.cfg
local S = ColGen.state

local function createVisual(cx, cy)
	local _, faces, points, stride = ColGen.getGeometry(cx, cy)
	local minZ, maxZ = math.huge, -math.huge
	for _, p in ipairs(points) do
		minZ = math.min(minZ, p[3])
		maxZ = math.max(maxZ, p[3])
	end
	return {
		cx = cx,
		cy = cy,
		points = points,
		faces = faces,
		stride = stride,
		draw = {},
		light = S.light,
		centerZ = (minZ + maxZ) / 2,
	}
end

local function roadCacheName(chunk)
	local bucket = math.floor(S.light * 10 + 0.5)
	return "Models/dff/r_v" .. C.CACHE_VERSION .. "_" .. C.SEED .. "_" .. chunk.cx .. "_" .. chunk.cy .. "_b" .. bucket .. ".dff"
end

local function terrainCacheName(chunk, lod)
	local bucket = math.floor(S.light * 10 + 0.5)
	return "Models/dff/t_v" .. C.CACHE_VERSION .. "_" .. C.SEED .. "_" .. chunk.cx .. "_" .. chunk.cy .. "_l" .. lod .. "_b" .. bucket .. ".dff"
end

local function lodForDistance(dist)
	for k, level in ipairs(C.LOD_LEVELS) do
		if dist <= level.radius then
			return k
		end
	end
end

local function desiredLod(chunk)
	local dist = math.max(math.abs(chunk.cx - S.playerCX), math.abs(chunk.cy - S.playerCY))
	return math.max(lodForDistance(dist), ColGen.flatLod(chunk))
end

local function writeTerrainDff(chunk, lod, fileName)
	if fileExists(fileName) then
		return true
	end
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local data
	if lod == 1 then
		data = ColGen.chunkDff(chunk, centerX, centerY, chunk.centerZ)
	else
		data = ColGen.coarseChunkDff(chunk, C.LOD_LEVELS[lod].step, centerX, centerY, chunk.centerZ)
	end
	return ColGen.writeCache(fileName, data)
end

local function attachVisual(chunk)
	if not S.terrainShader then
		return false
	end
	local model = engineRequestModel("object")
	if not model then
		outputDebugString("TerrainGen: нет свободного ID модели для чанка " .. chunk.cx .. ":" .. chunk.cy)
		return false
	end
	local lod = desiredLod(chunk)
	local fileName = terrainCacheName(chunk, lod)
	if not writeTerrainDff(chunk, lod, fileName) then
		engineFreeModel(model)
		return false
	end
	local dff = engineLoadDFF(fileName)
	local replaced = dff and engineReplaceModel(dff, model)
	if not replaced then
		if dff then
			destroyElement(dff)
		end
		engineFreeModel(model)
		return false
	end
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	ColGen.applyVisualBounds(chunk, model)
	local obj = createObject(model, centerX, centerY, chunk.centerZ)
	setElementFrozen(obj, true)
	setElementCollisionsEnabled(obj, false)
	engineApplyShaderToWorldTexture(S.terrainShader, "*", obj)
	engineSetModelLODDistance(model, 2000)
	chunk.visual = {obj = obj, model = model, dff = dff, lod = lod, light = chunk.light}
	return true
end

local function attachRoadVisual(chunk)
	if not S.roadShader or not ColGen.hasRoadTriangles(chunk.cx, chunk.cy) then
		return false
	end
	local road, side = ColGen.getRoadTriangles(chunk.cx, chunk.cy)
	local all = {}
	for _, tri in ipairs(road) do
		all[#all + 1] = tri
	end
	for _, tri in ipairs(side) do
		all[#all + 1] = tri
	end
	if #all == 0 then
		return false
	end
	local model = engineRequestModel("object")
	if not model then
		return false
	end
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local fileName = roadCacheName(chunk)
	if not fileExists(fileName) then
		chunk.roadDff = chunk.roadDff or ColGen.roadChunkDff(all, centerX, centerY, chunk.centerZ)
		if not ColGen.writeCache(fileName, chunk.roadDff) then
			engineFreeModel(model)
			return false
		end
	end
	local dff = engineLoadDFF(fileName)
	local replaced = dff and engineReplaceModel(dff, model)
	if not replaced then
		if dff then
			destroyElement(dff)
		end
		engineFreeModel(model)
		return false
	end
	ColGen.applyVisualBounds(chunk, model)
	local obj = createObject(model, centerX, centerY, chunk.centerZ)
	setElementFrozen(obj, true)
	setElementCollisionsEnabled(obj, false)
	engineApplyShaderToWorldTexture(S.roadShader, "*", obj)
	engineSetModelLODDistance(model, 2000)
	chunk.road = {obj = obj, model = model, dff = dff}
	return true
end

local function detachRoadVisual(chunk)
	local r = chunk.road
	if not r then
		return
	end
	destroyElement(r.obj)
	engineFreeModel(r.model)
	destroyElement(r.dff)
	chunk.road = nil
end

local function detachVisual(chunk)
	detachRoadVisual(chunk)
	local v = chunk.visual
	if not v then
		return
	end
	destroyElement(v.obj)
	engineFreeModel(v.model)
	destroyElement(v.dff)
	chunk.visual = nil
end

local function perimeterCell(k, r)
	local s = 2 * r
	if k < s then
		return -r + k, -r
	end
	k = k - s
	if k < s then
		return r, -r + k
	end
	k = k - s
	if k < s then
		return r - k, r
	end
	k = k - s
	return -r, r - k
end

local function scanRings(pcx, pcy, visit)
	for r = 0, C.CACHE_RADIUS do
		local len = r == 0 and 1 or 8 * r
		for k = 0, len - 1 do
			local dx, dy = 0, 0
			if r > 0 then
				dx, dy = perimeterCell(k, r)
			end
			visit(pcx + dx, pcy + dy)
		end
	end
end

function ColGen.releaseAll()
	for key, chunk in pairs(S.chunks) do
		ColGen.detachCollision(chunk)
		detachVisual(chunk)
		S.chunks[key] = nil
	end
	ColGen.flushCollisionPool()
end

function ColGen.setDrawDistance(meters)
	local r = math.floor(meters / C.DRAW_DIST_PER_RING)
	C.CACHE_RADIUS = math.max(C.CACHE_RADIUS_MIN, math.min(C.CACHE_RADIUS_MAX, r))
	return C.CACHE_RADIUS
end

local pending = {}

local function spawnKeyed(id, fn, first)
	local co = pending[id]
	if co and coroutine.status(co) ~= "dead" then
		return
	end
	pending[id] = ColGen.spawn(fn, first)
end

local function dropIfReleased(key, chunk)
	if S.chunks[key] == chunk then
		return false
	end
	ColGen.detachCollision(chunk)
	detachVisual(chunk)
	return true
end

local function ringNeedsWork(chunk, cx, cy)
	if not chunk then
		return true
	end
	if not ColGen.hasRoadTriangles(cx, cy) then
		return true
	end
	local v = chunk.visual
	if S.terrainShader and (not v or v.lod ~= desiredLod(chunk) or v.light ~= chunk.light) then
		return true
	end
	return S.roadShader ~= nil and not chunk.road and ColGen.hasRoadTriangles(cx, cy)
end

local function buildRingChunk(cx, cy)
	local key = cx .. ":" .. cy
	local chunk = S.chunks[key]
	if not chunk then
		if math.max(math.abs(cx - S.playerCX), math.abs(cy - S.playerCY)) > C.CACHE_RADIUS then
			return
		end
		chunk = createVisual(cx, cy)
		S.chunks[key] = chunk
	end
	if not ColGen.hasRoadTriangles(cx, cy) then
		if ColGen.warmRoadBlock(cx, cy) then
			return
		end
		ColGen.getRoadTriangles(cx, cy)
	end
	if dropIfReleased(key, chunk) then
		return
	end
	local v = chunk.visual
	if v and (v.lod ~= desiredLod(chunk) or v.light ~= chunk.light) then
		detachVisual(chunk)
	end
	if not chunk.visual then
		attachVisual(chunk)
	end
	if dropIfReleased(key, chunk) then
		return
	end
	if not chunk.road then
		attachRoadVisual(chunk)
	end
	dropIfReleased(key, chunk)
end

local function buildCollisionChunk(key)
	local chunk = S.chunks[key]
	if not chunk or chunk.model then
		return
	end
	ColGen.getRoadTriangles(chunk.cx, chunk.cy)
	if dropIfReleased(key, chunk) then
		return
	end
	ColGen.attachCollision(chunk)
	dropIfReleased(key, chunk)
end

function ColGen.updateChunks()
	ColGen.refreshLight()
	local chunks = S.chunks

	local px, py = getElementPosition(localPlayer)
	local pcx = math.floor(px / C.CHUNK_SIZE)
	local pcy = math.floor(py / C.CHUNK_SIZE)
	S.playerCX, S.playerCY = pcx, pcy

	local centerKey = pcx .. ":" .. pcy
	spawnKeyed("center", function ()
		buildRingChunk(pcx, pcy)
		buildCollisionChunk(centerKey)
	end, true)

	scanRings(pcx, pcy, function (cx, cy)
		local key = cx .. ":" .. cy
		if ringNeedsWork(chunks[key], cx, cy) then
			spawnKeyed("ring:" .. key, function ()
				buildRingChunk(cx, cy)
			end)
		end
	end)

	for key, chunk in pairs(chunks) do
		local ax, ay = math.abs(chunk.cx - pcx), math.abs(chunk.cy - pcy)
		if math.max(ax, ay) > C.CACHE_RADIUS then
			ColGen.detachCollision(chunk)
			detachVisual(chunk)
			chunks[key] = nil
		elseif math.max(ax, ay) > 1 then
			ColGen.detachCollision(chunk)
		end
	end

	local order = {}
	for _, chunk in pairs(chunks) do
		order[#order + 1] = chunk
	end
	table.sort(order, function (a, b)
		return math.max(math.abs(a.cx - pcx), math.abs(a.cy - pcy)) < math.max(math.abs(b.cx - pcx), math.abs(b.cy - pcy))
	end)
	S.chunkOrder = order

	for _, off in ipairs(C.COLLISION_OFFSETS) do
		local key = (pcx + off[1]) .. ":" .. (pcy + off[2])
		local chunk = chunks[key]
		if chunk and not chunk.model then
			spawnKeyed("col:" .. key, function ()
				local t0 = getTickCount()
				buildCollisionChunk(key)
				ColGen.debugRecord("collision attach", getTickCount() - t0)
			end)
		end
	end
end
