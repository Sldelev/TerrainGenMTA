local C = ColGen.cfg
local S = ColGen.state

local function drawChunkGrid(points, stride)
	local rows = #points / stride
	for j = 0, rows - 1 do
		for i = 0, stride - 1 do
			local a = points[j * stride + i + 1]
			if i < stride - 1 then
				local b = points[j * stride + i + 2]
				dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], C.GRID_COLOR, 2)
			end
			if j < rows - 1 then
				local c = points[(j + 1) * stride + i + 1]
				dxDrawLine3D(a[1], a[2], a[3], c[1], c[2], c[3], C.GRID_COLOR, 2)
			end
		end
	end
end

local function isChunkVisible(chunk, camX, camY, camZ, fx, fy, fz)
	local dx = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2 - camX
	local dy = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2 - camY
	local dz = C.BASE_Z - camZ
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dist <= C.CULL_RADIUS then
		return true
	end
	local cosAngle = (dx * fx + dy * fy + dz * fz) / dist
	local angle = math.acos(math.max(-1, math.min(1, cosAngle)))
	return angle - math.asin(C.CULL_RADIUS / dist) <= C.CULL_HALF_ANGLE
end

function ColGen.loadTerrain()
	S.terrainShader = dxCreateShader("Assets/Shaders/terrain.fx")
	if not S.terrainShader then
		outputDebugString("TerrainGen: terrain.fx failed to compile")
		return
	end
	local params = {grass = "gGrass", stone = "gRock", sand = "gSand", snow = "gSnow"}
	for mat, param in pairs(params) do
		local tex = dxCreateTexture(C.TEXTURE_PATHS[mat])
		S.terrainTextures[#S.terrainTextures + 1] = tex
		dxSetShaderValue(S.terrainShader, param, tex)
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
end

local function drawTerrain(verts)
	dxDrawMaterialPrimitive3D("trianglelist", S.terrainShader, "prefx", unpack(verts))
end

function ColGen.renderChunks()
	if S.terrainShader then
		local camX, camY, camZ, lookX, lookY, lookZ = getCameraMatrix()
		local fx, fy, fz = lookX - camX, lookY - camY, lookZ - camZ
		local fLen = math.sqrt(fx * fx + fy * fy + fz * fz)
		fx, fy, fz = fx / fLen, fy / fLen, fz / fLen
		for _, chunk in pairs(S.chunks) do
			if isChunkVisible(chunk, camX, camY, camZ, fx, fy, fz) then
				local dist = math.max(math.abs(chunk.cx - S.playerCX), math.abs(chunk.cy - S.playerCY))
				local lod = dist > C.LOD_NEAR_RADIUS and 2 or 1
				drawTerrain(ColGen.getChunkDraw(chunk, lod))
			end
		end
	end
	if not S.gridVisible then
		return
	end
	for _, chunk in pairs(S.chunks) do
		drawChunkGrid(chunk.points, chunk.stride)
	end
end
