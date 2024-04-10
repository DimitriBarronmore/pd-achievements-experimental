import "achievements"
import "CoreLibs/graphics"

local gfx <const> = playdate.graphics

---@diagnostic disable-next-line: lowercase-global
toast_graphics = {
	displayGrantedMilliseconds = 2000,
	displayGrantedDefaultX = 20,
	displayGrantedDefaultY = 0,
	displayGrantedDelayNext = 400,
	iconWidth = 32,
	iconHeight = 32,
}

local function set_rounded_mask(img, width, height, round)
	gfx.pushContext(img:getMaskImage())
	gfx.clear(gfx.kColorBlack)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(0, 0, width, height, round)
	gfx.popContext()
end

-- make 'defaults' start with a *, so they can't show up in the file system, so any file-name the user can choose is valid
-- since lua's variable naming is more restrictive than the file-systems, we need to set them as strings
local path_to_image_data = {
	["*_default_icon"] = { image = gfx.image.new(toast_graphics.iconWidth, toast_graphics.iconHeight), ids = {} },
	["*_default_locked"] = { image = gfx.image.new(toast_graphics.iconWidth, toast_graphics.iconHeight), ids = {} },
}
local function load_images(gameID)
	-- 'load' default icon:
	-- TODO: art not final
	gfx.pushContext(path_to_image_data["*_default_icon"].image)
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(2, 2, toast_graphics.iconWidth - 4, toast_graphics.iconHeight - 4, 3)
	gfx.fillRect(14, 6, 4, 12)
	gfx.fillRect(14, 22, 4, 4)
	gfx.popContext()
	set_rounded_mask(path_to_image_data["*_default_icon"].image, toast_graphics.iconWidth, toast_graphics.iconHeight, 3)

	-- 'load' default locked icon:
	-- TODO: art not final
	gfx.pushContext(path_to_image_data["*_default_locked"].image)
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(2, 2, toast_graphics.iconWidth - 4, toast_graphics.iconHeight - 4, 3)
	gfx.setLineWidth(3)
	gfx.drawCircleInRect(12, 7, 8, 8)
	gfx.fillRect(9, 12, 14, 14)
	gfx.popContext()
	set_rounded_mask(path_to_image_data["*_default_locked"].image, toast_graphics.iconWidth, toast_graphics.iconHeight, 3)

	-- load images if a file is known, otherwise set defaults
	local paths_by_reference = achievements.getPaths(gameID, { "icon", "icon_locked" })
	for key, value in pairs(achievements.keyedAchievements) do
		if value.icon ~= nil then
			if path_to_image_data[value.icon] == nil then
				local filename = paths_by_reference[value.icon].native
				path_to_image_data[value.icon] = { image = gfx.image.new(filename), ids = {} }
			end
		else
			value.icon = "*_default_icon"
		end
		table.insert(path_to_image_data[value.icon].ids, key)
		if value.icon_locked ~= nil then
			if path_to_image_data[value.icon_locked] == nil then
				local filename = paths_by_reference[value.icon_locked].native
				path_to_image_data[value.icon_locked] = { image = gfx.image.new(filename), ids = {} }
			end
		else
			value.icon_locked = "*_default_locked"
		end
		table.insert(path_to_image_data[value.icon_locked].ids, key)
	end
end

function toast_graphics.initialize(gamedata, prevent_debug)
	achievements.initialize(gamedata, prevent_debug)
	load_images(achievements.gameData.gameID)
end

--[[ Achievement Drawing & Animation ]]--

local function resolve_achievement_or_id(achievement_or_id)
	if type(achievement_or_id) == "string" then
		return achievements.keyedAchievements[achievement_or_id]
	end
	return achievement_or_id
end

local function create_card(width, height, round, draw_func)
	local img = gfx.image.new(width, height)
	if draw_func ~= nil then
		gfx.pushContext(img)
		draw_func()
		gfx.popContext()
	end
	-- mask image, for rounded corners
	if round ~= nil and round > 0 then
		set_rounded_mask(img, width, height, round)
	end
	return img
end

local draw_card_cache = {} -- NOTE: don't forget to invalidate the cache on grant/revoke/progress!
local function draw_card_unsafe(ach, x, y, msec_since_granted)
	-- if not in cache yet, create the card for quick drawing later
	if draw_card_cache[ach.id] == nil then
		-- TODO: properly draw this, have someone with better art-experience look at it
		draw_card_cache[ach.id] = create_card(
			360,
			40,
			3,
			function()
				-- TODO?: 'achievement unlocked', progress, time, etc.??
				gfx.clear(gfx.kColorBlack)
				gfx.setImageDrawMode(gfx.kDrawModeCopy)
				gfx.setColor(gfx.kColorWhite)
				gfx.drawRoundRect(0, 0, 360, 40, 3, 3)
				-- TODO: either do these next 2 separately, or make the entire card into an animation
				local select_icon = ach.icon_locked
				if ach.granted_at then
					select_icon = ach.icon
				end
				path_to_image_data[select_icon].image:draw(4, 4)
				path_to_image_data[select_icon].image:draw(324, 4)
				gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
				-- TODO: get our own font in here, so we don't use the font users have set outside of the lib
				gfx.drawTextInRect(ach.name, 40, 14, 292, 60, nil, "...", kTextAlignment.center)
			end
		)
	end

	-- animation
	if msec_since_granted ~= 0 then
		x = x + 7.0 * math.sin(msec_since_granted / 90.0)
		y = y + (msec_since_granted / 10.0)
	end

	-- draw to screen
	gfx.pushContext()
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	draw_card_cache[ach.id]:draw(x, y);
	gfx.popContext()

	return msec_since_granted <= toast_graphics.displayGrantedMilliseconds
end

toast_graphics.drawCard = function(achievement_or_id, x, y, msec_since_granted)
	local ach = resolve_achievement_or_id(achievement_or_id)
	if not ach then
		error("attempt to draw unconfigured achievement '" .. achievement_or_id .. "'", 2)
		return
	end
	if x == nil or y == nil then
		x = toast_graphics.displayGrantedDefaultX
		y = toast_graphics.displayGrantedDefaultY
	end
	if msec_since_granted == nil then
		msec_since_granted = 0
	end
	-- split into 'unsafe' function, so that can be called internally without all the checks above each time
	return draw_card_unsafe(ach, x, y, msec_since_granted)
end

local animate_coros = {}
toast_graphics.updateVisuals = function ()
	for achievement_id, coro_func in pairs(animate_coros) do
		if not coroutine.resume(coro_func) then
			animate_coros[achievement_id] = nil
		end
	end
end

local last_grant_display_msec = -toast_graphics.displayGrantedDelayNext
local function start_granted_animation(ach, draw_card_func)
	draw_card_cache[ach.id] = nil
	-- tie display-coroutine to achievement-id, so that the system doesn't get confused by rapid grant/revoke
	animate_coros[ach.id] = coroutine.create(
		function ()
			-- NOTE: use getCurrentTimeMilliseconds here (regardless of time granted), since that'll take into account game-pausing.
			local start_msec = 0
			repeat
				start_msec = playdate.getCurrentTimeMilliseconds()
				coroutine.yield()
			until start_msec > (last_grant_display_msec + toast_graphics.displayGrantedDelayNext)
			last_grant_display_msec = start_msec
			local current_msec = start_msec
			while draw_card_func(
				ach,
				toast_graphics.displayGrantedDefaultX,
				toast_graphics.displayGrantedDefaultY,
				current_msec - start_msec
			) do
				coroutine.yield()
				current_msec = playdate.getCurrentTimeMilliseconds()
			end
		end
	)
end

--[[ Achievement Management Functions ]]--

toast_graphics.grant = function(achievement_id, draw_card_func)
	if achievements.grant(achievement_id) then
		local ach = achievements.keyedAchievements[achievement_id]
		if draw_card_func == nil then
			draw_card_func = draw_card_unsafe
		end
		start_granted_animation(ach, draw_card_func)
	end
end

toast_graphics.revoke = function(achievement_id)
	if achievements.revoke(achievement_id) then
		draw_card_cache[achievement_id] = nil
	end
end

toast_graphics.isGranted = function(achievement_id)
	return achievements.isGranted(achievement_id)
end

toast_graphics.save = function()
	achievements.save()
end

return toast_graphics
