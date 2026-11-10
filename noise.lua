local C = ColGen.cfg

local perm = {}
for i = 0, 255 do
	perm[i] = i
end
local rngState = C.SEED
for i = 255, 1, -1 do
	rngState = (rngState * 16807) % 2147483647
	local j = rngState % (i + 1)
	perm[i], perm[j] = perm[j], perm[i]
end
local P = {}
for i = 0, 511 do
	P[i] = perm[i % 256]
end

local GRADS = {{1, 1}, {-1, 1}, {1, -1}, {-1, -1}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local function fade(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, t)
	return a + t * (b - a)
end

local function grad(hash, dx, dy)
	local g = GRADS[hash % 8 + 1]
	return g[1] * dx + g[2] * dy
end

function ColGen.perlin2(x, y)
	local xi, yi = math.floor(x), math.floor(y)
	local xf, yf = x - xi, y - yi
	local X, Y = xi % 256, yi % 256
	local u, v = fade(xf), fade(yf)
	local aa = P[P[X] + Y]
	local ab = P[P[X] + Y + 1]
	local ba = P[P[X + 1] + Y]
	local bb = P[P[X + 1] + Y + 1]
	local x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u)
	local x2 = lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u)
	return lerp(x1, x2, v)
end

function ColGen.smoothstep(e0, e1, x)
	local t = math.max(0, math.min(1, (x - e0) / (e1 - e0)))
	return t * t * (3 - 2 * t)
end
