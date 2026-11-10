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
	for _, f in ipairs(faces) do
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

function ColGen.attachCollision(chunk)
	local model = engineRequestModel("object")
	if not model then
		return false
	end
	local verts, faces, _, _, centerX, centerY = ColGen.getGeometry(chunk.cx, chunk.cy)
	local fileName = "chunk_" .. chunk.cx .. "_" .. chunk.cy .. ".col"
	local file = fileCreate(fileName)
	if not file then
		engineFreeModel(model)
		return false
	end
	fileWrite(file, buildCol(model, verts, faces))
	fileClose(file)
	local col = engineLoadCOL(fileName)
	fileDelete(fileName)
	if not col or not engineReplaceCOL(col, model) then
		engineFreeModel(model)
		return false
	end
	local obj = createObject(model, centerX, centerY, C.BASE_Z)
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
	engineRestoreCOL(chunk.model)
	engineFreeModel(chunk.model)
	chunk.model = nil
	chunk.object = nil
end
