local crossgame <const> = achievements.crossgame
local gfx <const> = playdate.graphics

local scene = {}
Scenes.simple_viewer = scene

local games_view, games_list, games_data_index

function scene.enter()
	games_view = playdate.ui.gridview.new(0, 50)
	games_list = crossgame.listGames()
	games_view:setNumberOfRows(#games_list)
	games_data_index = {}

	for _, game in ipairs(games_list) do
		local data = crossgame.getData(game)
		games_data_index[game] = data
	end

	function games_view:drawCell(section, row, column, selected, x, y, width, height)
		local game_id = games_list[row]
		local game_data = games_data_index[game_id]
		if selected then
			gfx.drawRoundRect(x, y, width, height, 3)
		end
		playdate.graphics.drawText(game_data.name, x + 10, y + 5)
		playdate.graphics.drawText("By " .. game_data.author, x + 30, y + 25)
		gfx.drawTextAligned(math.floor(100 * game_data.completionPercentage) .. "%", width, y + 10, kTextAlignment.right)
	end
end

function scene.downButtonDown()
	games_view:selectNextRow(true)
end
function scene.upButtonDown()
	games_view:selectPreviousRow(true)
end

function scene.AButtonDown()
	local selected_game = games_list[games_view:getSelectedRow()]
	CHANGE_SCENE("simple_viewer_game", games_data_index[selected_game])
end
function scene.BButtonDown()
	CHANGE_SCENE("MAIN_DEBUG")
end

function scene.update()
	gfx.clear()
	games_view:drawInRect(10, 10, 380, 220)
	playdate.drawFPS(0,0)
end

scene_game = {}
Scenes.simple_viewer_game = scene_game
local achievement_view
local fallbackico = gfx.image.new("achievements/graphics/achievement-unlock")
local fallbackicolocked = gfx.imagetable.new("achievements/graphics/achievement-lock"):getImage(1)
local fallbackicosecret = gfx.imagetable.new("achievements/graphics/achievement-secret"):getImage(1)

function scene_game.enter(game_data)
	achievement_view = playdate.ui.gridview.new(0, 65)
	local icons = {}
	local icons_locked = {}
	local defaultico, defaulticolocked, icosecret
	if game_data.defaultIcon then
		defaultico = crossgame.loadImage(game_data.gameID, game_data.defaultIcon)
	end
	if game_data.defaultIconLocked then
		defaulticolocked = crossgame.loadImage(game_data.gameID, game_data.defaultIcon)
	end
	if game_data.secretIcon then
		icosecret = crossgame.loadImage(game_data.gameID, game_data.secretIcon)
	end
	for _, ach in ipairs(game_data.achievements) do
		if ach.icon then
			icons[ach.id] = crossgame.loadImage(game_data.gameID, ach.icon)
		end
		if ach.icon_locked then
			icons_locked[ach.id] = crossgame.loadImage(game_data.gameID, ach.icon_locked)
		end
	end

	achievement_view:setNumberOfRows(#game_data.achievements)
	function achievement_view:drawCell(section, row, column, selected, x, y, width, height)
		if selected then
			gfx.drawRoundRect(x, y, width, height, 3)
		end
		local ach = game_data.achievements[row]
		if ach.is_secret and not ach.granted_at then
			local icon = icosecret or fallbackicosecret
			icon:draw(x + 5, y + (height/2) - 16)
			gfx.drawText("Secret Achievement", x + 47, y + 5)
			gfx.drawText("Unlock to see name and description.", x + 67, y + 25)
		else
			local icon
			if not ach.granted_at then
				gfx.drawText(ach.name, x + 47, y + 5)
				icon = icons_locked[ach.id] or fallbackicolocked
				if ach.progress_max then
					local txt = ach.progress .. "/" .. ach.progress_max
					if ach.progress_is_percentage then
						txt = math.floor(100 * (ach.progress / ach.progress_max)) .. "%"
					end
					gfx.drawText("Completion: " .. txt, x + 67, y + 45)
				else
					gfx.drawText("Not yet earned.", x + 67, y + 45)
				end
			else
				gfx.drawText(ach.name, x + 47, y + 5)
				icon = icons[ach.id] or fallbackico
				local time = playdate.timeFromEpoch(ach.granted_at, 0)
				if time.hour < 10 then
					time.hour = "0" .. time.hour
				end
				if time.minute < 10 then
					time.minute = "0" .. time.minute
				end
				gfx.drawText(("Earned at: %s/%s/%s %s:%s"):format(time.year, 
					time.month, time.day, time.hour, time.minute), x + 67, y + 45)
			end
			icon:draw(x + 5, y + (height/2) - 16)
			gfx.drawText(ach.description, x + 67, y + 25)
		end
	end
end

function scene_game.downButtonDown()
	achievement_view:selectNextRow(true)
end
function scene_game.upButtonDown()
	achievement_view:selectPreviousRow(true)
end
function scene_game.BButtonDown()
	CHANGE_SCENE("simple_viewer")
end

function scene_game.update()
	gfx.clear()
	achievement_view:drawInRect(10, 10, 380, 220)
	playdate.drawFPS(0,0)
end