
require "stdlib/area/area"
require "stdlib/area/chunk"

function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end


function fm.generateMap(data)
    -- delete folder (if it already exists)
    local basePath = data.folderName
    game.remove_path(basePath .. "/Images/" .. data.subfolder .. "/")


    
    -- Number of pixels in an image
    local gridSizes = {256, 512, 1024} -- cant have 2048 anymore. code now relies on it being smaller than one game chunk (32 tiles * 32 pixels)
    local gridSize = gridSizes[data.gridSizeIndex]

    -- These are the number of tiles per grid section
    local gridPixelSize = gridSize / 32 -- 32 is a hardcoded Factorio value for pixels per tile.



    local player = game.players[data.player_index]
    
    local minX = nil
    local minY = nil
    local maxX = nil
    local maxY = nil

    local buildChunks = {}
    local allGrid = {}
    for chunk in player.surface.get_chunks() do
        if player.force.is_chunk_charted(player.surface, chunk) then
            for gridX = chunk.x * 32 / gridPixelSize, (chunk.x + 1) * 32 / gridPixelSize - 1 do
                for gridY = chunk.y * 32 / gridPixelSize, (chunk.y + 1) * 32 / gridPixelSize - 1 do
                    for k = 0, fm.autorun.around_build_range, 1 do
                        for l = 0, fm.autorun.around_build_range, 1 do
                            for m = -1, k > 0 and 1 or -1, 2 do
                                for n = -1, l > 0 and 1 or -1, 2 do
                                    local i = k * m
                                    local j = l * n
                                    if math.pow(2, i) + math.pow(2, j) <= math.pow(2, fm.autorun.around_build_range + .5) then
                                        local x = gridX + i
                                        local y = gridY + j
                                        local area = {{gridPixelSize * x, gridPixelSize * y}, {gridPixelSize * (x + 1), gridPixelSize * (y + 1)}}
                                        if buildChunks[x .. " " .. y] == nil then
                                            buildChunks[x .. " " .. y] = player.surface.count_entities_filtered({ force=player.force.name, area=area }) > player.surface.count_entities_filtered({ force=player.force.name, area=area, type={"player", "lamp", "electric-pole"} })
                                        end
                                        if buildChunks[x .. " " .. y] then
                                            allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY}

                                            minX = fm.helpers.getMin(minX, area[1][1])
                                            minY = fm.helpers.getMin(minY, area[1][2])
                            
                                            maxX = fm.helpers.getMax(maxX, area[2][1])
                                            maxY = fm.helpers.getMax(maxY, area[2][2])
                                            goto done
                                        end
                                    end
                                end
                            end
                        end
                    end
                    ::done::
                end
            end
        end
    end
    

    local mapArea = Area.normalize(Area.round_to_integer({{minX, minY}, {maxX, maxY}}))
    local _ ,inGameTotalWidth, inGameTotalHeight, _ = Area.size(mapArea)
    local inGameCenter = Area.center(mapArea)


    local minZoomLevel = data.gridSizeIndex
    local maxZoomLevel = 0 -- default

    local resolutionArray = {8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536,131072,262144,524288,1048576} -- resolution for each zoom level, lvl 0 is always 8x8 (256x256 pixels)

    local tmpCounter = 0 -- in google maps, max zoom out level is 0, so start with 0
    for _, resolution in pairs(resolutionArray) do
        if(inGameTotalWidth < resolution and inGameTotalHeight < resolution) then
            maxZoomLevel = tmpCounter
            break
        end
        tmpCounter = tmpCounter + 1
    end

    if maxZoomLevel > 0 and data.extraZoomIn ~= true then maxZoomLevel = maxZoomLevel - 1 end
    if maxZoomLevel < minZoomLevel then maxZoomLevel = minZoomLevel end

    --Setup the results table for feeding into generateIndex
    data.index = {}
    data.index.inGameCenter = inGameCenter
    data.index.maxZoomLevel = maxZoomLevel
    data.index.minZoomLevel = minZoomLevel
    data.index.gridSize = gridSize
    data.index.gridPixelSize = gridPixelSize

    local extension = "jpg"
    local pathText = ""
    local positionText = ""
    local resolutionText = ""
    local numHScreenshots = math.ceil(inGameTotalWidth / gridPixelSize)
    local numVScreenshots =  math.ceil(inGameTotalHeight / gridPixelSize)

    --Aligns the center of the Google map with the center of the coords we are making a map of.
    local screenshotWidth = gridPixelSize * numHScreenshots
    local screenshotHeight = gridPixelSize * numVScreenshots
    local screenshotCenter = {x = screenshotWidth / 2, y = screenshotHeight / 2}
    local screenshotTopLeftX = inGameCenter.x - screenshotCenter.x
    local screenshotTopLeftY = inGameCenter.y - screenshotCenter.y

    --[[if data.dayOnly then
        fm.helpers.makeDay(data.surfaceName)
    else
        -- Set to night then
        fm.helpers.makeNight(data.surfaceName)
    end]]--

    local text = (minZoomLevel + 20 - maxZoomLevel) .. " " .. 20
    for y = math.floor(minX/gridPixelSize/math.pow(2, maxZoomLevel-minZoomLevel)), math.ceil(maxX/gridPixelSize/math.pow(2, maxZoomLevel-minZoomLevel)) do
        for x = math.floor(minY/gridPixelSize/math.pow(2, maxZoomLevel-minZoomLevel)), math.ceil(maxY/gridPixelSize/math.pow(2, maxZoomLevel-minZoomLevel)) do
        	text = text .. "\n" .. x .. " " .. y
        end
    end
    game.write_file(basePath .. "/zoomData.txt", text, false, data.player_index)
    
    text = '{\n\t"ticks": ' .. game.tick .. ',\n\t"seed": ' .. game.default_map_gen_settings.seed .. ',\n\t"mods": ['
    local comma = false 
    for name, version in pairs(game.active_mods) do
        if name ~= "FactorioMaps" then
            if comma then
                text = text .. ","
            else
                comma = true
            end
            text = text .. '\n\t\t{\n\t\t\t"name": "' .. name .. '",\n\t\t\t"version": "' .. version .. '"\n\t\t}'
        end
    end
    text = text .. '\n\t]\n}'

    game.write_file(basePath .. "/mapInfo.json", text, false, data.player_index)


    local cropText = ""

    for _, chunk in pairs(allGrid) do   
        --game.print(chunk)

        positionTable = {(chunk.x + 0.5) * gridPixelSize, (chunk.y + 0.5) * gridPixelSize}

        local box = { positionTable[1], positionTable[2], (positionTable[1] + gridPixelSize), (positionTable[2] + gridPixelSize) } -- -X -Y X Y
        if data.render_light then
            for _, t in pairs(player.surface.find_entities_filtered{area={{box[1] - 16, box[2] - 16}, {box[3] + 16, box[4] + 16}}, type="lamp"}) do 
                if t.position.x < box[1] then
                    box[1] = t.position.x + 0.46875  --15/32, makes it so 1 pixel remains of the lamp
                elseif t.position.x > box[3] then
                    box[3] = t.position.x - 0.46875
                end
                if t.position.y < box[2] then
                    box[2] = t.position.y + 0.46875
                elseif t.position.y > box[4] then
                    box[4] = t.position.y - 0.46875
                end
            end
            if box[1] < positionTable[1] or box[2] < positionTable[2] or box[3] > positionTable[1] + gridPixelSize or box[4] > positionTable[2] + gridPixelSize then
                cropText = cropText .. "\n" .. chunk.x .. " " .. chunk.y .. " " .. (positionTable[1] - box[1])*32 .. " " .. (positionTable[2] - box[2])*32
            end
        end

        pathText = basePath .. "/Images/" .. data.subfolder .. "/20/" .. chunk.x .. "/" .. chunk.y .. "." .. extension
        game.take_screenshot({by_player=player, position = {(box[1] + box[3]) / 2, (box[2] + box[4]) / 2}, resolution = {(box[3] - box[1])*32, (box[4] - box[2])*32}, zoom = 1, path = pathText, show_entity_info = data.altInfo})                        
    end 
    
    if data.render_light then
        game.write_file(basePath .. "/crop-" .. data.subfolder .. ".txt", gridSize .. cropText, false, data.player_index)
    end
    
end