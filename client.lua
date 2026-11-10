local C = ColGen.cfg
local S = ColGen.state

local renderMs, renderFrames, renderMax = 0, 0, 0

addEventHandler("onClientResourceStart", resourceRoot, function ()
	ColGen.loadTerrain()
	setTimer(ColGen.updateChunks, C.STREAM_INTERVAL, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function ()
	ColGen.unloadTerrain()
	ColGen.releaseAll()
end)

addEventHandler("onClientRender", root, function ()
	local t0 = getTickCount()
	ColGen.renderChunks()
	local frameMs = getTickCount() - t0
	renderMs = renderMs + frameMs
	renderMax = math.max(renderMax, frameMs)
	renderFrames = renderFrames + 1
	if renderFrames >= 300 then
		local count = 0
		for _ in pairs(S.chunks) do
			count = count + 1
		end
		outputDebugString("colgen render avg " .. string.format("%.2f", renderMs / renderFrames) .. " ms, max " .. renderMax .. " ms, chunks " .. count)
		renderMs, renderFrames, renderMax = 0, 0, 0
	end
end)

addCommandHandler("colgrid", function ()
	S.gridVisible = not S.gridVisible
	outputChatBox("COL: сетка " .. (S.gridVisible and "включена" or "выключена"), 255, 255, 0)
end)
