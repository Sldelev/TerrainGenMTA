local C = ColGen.cfg
local S = ColGen.state

addEventHandler("onClientResourceStart", resourceRoot, function ()
	removeGameWorld()
	setWaterLevel(-10000000,true,true,true,true)
	setOcclusionsEnabled(false)
	ColGen.loadTerrain()
	setTimer(ColGen.updateChunks, C.STREAM_INTERVAL, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function ()
	ColGen.unloadTerrain()
	ColGen.releaseAll()
end)

local lastFrameTick

addEventHandler("onClientRender", root, function ()
	local t0 = getTickCount()
	if lastFrameTick then
		ColGen.debugRecord("frame interval", t0 - lastFrameTick)
	end
	lastFrameTick = t0
	ColGen.pump()
	if not S.renderOff then
		ColGen.renderChunks()
	end
	ColGen.debugRecord("render chunks", getTickCount() - t0)
	local count = 0
	for _ in pairs(S.chunks) do
		count = count + 1
	end
	ColGen.debugValue("chunks loaded", count)
end)

addCommandHandler("tgrender", function ()
	S.renderOff = not S.renderOff
	outputChatBox("TerrainGen: отрисовка " .. (S.renderOff and "выключена" or "включена"), 255, 255, 0)
end)

addCommandHandler("tglod", function ()
	S.forceLod = not S.forceLod
	outputChatBox("TerrainGen: принудительный грубый LOD " .. (S.forceLod and "включен" or "выключен"), 255, 255, 0)
end)

addCommandHandler("tgdff", function ()
	local px, py = getElementPosition(localPlayer)
	local chunk = S.chunks[math.floor(px / C.CHUNK_SIZE) .. ":" .. math.floor(py / C.CHUNK_SIZE)]
	if not chunk then
		outputChatBox("TerrainGen: чанк под игроком не загружен", 255, 255, 0)
		return
	end
	local fileName = "test_" .. chunk.cx .. "_" .. chunk.cy .. ".dff"
	local size = ColGen.writeChunkDff(chunk, fileName)
	if not size then
		outputChatBox("TerrainGen: не удалось записать " .. fileName, 255, 255, 0)
		return
	end
	local model = engineRequestModel("object")
	if not model then
		fileDelete(fileName)
		outputChatBox("TerrainGen: нет свободного ID модели", 255, 255, 0)
		return
	end
	local dff = engineLoadDFF(fileName)
	if not dff then
		fileDelete(fileName)
		engineFreeModel(model)
		outputChatBox("TerrainGen: engineLoadDFF не загрузил файл", 255, 255, 0)
		return
	end
	local replaced = engineReplaceModel(dff, model)
	fileDelete(fileName)
	outputDebugString("TerrainGen dff: engineReplaceModel model " .. model .. " result " .. tostring(replaced))
	if not replaced then
		destroyElement(dff)
		engineFreeModel(model)
		outputChatBox("TerrainGen: engineReplaceModel не применил модель", 255, 255, 0)
		return
	end
	local centerX = chunk.cx * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local centerY = chunk.cy * C.CHUNK_SIZE + C.CHUNK_SIZE / 2
	local obj = createObject(model, centerX, centerY, chunk.centerZ)
	setElementFrozen(obj, true)
	engineApplyShaderToWorldTexture(S.terrainShader, "*", obj)
	outputDebugString("TerrainGen dff: object " .. tostring(obj) .. " at " .. centerX .. ", " .. centerY .. ", " .. chunk.centerZ)
	outputChatBox("TerrainGen: модель " .. model .. ", объект создан. Подробности в debugscript", 255, 255, 0)
end)

addCommandHandler("tgstat", function ()
	local px, py = getElementPosition(localPlayer)
	local pcx, pcy = math.floor(px / C.CHUNK_SIZE), math.floor(py / C.CHUNK_SIZE)
	local total, withObj, maxDist = 0, 0, 0
	for _, chunk in pairs(S.chunks) do
		total = total + 1
		if chunk.visual and isElement(chunk.visual.obj) then
			withObj = withObj + 1
		end
		maxDist = math.max(maxDist, math.max(math.abs(chunk.cx - pcx), math.abs(chunk.cy - pcy)))
	end
	outputChatBox("TerrainGen: CACHE_RADIUS " .. C.CACHE_RADIUS .. ", чанков " .. total .. ", с объектом " .. withObj .. ", макс. радиус " .. maxDist, 255, 255, 0)
end)

addCommandHandler("colgrid", function ()
	S.gridVisible = not S.gridVisible
	outputChatBox("COL: сетка " .. (S.gridVisible and "включена" or "выключена"), 255, 255, 0)
end)

addCommandHandler("TerrainGen", function (_, action, value)
	if string.lower(action or "") ~= "drawdistance" then
		outputChatBox("TerrainGen: /TerrainGen drawDistance <метры>", 255, 255, 0)
		return
	end
	local meters = tonumber(value)
	if not meters then
		outputChatBox("TerrainGen: /TerrainGen drawDistance <метры>", 255, 255, 0)
		return
	end
	meters = math.min(meters, ColGen.cfg.DRAW_DIST_MAX)
	local radius = ColGen.setDrawDistance(meters)
	outputChatBox("TerrainGen: дальность " .. meters .. " м, радиус чанков " .. radius, 255, 255, 0)
end)
