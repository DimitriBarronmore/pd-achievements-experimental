
--[[
	==prototype achievements library==
	This is an initial prototype implementation in order to help effect a standard.
	This prototype will have no strong error checks and be small in scope. Any
	  wider-scope implementation of the standard will be separate.

	== planned usage ==

	Import the library using `import "achievements"
	The library has now created a global variable named "achievements".
	I hate this approach, but it's a prototype and this is how the playdate
	  does things because y'all are crazy.

	The user now needs to configure the library. Make a config table as so:

		local achievementData = {
			-- Technically, any string. We need to spell it out explicitly
			--   instead of using metadata.bundleID so that it won't get 
			--   mangled by online sideloading. Plus, this way multi-pdx
			--   games or demos can share achievements.
			gameID = "com.example.yourgame",
			-- These are optional, and will be auto-filled with metadata
			--   values if not specified here. This is also for multi-pdx
			--   games.
			name = "My Awesome Game",
			author = "You, Inc",
			description = "The next (r)evolution in cranking technology.",
			-- And finally, a table of achievements.
			achievements = {
				{
					id = "test_achievement",
					name = "Achievement Name",
					description = "Achievement Description",
					is_secret = false,
					icon = "filepath" -- to be iterated on
					[more to be determined]
				},
			}
		}

	This table makes up the top-level data structure being saved to the shared
	json file. The gameID field determines the name of the folder it will
	be written to, rather than bundleID, to keep things consistent.

	The only thing that is truly required is the gameID field, because this is
	  necessary for identification. Everything else can be left blank, and it
	  will be auto-filled or simply absent in the case of achievement data.

	The user passes the config table to the library like so:
		achievements.initialize(achievementData, preventdebug)
	This function finishes populating the configuration table with metadata
	  if necessary, merges the achievement data with the saved list of granted
	  achievements, creates the shared folder and .json file with the new data,
	  and iterates over the achievement data in order to copy images given to
	  the shared folder.
	If `preventdebug` evaluates true, initialization debugging messages will not
	  be printed to the console.

	In order to grant an achievement to the player, run `achievements.grant(id)`
	  If this is a valid achievement id, it will key the id to the current epoch
	  second in the achievement save data.
	In order to revoke an achievement, run `achievements.revoke(id)`
	  If this is a valid achievement id, it will remove the id from the save
	  data keys.
	
	To save achievement data, run `achievements.save()`. This will save granted
	  achievements to disk and save the game data to the shared json file. Run this
	  function alongside other game-save functions when the game exits. Of course,
	  unfortunately, achievements don't respect save slots.

	==details==
	The achievements file in the game's save directory is the prime authority on active achievements.
	It contains nothing more than a map of achievement IDs which have been earned by the player to when they were earned.
	This should make it extremely easy to manage, and prevents other games from directly messing with achievement data.
	The achievement files in the /Shared/Achievements/bundleID folder are regenerated at game load and when saving.
	They are to be generated by serializing `module.achievements` along with `module.localData` and copying any images (when we get to those).
--]]

-- TODO?: Maybe make importing these 'extra' graphics optional
import "CoreLibs/graphics"

-- Right, we're gonna make this easier to change in the future.
-- Another note: changing the data directory to `/Shared/gameID`
--   rather than the previously penciled in `/Shared/Achievements/gameID`
local default_shared_achievement_folder <const> = "/Shared/"
local default_achievement_file_name <const> = "Achievements.json"
local default_shared_images_subfolder <const> = "AchievementImages/"
local default_shared_images_updated_file <const> = "_last_seen_version.txt"

local function basename(str)
	local pos = str:reverse():find("/", 0, true)
	if pos == nil then
		return str
	end
	if pos == #str then
		pos = str:reverse():find("/", 2, true)
	end
	return str:sub((#str + 1) - (pos - 1))
end

local function parse_version_string(ver)
	local status = true

	local function split_all_after_first(str, char)
		local char_pos = str:find(char, 1, true)
		local res = nil
		if char_pos ~= nil then
			status, res = pcall(function() return { str:sub(0, char_pos - 1), str:sub(char_pos + 1, -1) } end)
			if status then
				return res[1], res[2]
			end
		end
		return str, ""
	end

	-- drop everything after '+' (as is normal in semver)
	ver, _ = split_all_after_first(ver, '+')
	-- also drop everything after '-' (as parsing that is massive overkill for the intended use)
	ver, _ = split_all_after_first(ver, '-')

	-- what is left should be a normal version number
	local result = {}
	while ver ~= nil and ver ~= "" do
		local num_str, next = split_all_after_first(ver, '.')
		if num_str ~= nil and num_str ~= "" then
			local num = nil
			status, num = pcall(function() return tonumber(num_str) end)
			if not status then
				num = -1
			end
			table.insert(result, num)
		end
		ver = next
	end

	return result
end

local function compare_version_strings(version_a, version_b)
	local ver_a = parse_version_string(version_a)
	local ver_b = parse_version_string(version_b)
	local longest = math.max(#ver_a, #ver_b)
	for i_pos = 1, longest, 1 do
		ver_a[i_pos] = ver_a[i_pos] or 0
		ver_b[i_pos] = ver_b[i_pos] or 0
		if ver_a[i_pos] < ver_b[i_pos] then
			return -1
		end
		if ver_a[i_pos] > ver_b[i_pos] then
			return 1
		end
	end
	return 0
end

local function get_achievement_folder_root_path(gameID)
	if type(gameID) ~= "string" then
		error("bad argument #1: expected string, got " .. type(gameID), 2)
	end
	local root = string.format(default_shared_achievement_folder .. "%s/", gameID)
	return root
end
local function get_achievement_data_file_path(gameID)
	if type(gameID) ~= "string" then
		error("bad argument #1: expected string, got " .. type(gameID), 2)
	end
	local root = get_achievement_folder_root_path(gameID)
	return root .. default_achievement_file_name
end
local function get_shared_images_path(gameID)
	if type(gameID) ~= "string" then
		error("bad argument #1: expected string, got " .. type(gameID), 2)
	end
	local root = get_achievement_folder_root_path(gameID)
	return root .. default_shared_images_subfolder
end
local function get_shared_images_updated_file_path(gameID)
	if type(gameID) ~= "string" then
		error("bad argument #1: expected string, got " .. type(gameID), 2)
	end
	local folder = get_shared_images_path(gameID)
	return folder .. default_shared_images_updated_file
end

local metadata <const> = playdate.metadata
local gfx <const> = playdate.graphics

---@diagnostic disable-next-line: lowercase-global
achievements = {
	specversion = "0.1+prototype",
	libversion = "0.2-alpha+prototype",

	onUnconfigured = error,
	forceSaveOnGrantOrRevoke = false,

	displayGrantedMilliseconds = 2000,
	displayGrantedDefaultX = 20,
	displayGrantedDefaultY = 0,
	displayGrantedDelayNext = 400,
	iconWidth = 32,
	iconHeight = 32,
}

local function load_granted_data(from_file)
	if from_file == nil then
		from_file = "./" .. default_achievement_file_name
	end
	local data = json.decodeFile(from_file)
	if not data then
		data = {}
	end
	achievements.granted = data
end

local function export_data()
	local data = achievements.gameData
	json.encodeToFile(get_achievement_data_file_path(data.gameID), true, data)
end
function achievements.save(to_file)
	if to_file == nil then
		to_file = "./" .. default_achievement_file_name
	end
	export_data()
	json.encodeToFile(to_file, false, achievements.granted)
end

local function set_rounded_mask(img, width, height, round)
	gfx.pushContext(img:getMaskImage())
	gfx.clear(gfx.kColorBlack)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(0, 0, width, height, round)
	gfx.popContext()
end

local path_to_image_data = {
	_default_icon = { image = gfx.image.new(achievements.iconWidth, achievements.iconHeight), ids = {} },
	_default_locked = { image = gfx.image.new(achievements.iconWidth, achievements.iconHeight), ids = {} },
}
local function load_images()
	-- 'load' default icon:
	-- TODO: art not final
	gfx.pushContext(path_to_image_data._default_icon.image)
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(2, 2, achievements.iconWidth - 4, achievements.iconHeight - 4, 3)
	gfx.fillRect(14, 6, 4, 12)
	gfx.fillRect(14, 22, 4, 4)
	gfx.popContext()
	set_rounded_mask(path_to_image_data._default_icon.image, achievements.iconWidth, achievements.iconHeight, 3)

	-- 'load' default locked icon:
	-- TODO: art not final
	gfx.pushContext(path_to_image_data._default_locked.image)
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRoundRect(2, 2, achievements.iconWidth - 4, achievements.iconHeight - 4, 3)
	gfx.setLineWidth(3)
	gfx.drawCircleInRect(12, 7, 8, 8)
	gfx.fillRect(9, 12, 14, 14)
	gfx.popContext()
	set_rounded_mask(path_to_image_data._default_locked.image, achievements.iconWidth, achievements.iconHeight, 3)

	-- load images if a file is known, otherwise set defaults
	for key, value in pairs(achievements.keyedAchievements) do
		if value.icon ~= nil then
			if path_to_image_data[value.icon] == nil then
				path_to_image_data[value.icon] = { image = gfx.image.new(value.icon), ids = {} }
			end
		else
			value.icon = "_default_icon"
		end
		table.insert(path_to_image_data[value.icon].ids, key)
		if value.icon_locked ~= nil then
			if path_to_image_data[value.icon_locked] == nil then
				path_to_image_data[value.icon_locked] = { image = gfx.image.new(value.icon_locked), ids = {} }
			end
		else
			value.icon_locked = "_default_locked"
		end
		table.insert(path_to_image_data[value.icon_locked].ids, key)
	end
end

local function copy_images_to_shared(gameID, current_version_str)
	-- if >= the current version of the gamedata already exists, no need to re-copy the images
	local path = get_shared_images_updated_file_path(gameID)
	if playdate.file.exists(path) and not playdate.file.isdir(path) then
		local ver_file, err = playdate.file.open(path, playdate.file.kFileRead)
		if not ver_file then
			error("Couldn't read version file at '" .. path .. "', because: " .. err, 2)
		end
		local ver_str = ver_file:readline() or "0.0.0"
		ver_file:close()
		if compare_version_strings(ver_str, current_version_str) <= 0 then
			return
		end
	end

	-- otherwise, the structure should be copied
	local folder = get_shared_images_path(gameID)
	if playdate.file.exists(folder) then
		playdate.file.delete(folder, true)
	end
	playdate.file.mkdir(folder)
	local skip_default_icons <const> = { _default_icon = true, _default_locked = true }
	for original_path, data in pairs(path_to_image_data) do
		if skip_default_icons[original_path] == nil then
			if original_path:sub(1,1) == "/" then
				error("Absolute paths in the (non-shared) achievement template data aren't implemented. (Yet?)", 2)
			end
			local shared_path = folder .. original_path
			local subfolder = basename(shared_path)
			if not playdate.file.exists(subfolder) then
				playdate.file.mkdir(subfolder)
			end
			playdate.datastore.writeImage(data.image, shared_path)
		end
	end

	-- also write the version-file
	local ver_file, err = playdate.file.open(path, playdate.file.kFileWrite)
	if not ver_file then
		error("Couldn't write version file at '" .. path .. "', because: " .. err, 2)
	end
	ver_file:write(current_version_str)
	ver_file:close()
end

local function donothing(...) end
function achievements.initialize(gamedata, prevent_debug)
	local print = (prevent_debug and donothing) or print
	print("------")
	print("Initializing achievements...")
	if gamedata.achievements == nil then
		print("WARNING: no achievements configured")
		gamedata.achievements = {}
	elseif type(gamedata.achievements) ~= "table" then
		error("achievements must be a table", 2)
	end
	if gamedata.gameID == nil then
		gamedata.gameID = string.gsub(metadata.bundleID, "^user%.%d+%.", "")
		print('gameID not configured: defaulting to "' .. gamedata.gameID .. '"')
	elseif type(gamedata.gameID) ~= "string" then
		error("gameID must be a string", 2)
	end
	for _, field in ipairs{"name", "author", "version", "description"} do
		if gamedata[field] == nil then
			if playdate.metadata[field] ~= nil then
				gamedata[field] = playdate.metadata[field]
				print(field .. ' not configured: defaulting to "' .. gamedata[field] .. '"')
			else
				print("WARNING: " .. field .. " not configured AND not present in pxinfo metadata")
			end
		elseif type(gamedata[field]) ~= "string" then
			error(field .. " must be a string", 2)
		end
	end
	gamedata.version = metadata.version
	gamedata.specversion = achievements.specversion
	gamedata.libversion = achievements.libversion
	print("game version saved as \"" .. gamedata.version .. "\"")
	print("library version saved as \"" .. gamedata.libversion .. "\"")
	achievements.gameData = gamedata

	load_granted_data()

	achievements.keyedAchievements = {}
	for _, ach in ipairs(gamedata.achievements) do
		if achievements.keyedAchievements[ach.id] then
			error("achievement id '" .. ach.id .. "' defined multiple times", 2)
		end
		achievements.keyedAchievements[ach.id] = ach
		ach.granted_at = achievements.granted[ach.id] or false
	end

	load_images()

	playdate.file.mkdir(get_achievement_folder_root_path(gamedata.gameID))
	export_data()
	copy_images_to_shared(gamedata.gameID, gamedata.version)

	print("files exported to /Shared")
	print("Achievements have been initialized!")
	print("------")
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
local function draw_card_unsafe(ach, x, y)
	-- TODO: get our own font in here, so we don't use the font users have set outside of the lib
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
				gfx.drawTextInRect(ach.name, 40, 14, 292, 60, nil, "...", kTextAlignment.center)
			end
		)
	end

	gfx.pushContext()
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	draw_card_cache[ach.id]:draw(x, y);
	gfx.popContext()
end

achievements.drawCard = function (achievement_or_id, x, y)
	local ach = resolve_achievement_or_id(achievement_or_id)
	if not ach then
		achievements.onUnconfigured("attempt to draw unconfigured achievement '" .. achievement_or_id .. "'", 2)
		return
	end
	if x == nil or y == nil then
		x = achievements.displayGrantedDefaultX
		y = achievements.displayGrantedDefaultY
	end
	draw_card_unsafe(ach, x, y)
end

local function animate_granted_unsafe(ach, x, y, msec_since_granted, draw_card_func)
	-- TODO: like for drawing, this needs a bit more care and attention from someone with an art eye
	draw_card_func(
		ach,
		x + 7.0 * math.sin(msec_since_granted / 90.0),
		y + (msec_since_granted / 10.0)
	)
	return msec_since_granted <= achievements.displayGrantedMilliseconds
end

achievements.animateGranted = function(achievement_or_id, x, y, msec_since_granted, draw_card_func)
	local ach = resolve_achievement_or_id(achievement_or_id)
	if not ach then
		achievements.onUnconfigured("attempt to animate unconfigured achievement '" .. achievement_or_id .. "'", 2)
		return
	end
	if x == nil or y == nil then
		x = achievements.displayGrantedDefaultX
		y = achievements.displayGrantedDefaultY
	end
	if msec_since_granted == nil then
		-- for now, the animation will take an equal time in as out, so 'half-time' is a good position to draw unspecified
		msec_since_granted = achievements.displayGrantedMilliseconds / 2
	end
	if draw_card_func == nil then
		draw_card_func = draw_card_unsafe
	end
	return animate_granted_unsafe(ach, x, y, msec_since_granted, draw_card_func)
end

local animate_coros = {}
achievements.updateVisuals = function ()
	for achievement_id, coro_func in pairs(animate_coros) do
		if not coroutine.resume(coro_func) then
			animate_coros[achievement_id] = nil
		end
	end
end

local last_grant_display_msec = -achievements.displayGrantedDelayNext
local function start_granted_animation(ach, draw_card_func, animate_func)
	draw_card_cache[ach.id] = nil
	-- tie display-coroutine to achievement-id, so that the system doesn't get confused by rapid grant/revoke
	animate_coros[ach.id] = coroutine.create(
		function ()
			-- NOTE: use getCurrentTimeMilliseconds here (regardless of time granted), since that'll take into account game-pausing.
			local start_msec = 0
			repeat
				start_msec = playdate.getCurrentTimeMilliseconds()
				coroutine.yield()
			until start_msec > (last_grant_display_msec + achievements.displayGrantedDelayNext)
			last_grant_display_msec = start_msec
			local current_msec = start_msec
			while animate_func(
				ach,
				achievements.displayGrantedDefaultX,
				achievements.displayGrantedDefaultY,
				current_msec - start_msec,
				draw_card_func
			) do
				coroutine.yield()
				current_msec = playdate.getCurrentTimeMilliseconds()
			end
		end
	)
end

--[[ Achievement Management Functions ]]--

achievements.getInfo = function(achievement_id)
	return achievements.keyedAchievements[achievement_id] or false
end

achievements.grant = function(achievement_id, silent, draw_card_func, animate_func)
	local ach = achievements.keyedAchievements[achievement_id]
	if not ach then
		achievements.onUnconfigured("attempt to grant unconfigured achievement '" .. achievement_id .. "'", 2)
		return false
	end
	local time, _ = playdate.getSecondsSinceEpoch()
	if ach.granted_at ~= false and arch.granted_at <= ( time ) then
		return false
	end
	achievements.granted[achievement_id] = ( time )
	ach.granted_at = time

	if achievements.forceSaveOnGrantOrRevoke then
		achievements.save()
	end

	-- drawing, if needed
	if not silent then
		if draw_card_func == nil then
			draw_card_func = draw_card_unsafe
		end
		if animate_func == nil then
			animate_func = animate_granted_unsafe
		end
		start_granted_animation(ach, draw_card_func, animate_func)
	end
	return true
end

achievements.revoke = function(achievement_id)
	local ach = achievements.keyedAchievements[achievement_id]
	if not ach then
		achievements.onUnconfigured("attempt to revoke unconfigured achievement '" .. achievement_id .. "'", 2)
		return false
	end
	ach.granted_at = false
	achievements.granted[achievement_id] = nil
	if achievements.forceSaveOnGrantOrRevoke then
		achievements.save()
	end
	draw_card_cache[achievement_id] = nil
	return true
end

--[[ External Game Functions ]]--

achievements.gamePlayed = function(game_id)
	return playdate.file.isdir(get_achievement_folder_root_path(game_id))
end

achievements.gameData = function(game_id)
	if not achievements.gamePlayed(game_id) then
		error("No game with ID '" .. game_id .. "' was found", 2)
	end
	local data = json.decodeFile(get_achievement_data_file_path(game_id))
	local keys = {}
	for _, ach in ipairs(data.achievements) do
		keys[ach.id] = ach
	end
	data.keyedAchievements = keys
	return data
end


return achievements
