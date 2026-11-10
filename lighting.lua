local C = ColGen.cfg
local S = ColGen.state

local SUN_X, SUN_Y, SUN_Z = C.SUN[1], C.SUN[2], C.SUN[3]
local SUN_LEN = math.sqrt(SUN_X * SUN_X + SUN_Y * SUN_Y + SUN_Z * SUN_Z)

local function getTimeLight()
	local hour, minute = getTime()
	local t = hour + minute / 60
	if t >= 7 and t < 19 then
		return 1
	end
	if t >= 21 or t < 5 then
		return C.NIGHT_LIGHT
	end
	if t < 7 then
		return C.NIGHT_LIGHT + (1 - C.NIGHT_LIGHT) * (t - 5) / 2
	end
	return 1 - (1 - C.NIGHT_LIGHT) * (t - 19) / 2
end

function ColGen.faceShade(p1, p2, p3, light)
	local ux, uy, uz = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
	local vx, vy, vz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]
	local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
	local nLen = math.sqrt(nx * nx + ny * ny + nz * nz)
	local diffuse = 0
	if nLen > 0 then
		diffuse = math.max(0, (nx * SUN_X + ny * SUN_Y + nz * SUN_Z) / (nLen * SUN_LEN))
	end
	return math.floor(255 * (C.AMBIENT + C.DIFFUSE_STRENGTH * diffuse) * light + 0.5)
end

function ColGen.refreshLight()
	local light = getTimeLight()
	if math.abs(light - S.light) > C.LIGHT_EPSILON then
		S.light = light
	end
	for _, chunk in pairs(S.chunks) do
		if math.abs(chunk.light - S.light) > C.LIGHT_EPSILON then
			chunk.light = S.light
			chunk.draw = {}
		end
	end
end
