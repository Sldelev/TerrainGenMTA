local C = ColGen.cfg
local S = ColGen.state
local perlin2 = ColGen.perlin2
local smoothstep = ColGen.smoothstep

local NODE = C.ROAD_NODE
local LATERAL = C.ROAD_LATERAL
local RANGE = C.ROAD_LATERAL_RANGE
local BLOCK = C.ROAD_BLOCK_NODES
local BLOCK_LENGTH = BLOCK * NODE
local LANES = 2 * RANGE + 1
local FLAT = C.ROAD_HALF_WIDTH + C.ROAD_FLAT_MARGIN
local REACH = FLAT + C.ROAD_SHOULDER
local BRANCH_STEP = NODE / 2
local BRANCH_MIN_STEPS = 3
local BRANCH_CLEAR = REACH + 4
local function roadTrend(x)
	return C.ROAD_WANDER * perlin2(x * C.ROAD_SCALE, C.ROAD_SEED_Y)
end

local anchorCache = {}

local function anchorIndex(j)
	local cached = anchorCache[j]
	if cached then
		return cached
	end
	local x = j * BLOCK_LENGTH
	local trend = roadTrend(x)
	local bestK, bestCost = 0, math.huge
	for k = -RANGE, RANGE do
		local y = k * LATERAL
		local cost = ColGen.rawHeightAt(x, y) + C.ROAD_ANCHOR_PULL * math.abs(y - trend)
		if cost < bestCost then
			bestK, bestCost = k, cost
		end
	end
	anchorCache[j] = bestK
	return bestK
end

local function stepCost(dx, dy, ha, hb)
	local len = math.sqrt(dx * dx + dy * dy)
	local excess = math.max(0, math.abs(hb - ha) - C.ROAD_MAX_GRADE * len)
	return len + C.ROAD_GRADE_WEIGHT * excess + C.ROAD_SWITCH_WEIGHT * math.abs(dy)
end

local function solveBlock(j, hardGrade)
	local x0 = j * BLOCK_LENGTH
	local heights = {}
	for i = 0, BLOCK do
		local row = {}
		for k = -RANGE, RANGE do
			row[k] = ColGen.rawHeightAt(x0 + i * NODE, k * LATERAL)
		end
		heights[i] = row
		ColGen.yieldIfOver()
	end
	local cost = {}
	for k = -RANGE, RANGE do
		cost[k] = math.huge
	end
	cost[anchorIndex(j)] = 0
	local back = {}
	for i = 1, BLOCK do
		local nextCost, from = {}, {}
		local hPrev, hNext = heights[i - 1], heights[i]
		for b = -RANGE, RANGE do
			local bestCost, bestA = math.huge, 0
			for a = -RANGE, RANGE do
				if cost[a] < math.huge and math.abs(b - a) <= C.ROAD_MAX_STEP and (not hardGrade or math.abs(hNext[b] - hPrev[a]) <= C.ROAD_MAX_GRADE * math.sqrt(NODE * NODE + ((b - a) * LATERAL) ^ 2)) then
					local c = cost[a] + stepCost(NODE, (b - a) * LATERAL, hPrev[a], hNext[b])
					if c < bestCost then
						bestCost, bestA = c, a
					end
				end
			end
			nextCost[b] = bestCost
			from[b] = bestA
		end
		cost = nextCost
		back[i] = from
		ColGen.yieldIfOver()
	end
	local stop = anchorIndex(j + 1)
	if hardGrade and cost[stop] == math.huge then
		return nil
	end
	local route = {}
	local k = stop
	route[BLOCK] = k
	for i = BLOCK, 1, -1 do
		k = back[i][k]
		route[i - 1] = k
	end
	return route
end

local function routeToPath(j, route)
	local x0 = j * BLOCK_LENGTH
	local path = {}
	for i = 0, BLOCK do
		path[#path + 1] = {x0 + i * NODE, route[i] * LATERAL}
	end
	return path
end

local function maxGrade(path)
	local worst = 0
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local grade = math.abs(ColGen.rawHeightAt(b[1], b[2]) - ColGen.rawHeightAt(a[1], a[2])) / len
		worst = math.max(worst, grade)
	end
	return worst
end

local function relaxPath(path, passes)
	for _ = 1, passes do
		local out = {path[1]}
		for i = 2, #path - 1 do
			local a, p, b = path[i - 1], path[i], path[i + 1]
			out[i] = {0.5 * p[1] + 0.25 * (a[1] + b[1]), 0.5 * p[2] + 0.25 * (a[2] + b[2])}
		end
		out[#path] = path[#path]
		path = out
	end
	return path
end

local function buildBlock(j)
	local route = solveBlock(j, true) or solveBlock(j, false)
	return relaxPath(routeToPath(j, route), C.ROAD_RELAX_PASSES)
end

local function smoothPath(path, passes)
	for _ = 1, passes do
		local out = {path[1]}
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			out[#out + 1] = {0.75 * a[1] + 0.25 * b[1], 0.75 * a[2] + 0.25 * b[2]}
			out[#out + 1] = {0.25 * a[1] + 0.75 * b[1], 0.25 * a[2] + 0.75 * b[2]}
		end
		out[#out + 1] = path[#path]
		path = out
	end
	return path
end

local function roundCorners(path)
	local out = {path[1]}
	for i = 2, #path - 1 do
		local p, a, b = path[i], path[i - 1], path[i + 1]
		local ux, uy = p[1] - a[1], p[2] - a[2]
		local vx, vy = b[1] - p[1], b[2] - p[2]
		local lu = math.sqrt(ux * ux + uy * uy)
		local lv = math.sqrt(vx * vx + vy * vy)
		local cosTurn = math.max(-1, math.min(1, (ux * vx + uy * vy) / (lu * lv)))
		local turn = math.acos(cosTurn)
		if turn > C.ROAD_MAX_TURN then
			local t = math.min(C.ROAD_CORNER_RADIUS * math.tan(turn / 2), 0.45 * lu, 0.45 * lv)
			local ax, ay = p[1] - ux / lu * t, p[2] - uy / lu * t
			local bx, by = p[1] + vx / lv * t, p[2] + vy / lv * t
			out[#out + 1] = {ax, ay}
			for k = 1, C.ROAD_CORNER_SAMPLES do
				local u = k / (C.ROAD_CORNER_SAMPLES + 1)
				local w0, w1, w2 = (1 - u) * (1 - u), 2 * u * (1 - u), u * u
				out[#out + 1] = {w0 * ax + w1 * p[1] + w2 * bx, w0 * ay + w1 * p[2] + w2 * by}
			end
			out[#out + 1] = {bx, by}
		else
			out[#out + 1] = p
		end
	end
	out[#out + 1] = path[#path]
	return out
end

local function probeAdd(key, ms)
	ColGen.debugRecord("road " .. key, ms)
end
ColGen.probeTerrain = function(ms) probeAdd("terrain", ms) end

local function makeSegment(path, id)
	local arc = {0}
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		arc[i] = arc[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(path) do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
	end
	return {id = id, path = path, arc = arc, length = arc[#arc], minX = minX, maxX = maxX, minY = minY, maxY = maxY}
end

local function hash01(j, salt)
	local n = (j * 73856093 + salt * 19349663 + C.SEED * 83492791) % 2147483647
	n = (n * 16807) % 2147483647
	n = (n * 16807) % 2147483647
	return n / 2147483647
end

local pathCache, pathCount = {}, 0

local function pathFor(j)
	local path = pathCache[j]
	if path then
		return path
	end
	path = smoothPath(roundCorners(buildBlock(j)), C.ROAD_CORNER_PASSES)
	if pathCount >= C.ROAD_CACHE_LIMIT then
		pathCache, pathCount = {}, 0
	end
	pathCache[j] = path
	pathCount = pathCount + 1
	return path
end

local blockCache, blockCount = {}, 0
local function blockData(j)
	local data = blockCache[j]
	if data then
		return data
	end
	local t0 = getTickCount()
	data = makeSegment(pathFor(j), 4 * j)
	data.prev = 4 * (j - 1)
	data.next = 4 * (j + 1)
	if blockCount >= C.ROAD_CACHE_LIMIT then
		blockCache, blockCount = {}, 0
	end
	blockCache[j] = data
	blockCount = blockCount + 1
	probeAdd("block", getTickCount() - t0)
	return data
end

local branchData

local function segmentById(id)
	if id % 4 == 0 then
		return blockData(math.floor(id / 4))
	end
	return branchData(math.floor(id / 4))
end

local function pointAt(data, s)
	local path, arc = data.path, data.arc
	s = math.max(0, math.min(data.length, s))
	local lo, hi = 1, #arc
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if arc[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = path[lo], path[hi]
	local t = (s - arc[lo]) / (arc[hi] - arc[lo])
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dy * dy)
	return a[1] + t * dx, a[2] + t * dy, dx / len, dy / len
end

local function nearestOnBlock(data, x, y)
	local path = data.path
	local bestD2, bestI, bestT = math.huge, 1, 0
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local t = ((x - a[1]) * dx + (y - a[2]) * dy) / (dx * dx + dy * dy)
		t = math.max(0, math.min(1, t))
		local ex, ey = x - (a[1] + t * dx), y - (a[2] + t * dy)
		local d2 = ex * ex + ey * ey
		if d2 < bestD2 then
			bestD2, bestI, bestT = d2, i, t
		end
	end
	return math.sqrt(bestD2), data.arc[bestI] + bestT * (data.arc[bestI + 1] - data.arc[bestI])
end

local BRANCH_ANGLES = {-0.4, -0.2, 0, 0.2, 0.4}

local function branchSpec(j)
	if hash01(j, 1) >= C.ROAD_BRANCH_CHANCE or hash01(j - 1, 1) < C.ROAD_BRANCH_CHANCE then
		return nil
	end
	return {
		fraction = 0.25 + 0.5 * hash01(j, 2),
		side = hash01(j, 3) < 0.5 and -1 or 1,
		steps = BRANCH_MIN_STEPS + math.floor(hash01(j, 4) * (C.ROAD_BRANCH_MAX_STEPS - BRANCH_MIN_STEPS + 1)),
	}
end

local function mainPerp(j, x, y)
	local best = math.huge
	for k = j - 1, j + 1 do
		local perp = nearestOnBlock(blockData(k), x, y)
		best = math.min(best, perp)
	end
	return best
end

local function buildBranch(j, spec)
	local main = blockData(j)
	local px, py, tx, ty = pointAt(main, main.length * spec.fraction)
	local dx, dy = -ty * spec.side, tx * spec.side
	local path = {{px + dx * C.ROAD_HALF_WIDTH, py + dy * C.ROAD_HALF_WIDTH}}
	local prevPerp = mainPerp(j, path[1][1], path[1][2])
	local turned = 0
	for _ = 1, spec.steps do
		local last = path[#path]
		local ch = ColGen.rawHeightAt(last[1], last[2])
		local bestScore, bestX, bestY, bestDX, bestDY, bestA
		for _, a in ipairs(BRANCH_ANGLES) do
			local ca, sa = math.cos(a), math.sin(a)
			local ndx, ndy = dx * ca - dy * sa, dx * sa + dy * ca
			local nx, ny = last[1] + ndx * BRANCH_STEP, last[2] + ndy * BRANCH_STEP
			local grade = (ColGen.rawHeightAt(nx, ny) - ch) / BRANCH_STEP
			if math.abs(turned + a) <= C.ROAD_BRANCH_MAX_TURN and math.abs(grade) <= C.ROAD_MAX_GRADE and (mainPerp(j, nx, ny) >= BRANCH_CLEAR or mainPerp(j, nx, ny) >= prevPerp) then
				local score = math.abs(grade) + 0.5 * math.abs(a)
				if not bestScore or score < bestScore then
					bestScore, bestX, bestY, bestDX, bestDY, bestA = score, nx, ny, ndx, ndy, a
				end
			end
		end
		if not bestScore then
			break
		end
		path[#path + 1] = {bestX, bestY}
		dx, dy = bestDX, bestDY
		turned = turned + bestA
		local perp = mainPerp(j, bestX, bestY)
		if #path - 1 >= BRANCH_MIN_STEPS and perp < BRANCH_CLEAR and perp < prevPerp then
			break
		end
		prevPerp = perp
		ColGen.yieldIfOver()
	end
	if #path < 2 then
		return nil
	end
	return smoothPath(roundCorners(path), C.ROAD_CORNER_PASSES)
end

local branchCache = {}

function branchData(j)
	local cached = branchCache[j]
	if cached == nil then
		local spec = branchSpec(j)
		local path = spec and buildBranch(j, spec)
		cached = path and makeSegment(path, 4 * j + 1) or false
		if cached then
			cached.joinId = 4 * j
		end
		branchCache[j] = cached
	end
	return cached or nil
end

local function nearestRoad(x, y)
	local bestPerp, bestId, bestS = math.huge, 0, 0
	local jFrom = math.floor((x - REACH) / BLOCK_LENGTH)
	local jTo = math.floor((x + REACH) / BLOCK_LENGTH)
	for j = jFrom, jTo do
		local data = blockData(j)
		if x >= data.minX - REACH and x <= data.maxX + REACH and y >= data.minY - REACH and y <= data.maxY + REACH then
			local perp, s = nearestOnBlock(data, x, y)
			if perp < bestPerp then
				bestPerp, bestId, bestS = perp, data.id, s
			end
		end
	end
	for j = jFrom - 1, jTo + 1 do
		local branch = branchData(j)
		if branch and x >= branch.minX - REACH and x <= branch.maxX + REACH and y >= branch.minY - REACH and y <= branch.maxY + REACH then
			local perp, s = nearestOnBlock(branch, x, y)
			if perp < bestPerp then
				bestPerp, bestId, bestS = perp, branch.id, s
			end
		end
	end
	return bestPerp, bestId, bestS
end

local targetCache, targetCount = {}, 0

local function roadPoint(id, s)
	local data = segmentById(id)
	local length = data.length
	if s < 0 then
		if not data.prev then
			return pointAt(data, 0)
		end
		local before = segmentById(data.prev)
		return pointAt(before, before.length + s)
	end
	if s > length then
		if not data.next then
			return pointAt(data, length)
		end
		return pointAt(segmentById(data.next), s - length)
	end
	return pointAt(data, s)
end

local function ownTarget(id, s)
	local key = id * 1000000 + math.floor(s * 10)
	local cached = targetCache[key]
	if cached then
		return cached
	end
	local total = 0
	for k = -C.ROAD_SMOOTH_STEPS, C.ROAD_SMOOTH_STEPS do
		local t = s + k * C.ROAD_SAMPLE
		local px, py = roadPoint(id, t)
		total = total + ColGen.rawHeightAt(px, py)
	end
	local value = total / (2 * C.ROAD_SMOOTH_STEPS + 1)
	if targetCount >= C.ROAD_CACHE_LIMIT then
		targetCache, targetCount = {}, 0
	end
	targetCache[key] = value
	targetCount = targetCount + 1
	return value
end

local function roadTarget(id, s)
	if id % 4 ~= 1 then
		return ownTarget(id, s)
	end
	local data = segmentById(id)
	local px, py = pointAt(data, s)
	local _, sMain = nearestOnBlock(blockData(data.joinId / 4), px, py)
	local join = roadTarget(data.joinId, sMain)
	local own = ownTarget(id, s)
	return join + (own - join) * smoothstep(REACH, REACH + C.ROAD_BRANCH_RAMP, s)
end

local function roadTargetAt(x, y, id, s)
	if id % 4 ~= 1 then
		return roadTarget(id, s)
	end
	local data = segmentById(id)
	local _, sMain = nearestOnBlock(blockData(data.joinId / 4), x, y)
	local join = roadTarget(data.joinId, sMain)
	local own = ownTarget(id, s)
	return join + (own - join) * smoothstep(REACH, REACH + C.ROAD_BRANCH_RAMP, s)
end

local function centreTarget(data, s, p)
	if data.id % 4 == 1 then
		return roadTargetAt(p[1], p[2], data.id, s)
	end
	return roadTarget(data.id, s)
end

function ColGen.applyRoad(x, y, h)
	local perp, id, s = nearestRoad(x, y)
	if perp >= REACH then
		return h
	end
	local target = roadTargetAt(x, y, id, s)
	local limit = C.ROAD_SLOPE * math.max(0, perp - FLAT)
	local dev = math.max(-limit, math.min(limit, h - target))
	local m = 1 - smoothstep(FLAT, REACH, perp)
	return h + (target + dev - h) * m
end

local function nodeNormal(path, i, before, after)
	local function segNormal(a, b)
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		return -dy / len, dx / len
	end
	local ax, ay = segNormal(path[i - 1] or before, path[i])
	local bx, by = segNormal(path[i], path[i + 1] or after)
	local mx, my = ax + bx, ay + by
	local ml = math.sqrt(mx * mx + my * my)
	if ml < 1e-6 then
		return ax, ay, 1
	end
	mx, my = mx / ml, my / ml
	return mx, my, math.min(C.ROAD_MITER_LIMIT, 1 / (mx * ax + my * ay))
end

local cornerCache, cornerCount = {}, 0
local CORNER_LIMIT = 65536

local CORNER_SPAN = 2097152

local function cornerHeight(x, y)
	local key = math.floor(x / C.CELL + 0.5) * CORNER_SPAN + math.floor(y / C.CELL + 0.5)
	local h = cornerCache[key]
	if h then
		return h
	end
	h = ColGen.heightAt(x, y)
	if cornerCount >= CORNER_LIMIT then
		cornerCache, cornerCount = {}, 0
	end
	cornerCache[key] = h
	cornerCount = cornerCount + 1
	return h
end

local function gridHeight(x, y)
	local gx, gy = math.floor(x / C.CELL), math.floor(y / C.CELL)
	local fx, fy = x / C.CELL - gx, y / C.CELL - gy
	local x0, y0 = gx * C.CELL, gy * C.CELL
	local a = cornerHeight(x0, y0)
	local b = cornerHeight(x0 + C.CELL, y0)
	local c = cornerHeight(x0, y0 + C.CELL)
	local d = cornerHeight(x0 + C.CELL, y0 + C.CELL)
	if fy <= fx then
		return a + (b - a) * fx + (d - b) * fy
	end
	return a + (c - a) * fy + (d - c) * fx
end

local function slopeEdge(p, mx, my, scale, roadZ)
	local reach = math.min(REACH, FLAT + C.ROAD_SLOPE_MAX)
	for d = FLAT, reach do
		local x, y = p[1] + d * mx * scale, p[2] + d * my * scale
		local rise = math.abs(C.BASE_Z + gridHeight(x, y) - roadZ)
		if rise <= (d - C.ROAD_HALF_WIDTH) * C.ROAD_SLOPE_GRADE then
			return d
		end
	end
	return reach
end

local function gravelWeight(x, y)
	return smoothstep(C.ROAD_GRAVEL_LOW, C.ROAD_GRAVEL_HIGH, perlin2(x * C.ROAD_GRAVEL_SCALE, y * C.ROAD_GRAVEL_SCALE + 500))
end

local function nodeRing(p, mx, my, scale, roadZ, zAt, gravel)
	local outer = slopeEdge(p, mx, my, scale, roadZ)
	local rings = {-outer, -FLAT, -C.ROAD_HALF_WIDTH, 0, C.ROAD_HALF_WIDTH, FLAT, outer}
	local ring = {}
	for k, d in ipairs(rings) do
		local x, y = p[1] + d * mx * scale, p[2] + d * my * scale
		local ad = math.abs(d)
		local baseZ = zAt and zAt(x, y) or roadZ
		local z = baseZ
		if ad > C.ROAD_HALF_WIDTH then
			local t = math.min(1, (ad - C.ROAD_HALF_WIDTH) / (outer - C.ROAD_HALF_WIDTH))
			local ground = C.BASE_Z + gridHeight(x, y)
			z = baseZ + (ground - baseZ) * t
		end
		local uv = ad <= C.ROAD_HALF_WIDTH and ad / C.ROAD_HALF_WIDTH or 1 + (ad - C.ROAD_HALF_WIDTH) / (outer - C.ROAD_HALF_WIDTH)
		ring[k] = {x, y, z, uv, p[1] / C.ROAD_TILE, gravel and gravelWeight(x, y) or 0}
	end
	return ring
end

local function roadHeightAt(x, y)
	local _, id, s = nearestRoad(x, y)
	return C.BASE_Z + roadTargetAt(x, y, id, s) + C.ROAD_OFFSET
end

local function neighbourPoints(data)
	if data.nb then
		return data.nb[1], data.nb[2]
	end
	local path = data.path
	local beforeBlock = data.prev and segmentById(data.prev).path
	local afterBlock = data.next and segmentById(data.next).path
	local before = beforeBlock and beforeBlock[#beforeBlock - 1] or {2 * path[1][1] - path[2][1], 2 * path[1][2] - path[2][2]}
	local after = afterBlock and afterBlock[2] or {2 * path[#path][1] - path[#path - 1][1], 2 * path[#path][2] - path[#path - 1][2]}
	data.nb = {before, after}
	return before, after
end

local function ringAt(data, i)
	data.rings = data.rings or {}
	local ring = data.rings[i]
	if ring then
		return ring
	end
	local before, after = neighbourPoints(data)
	local path = data.path
	local mx, my, scale = nodeNormal(path, i, before, after)
	local lane = data.id % 4 == 1
	local z = C.BASE_Z + centreTarget(data, data.arc[i], path[i]) + C.ROAD_OFFSET
	ring = nodeRing(path[i], mx, my, scale, z, lane and roadHeightAt or nil, lane)
	data.rings[i] = ring
	return ring
end

local function stripFits(data, i, j)
	local arc = data.arc
	local span = arc[j] - arc[i]
	if span <= 0 then
		return false
	end
	local ri, rj = ringAt(data, i), ringAt(data, j)
	for m = i + 1, j - 1 do
		local t = (arc[m] - arc[i]) / span
		local rm = ringAt(data, m)
		for k = 1, 7 do
			local a, b, v = ri[k], rj[k], rm[k]
			local dx = v[1] - (a[1] + (b[1] - a[1]) * t)
			local dy = v[2] - (a[2] + (b[2] - a[2]) * t)
			local dz = v[3] - (a[3] + (b[3] - a[3]) * t)
			local dg = v[6] - (a[6] + (b[6] - a[6]) * t)
			if math.sqrt(dx * dx + dy * dy + dz * dz) > C.ROAD_DECIMATE_TOL or math.abs(dg) > C.ROAD_DECIMATE_GRAVEL then
				return false
			end
		end
	end
	return true
end

local function stripsOf(data)
	if data.strips then
		return data.strips
	end
	local strips = {}
	local n = #data.path
	local i = 1
	while i < n do
		local j = i + 1
		while j < n and stripFits(data, i, j + 1) do
			j = j + 1
		end
		strips[#strips + 1] = {i, j}
		i = j
	end
	data.strips = strips
	return strips
end

local function stripTriangles(data, i, j, road, side)
	local ri, rj = ringAt(data, i), ringAt(data, j)
	for k = 1, 6 do
		local p, q, r, t = ri[k], rj[k], rj[k + 1], ri[k + 1]
		local list = (k == 3 or k == 4) and road or side
		list[#list + 1] = {p, q, r}
		list[#list + 1] = {p, r, t}
	end
end

local triangleCache, triangleCount = {}, 0

local function addStripsInChunk(data, x0, y0, x1, y1, road, side)
	local path = data.path
	for _, s in ipairs(stripsOf(data)) do
		local a, b = path[s[1]], path[s[2]]
		if math.max(a[1], b[1]) + REACH >= x0 and math.min(a[1], b[1]) - REACH <= x1 and math.max(a[2], b[2]) + REACH >= y0 and math.min(a[2], b[2]) - REACH <= y1 then
			stripTriangles(data, s[1], s[2], road, side)
		end
	end
end

function ColGen.warmRoadBlock(cx, cy)
	local x0 = cx * C.CHUNK_SIZE
	local x1 = x0 + C.CHUNK_SIZE
	for j = math.floor((x0 - REACH) / BLOCK_LENGTH), math.floor((x1 + REACH) / BLOCK_LENGTH) do
		if not blockCache[j] then
			blockData(j)
			return true
		end
	end
	for j = math.floor((x0 - REACH) / BLOCK_LENGTH) - 1, math.floor((x1 + REACH) / BLOCK_LENGTH) + 1 do
		if branchCache[j] == nil then
			branchData(j)
			return true
		end
	end
	return false
end

function ColGen.getRoadTriangles(cx, cy)
	local key = cx .. ":" .. cy
	local cached = triangleCache[key]
	if cached then
		return cached.road, cached.side
	end
	local t0 = getTickCount()
	local road, side = {}, {}
	local x0 = cx * C.CHUNK_SIZE
	local y0 = cy * C.CHUNK_SIZE
	local x1, y1 = x0 + C.CHUNK_SIZE, y0 + C.CHUNK_SIZE
	for j = math.floor((x0 - REACH) / BLOCK_LENGTH), math.floor((x1 + REACH) / BLOCK_LENGTH) do
		addStripsInChunk(blockData(j), x0, y0, x1, y1, road, side)
		ColGen.yieldIfOver()
	end
	for j = math.floor((x0 - REACH) / BLOCK_LENGTH) - 1, math.floor((x1 + REACH) / BLOCK_LENGTH) + 1 do
		local branch = branchData(j)
		if branch then
			addStripsInChunk(branch, x0, y0, x1, y1, road, side)
		end
		ColGen.yieldIfOver()
	end
	if triangleCount >= C.ROAD_CACHE_LIMIT then
		triangleCache, triangleCount = {}, 0
	end
	triangleCache[key] = {road = road, side = side}
	triangleCount = triangleCount + 1
	probeAdd("tri", getTickCount() - t0)
	return road, side
end

local function rectDistance(px, py, x0, y0, x1, y1)
	local dx = math.max(x0 - px, 0, px - x1)
	local dy = math.max(y0 - py, 0, py - y1)
	return math.sqrt(dx * dx + dy * dy)
end

function ColGen.roadDistance(cx, cy, limit)
	local x0, y0 = cx * C.CHUNK_SIZE, cy * C.CHUNK_SIZE
	local x1, y1 = x0 + C.CHUNK_SIZE, y0 + C.CHUNK_SIZE
	local best = math.huge
	for j = math.floor((x0 - limit) / BLOCK_LENGTH) - 1, math.floor((x1 + limit) / BLOCK_LENGTH) + 1 do
		for _, p in ipairs(blockData(j).path) do
			best = math.min(best, rectDistance(p[1], p[2], x0, y0, x1, y1))
		end
		local branch = branchData(j)
		if branch then
			for _, p in ipairs(branch.path) do
				best = math.min(best, rectDistance(p[1], p[2], x0, y0, x1, y1))
			end
		end
	end
	return best
end

function ColGen.hasRoadTriangles(cx, cy)
	return triangleCache[cx .. ":" .. cy] ~= nil
end

function ColGen.getRoadDebugTriangles(cx, cy)
	local road, side = ColGen.getRoadTriangles(cx, cy)
	local all = {}
	for _, tri in ipairs(road) do
		all[#all + 1] = tri
	end
	for _, tri in ipairs(side) do
		all[#all + 1] = tri
	end
	return all
end

local function emitRoadTriangle(list, tri, light)
	local shade = ColGen.faceShade(tri[1], tri[2], tri[3], light)
	for k = 1, 3 do
		local p = tri[k]
		local color = tocolor(math.floor(p[6] * 255 + 0.5), 255, 255, shade)
		list[#list + 1] = {p[1], p[2], p[3], color, p[4], p[5]}
	end
end

function ColGen.getRoadDraw(chunk)
	local draw = chunk.draw.road
	if not draw then
		draw = {}
		local road, side = ColGen.getRoadTriangles(chunk.cx, chunk.cy)
		local t0 = getTickCount()
		for _, tri in ipairs(road) do
			emitRoadTriangle(draw, tri, S.light)
		end
		for _, tri in ipairs(side) do
			emitRoadTriangle(draw, tri, S.light)
		end
		probeAdd("draw", getTickCount() - t0)
		chunk.draw.road = draw
	end
	return draw
end