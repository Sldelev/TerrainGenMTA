local C = ColGen.cfg
local S = ColGen.state

local loadStats = {total = 0, count = 0, max = 0}

local function createVisual(cx, cy)
	local _, faces, points, stride = ColGen.getGeometry(cx, cy)
	return {
		cx = cx,
		cy = cy,
		points = points,
		faces = faces,
		stride = stride,
		draw = {},
		light = S.light,
	}
end

function ColGen.releaseAll()
	for key, chunk in pairs(S.chunks) do
		ColGen.detachCollision(chunk)
		S.chunks[key] = nil
	end
end

function ColGen.updateChunks()
	ColGen.refreshLight()
	local chunks = S.chunks

	local px, py = getElementPosition(localPlayer)
	local pcx = math.floor(px / C.CHUNK_SIZE)
	local pcy = math.floor(py / C.CHUNK_SIZE)
	S.playerCX, S.playerCY = pcx, pcy

	local centerKey = pcx .. ":" .. pcy
	if not chunks[centerKey] then
		chunks[centerKey] = createVisual(pcx, pcy)
	end
	if not chunks[centerKey].model then
		ColGen.attachCollision(chunks[centerKey])
	end

	local createdVisual = 0
	for r = 0, C.CACHE_RADIUS do
		for dy = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local cx, cy = pcx + dx, pcy + dy
					local key = cx .. ":" .. cy
					if not chunks[key] and createdVisual < C.VISUAL_PER_TICK then
						chunks[key] = createVisual(cx, cy)
						createdVisual = createdVisual + 1
					end
				end
			end
		end
	end

	for key, chunk in pairs(chunks) do
		local ax, ay = math.abs(chunk.cx - pcx), math.abs(chunk.cy - pcy)
		if math.max(ax, ay) > C.CACHE_RADIUS then
			ColGen.detachCollision(chunk)
			chunks[key] = nil
		elseif math.max(ax, ay) > 1 then
			ColGen.detachCollision(chunk)
		end
	end

	local collisionLoaded = 0
	for _, off in ipairs(C.COLLISION_OFFSETS) do
		local chunk = chunks[(pcx + off[1]) .. ":" .. (pcy + off[2])]
		if chunk and not chunk.model and collisionLoaded < C.COLLISION_PER_TICK then
			local t0 = getTickCount()
			local ok = ColGen.attachCollision(chunk)
			local spent = getTickCount() - t0
			loadStats.total = loadStats.total + spent
			loadStats.count = loadStats.count + 1
			loadStats.max = math.max(loadStats.max, spent)
			if loadStats.count >= 20 then
				outputDebugString("colgen collision avg " .. string.format("%.2f", loadStats.total / loadStats.count) .. " ms, max " .. loadStats.max .. " ms")
				loadStats = {total = 0, count = 0, max = 0}
			end
			if ok then
				collisionLoaded = collisionLoaded + 1
			end
		end
	end
end
