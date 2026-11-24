ColGen.debug = {
	enabled = false,
	stats = {},
	order = {},
}

local D = ColGen.debug

function ColGen.debugRecord(key, ms)
	local s = D.stats[key]
	if not s then
		s = {total = 0, count = 0, max = 0, last = 0}
		D.stats[key] = s
		D.order[#D.order + 1] = key
	end
	s.total = s.total + ms
	s.count = s.count + 1
	s.max = math.max(s.max, ms)
	s.last = ms
end

function ColGen.debugValue(key, value)
	local s = D.stats[key]
	if not s then
		s = {}
		D.stats[key] = s
		D.order[#D.order + 1] = key
	end
	s.value = value
end

function ColGen.debugLines()
	local lines = {}
	for _, key in ipairs(D.order) do
		local s = D.stats[key]
		if s.value ~= nil then
			lines[#lines + 1] = key .. ": " .. tostring(s.value)
		elseif s.count and s.count > 0 then
			lines[#lines + 1] = string.format("%s: avg %.2f ms, last %.2f, max %.2f (%d)", key, s.total / s.count, s.last, s.max, s.count)
		end
	end
	return lines
end

local panelFont = "default-bold"
local panelX, panelY = 10, 10
local lineHeight = 16

addEventHandler("onClientRender", root, function ()
	if not D.enabled then
		return
	end
	local lines = ColGen.debugLines()
	local height = #lines * lineHeight + 12
	local width = 420
	dxDrawRectangle(panelX, panelY, width, height, tocolor(0, 0, 0, 170), true)
	for i, text in ipairs(lines) do
		dxDrawText(text, panelX + 8, panelY + 6 + (i - 1) * lineHeight, panelX + width, panelY + 6 + i * lineHeight, tocolor(255, 255, 255, 255), 1, panelFont, "left", "top", false, false, true, false, false)
	end
end, false, "low", 0)

addCommandHandler("tgdebug", function (_, action)
	if action == "reset" then
		D.stats = {}
		D.order = {}
		outputChatBox("TerrainGen debug: статистика сброшена", 255, 255, 0)
		return
	end
	D.enabled = not D.enabled
	outputChatBox("TerrainGen debug: " .. (D.enabled and "включен" or "выключен"), 255, 255, 0)
end)
