local C = ColGen.cfg
local S = ColGen.state
local ROAD_COLLISION_DEBUG_COLOR = tocolor(255, 0, 0, 200)
local frameTris = 0

local function drawChunkGrid(points, stride, step)
	local cells = stride - 1
	for j = 0, cells, step do
		for i = 0, cells, step do
			local a = points[j * stride + i + 1]
			if i + step <= cells then
				local b = points[j * stride + i + step + 1]
				dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], C.GRID_COLOR, 2)
			end
			if j + step <= cells then
				local c = points[(j + step) * stride + i + 1]
				dxDrawLine3D(a[1], a[2], a[3], c[1], c[2], c[3], C.GRID_COLOR, 2)
			end
		end
	end
end

local function isVisible(x, y, z, radius, camX, camY, camZ, fx, fy, fz)
	local dx = x - camX
	local dy = y - camY
	local dz = z - camZ
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dist <= radius then
		return true
	end
	local cosAngle = (dx * fx + dy * fy + dz * fz) / dist
	local angle = math.acos(math.max(-1, math.min(1, cosAngle)))
	return angle - math.asin(radius / dist) <= C.CULL_HALF_ANGLE
end

local function isChunkVisible(chunk, camX, camY, camZ, fx, fy, fz)
	return isVisible(chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2, chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2, chunk.centerZ, C.CULL_RADIUS, camX, camY, camZ, fx, fy, fz)
end

local function lodForDistance(dist)
	for k, level in ipairs(C.LOD_LEVELS) do
		if dist <= level.radius then
			return k
		end
	end
end

function ColGen.loadTerrain()
	S.terrainShader = dxCreateShader("Assets/Shaders/terrain.fx")
	if not S.terrainShader then
		outputDebugString("TerrainGen: terrain.fx failed to compile")
		return
	end
	local params = {grass = "gGrass", stone = "gRock", sand = "gSand", snow = "gSnow"}
	for mat, param in pairs(params) do
		local tex = dxCreateTexture(C.TEXTURE_PATHS[mat], "argb", true)
		S.terrainTextures[#S.terrainTextures + 1] = tex
		dxSetShaderValue(S.terrainShader, param, tex)
	end
	S.roadShader = dxCreateShader(C.ROAD_SHADER_PATH)
	S.roadTexture = dxCreateTexture(C.ROAD_TEXTURE_PATH, "argb", true)
	S.gravelTexture = dxCreateTexture(C.ROAD_GRAVEL_TEXTURE_PATH, "argb", true)
	if not S.gravelTexture then
		outputDebugString("TerrainGen: des_road.png failed to load")
	else
		S.terrainTextures[#S.terrainTextures + 1] = S.gravelTexture
	end
	local sandTex = dxCreateTexture(C.TEXTURE_PATHS.sand, "argb", true)
	local grassTex = dxCreateTexture(C.TEXTURE_PATHS.grass, "argb", true)
	S.terrainTextures[#S.terrainTextures + 1] = sandTex
	S.terrainTextures[#S.terrainTextures + 1] = grassTex
	if S.roadShader then
		dxSetShaderValue(S.roadShader, "gRoad", S.roadTexture)
		dxSetShaderValue(S.roadShader, "gSand", sandTex)
		dxSetShaderValue(S.roadShader, "gGrass", grassTex)
		dxSetShaderValue(S.roadShader, "gGravelRepeat", C.ROAD_TILE / C.ROAD_GRAVEL_TILE)
		if S.gravelTexture then
			dxSetShaderValue(S.roadShader, "gGravel", S.gravelTexture)
		end
	end
end

function ColGen.unloadTerrain()
	for _, tex in ipairs(S.terrainTextures) do
		destroyElement(tex)
	end
	S.terrainTextures = {}
	if S.terrainShader then
		destroyElement(S.terrainShader)
		S.terrainShader = nil
	end
	if S.roadTexture then
		destroyElement(S.roadTexture)
		S.roadTexture = nil
	end
	if S.roadShader then
		destroyElement(S.roadShader)
		S.roadShader = nil
	end
end

local BATCH_ARGS = 7000
local terrainBuf, roadBuf = {}, {}

local function appendBatch(buf, n, verts)
	for i = 1, #verts do
		buf[n + i] = verts[i]
	end
	return n + #verts
end

local function flushBatch(buf, n, shader, label)
	if n == 0 then
		return 0
	end
	local t0 = getTickCount()
	dxDrawMaterialPrimitive3D("trianglelist", shader, "prefx", unpack(buf, 1, n))
	ColGen.debugRecord(label, getTickCount() - t0)
	ColGen.debugRecord(label .. " items", n)
	frameTris = frameTris + n / 3
	return 0
end

function ColGen.renderChunks()
	ColGen.debugRecord("frame tris", frameTris)
	frameTris = 0
	if S.terrainShader then
		local camX, camY, camZ, lookX, lookY, lookZ = getCameraMatrix()
		local fx, fy, fz = lookX - camX, lookY - camY, lookZ - camZ
		local fLen = math.sqrt(fx * fx + fy * fy + fz * fz)
		fx, fy, fz = fx / fLen, fy / fLen, fz / fLen
		local terrainN, roadN = 0, 0
		for _, chunk in ipairs(S.chunkOrder) do
			if isChunkVisible(chunk, camX, camY, camZ, fx, fy, fz) then
				local dist = math.max(math.abs(chunk.cx - S.playerCX), math.abs(chunk.cy - S.playerCY))
				local ready = ColGen.hasRoadTriangles(chunk.cx, chunk.cy)
				local hasRoad = false
				if ready then
					local road, side = ColGen.getRoadTriangles(chunk.cx, chunk.cy)
					hasRoad = #road > 0 or #side > 0
				end
				local lod
				if hasRoad then
					lod = ColGen.flatLod(chunk)
				else
					lod = math.max(lodForDistance(dist), ColGen.flatLod(chunk))
				end
				if S.forceLod then
					lod = #C.LOD_LEVELS
				end
				chunk.drawLod = lod
			end
		end
			end
	if not S.gridVisible then
		return
	end
	for _, chunk in pairs(S.chunks) do
		drawChunkGrid(chunk.points, chunk.stride, C.LOD_LEVELS[chunk.drawLod or 1].step)
		for _, tri in ipairs(ColGen.getRoadDebugTriangles(chunk.cx, chunk.cy)) do
			for k = 1, 3 do
				local a, b = tri[k], tri[k % 3 + 1]
				dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], ROAD_COLLISION_DEBUG_COLOR, 2)
			end
		end
	end
end
