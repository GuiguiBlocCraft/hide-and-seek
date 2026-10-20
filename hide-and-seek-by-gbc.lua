-- name: Hide'n Seek
-- incompatible: gamemode
-- description: A hide and seek modified :D\n\n\\#dcdcdc\\Concept by \\#00f000\\Super Keeberghrh\n\\#dcdcdc\\Modified by \\#f0f000\\GuiguiBlocCraft

-- constants
local ROUND_STATE_WAIT             = 0
local ROUND_STATE_ACTIVE           = 1
local ROUND_STATE_SEEKERS_WIN      = 2
local ROUND_STATE_RESETING         = 3
local ROUND_STATE_UNKNOWN_END      = 4
local ROUND_STATE_TIMEOUT          = 5

-- globals
gGlobalSyncTable.roundState        = ROUND_STATE_WAIT -- current round state
gGlobalSyncTable.tickTimer         = 0                -- 30 tick per second
gGlobalSyncTable.selectLevel       = LEVEL_CASTLE
gGlobalSyncTable.selectArea        = 1
gGlobalSyncTable.timeToHide        = 60 * 30

-- variables
local np = gNetworkPlayers[0]
local clientInitialized = false
local displayNametags = gServerSettings.nametags
local sRoundTimer = 0
local cannonTimer = 0
local timerBeforeReset = 0
local ticksToReset = 30 * 30
local seekerIsOut = false
local seekerSelected = -1
local isTimeDisplayed = false
local playersExcluded = {}
local teleported = true
local isMenuOpen = false
local menuSelection = 1
local inSelection = false
local healthPrev = 0x880
local healthPos = { prevX = 0, x = 0 }
local healthShow = false
local healthTimer = 0

_G.HnS = {
	titles = {
		"Castle Main Floor",
		"Castle Upper Floor",
		"Castle Basement"
	},
	levels = {
		{ LEVEL_CASTLE, 1 },
		{ LEVEL_CASTLE, 2 },
		{ LEVEL_CASTLE, 3 }
	}
}

-- server settings
gServerSettings.bubbleDeath        = 0
gServerSettings.skipIntro          = 1
gServerSettings.pauseAnywhere      = 0
gServerSettings.playerInteractions = PLAYER_INTERACTIONS_SOLID
gLevelValues.disableActs           = true
gLevelValues.zoomOutCameraOnPause  = false
djui_set_popup_disabled_override(true)

-- Remove all names
for i = 0, COURSE_MAX - 1 do
	smlua_text_utils_course_name_replace(i, "Level Hidden")
end

-- localize functions to improve performance
local
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server, hook_event, play_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font, djui_hud_set_color, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height, djui_hud_measure_text, warp_to_level, dist_between_objects, math_floor, math_sin, table_insert, set_camera_mode =
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server, hook_event, play_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font, djui_hud_set_color, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height, djui_hud_measure_text, warp_to_level, dist_between_objects, math.floor, math.sin, table.insert, set_camera_mode

local function players_list()
	local activePlayers = {}

	for i = 0, (MAX_PLAYERS - 1) do
		if gNetworkPlayers[i].connected then
			table_insert(activePlayers, gPlayerSyncTable[i])
		end
	end

	return activePlayers
end

local function on_packet_receive(data)
	if data.round then
		gGlobalSyncTable.roundState = data.round
	end
	if data.level then
		gGlobalSyncTable.selectLevel = data.level
	end
	if data.area then
		gGlobalSyncTable.selectArea = data.area
	end

	if data.attackedBy and data.from then
		djui_chat_message_create("\\#f0f000\\" .. data.from .. "\\#ffffff\\ caught by \\#f0f000\\" .. data.attackedBy .. "\\#ffffff\\")
	elseif data.from then
		djui_chat_message_create("\\#f0f000\\" .. data.from .. "\\#ffffff\\ died and became a seeker")
	end
end

local function network_send_and_self(reliable, data)
	network_send(reliable, data)
	on_packet_receive(data)
end

local function start_round()
	-- reset seekers
	for i = 0, (MAX_PLAYERS - 1) do
		gPlayerSyncTable[i].seeking = false
	end

	-- pick random seeker
	local playerSelected = 0
	local playersList = players_list()

	if #playersExcluded >= #playersList then
		local lastSelected = playersExcluded[#playersExcluded]
		playersExcluded = { lastSelected }
	end

	if seekerSelected > -1 then
		playerSelected = seekerSelected + 1
	else
		while true do
			local alreadySeeker = false

			playerSelected = math.random(#playersList)

			for i = 1, #playersExcluded do
				if playersExcluded[i] == playerSelected then
					alreadySeeker = true
					break
				end
			end

			if not alreadySeeker then
				break
			end
		end
	end

	table_insert(playersExcluded, playerSelected)

	if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		network_send_and_self(true, {
			round = ROUND_STATE_WAIT
		})
	end

	playersList[playerSelected].seeking = true

	network_send_and_self(true, {
		round = ROUND_STATE_ACTIVE,
		level = HnS.levels[menuSelection][1],
		area = HnS.levels[menuSelection][2]
	})

	sRoundTimer = 0
	seekerSelected = -1
end

local function update()
	-- only allow the server to figure out the seeker
	if network_is_server() then
		-- increment timer
		sRoundTimer = sRoundTimer + 1
		gGlobalSyncTable.tickTimer = sRoundTimer

		-- figure out state of the game
		local hasSeeker = false
		local hasHider = false

		for i = 0, (MAX_PLAYERS - 1) do
			if gNetworkPlayers[i].connected then
				if gPlayerSyncTable[i].seeking then
					hasSeeker = true
				else
					hasHider = true
				end
			end
		end

		-- only change state if there are 2+ players
		if network_player_connected_count() < 2 then
			gGlobalSyncTable.roundState = ROUND_STATE_WAIT
		elseif gGlobalSyncTable.roundState == ROUND_STATE_WAIT or gGlobalSyncTable.roundState == ROUND_STATE_RESETING then
			network_send_and_self(true, {
				round = ROUND_STATE_UNKNOWN_END
			})
			sRoundTimer = 0
		end

		-- check to see if the round should end
		if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
			if not hasHider then
				network_send_and_self(true, {
					round = ROUND_STATE_SEEKERS_WIN
				})
				sRoundTimer = 0
			elseif not hasSeeker then -- if seeker disconnected in game
				if timerBeforeReset == 0 then
					timerBeforeReset = sRoundTimer
				elseif sRoundTimer - timerBeforeReset == ticksToReset then
					network_send_and_self(true, {
						round = ROUND_STATE_TIMEOUT
					})
					sRoundTimer = 0
				end
			elseif hasSeeker and timerBeforeReset > 0 then -- if seeker reconnected in game
				timerBeforeReset = 0
			end
		end
	end

	gServerSettings.nametags = displayNametags == 1 and gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE

	-- Force several camera configs
	camera_config_enable_collisions(true)
	rom_hack_cam_set_collisions(1)
	camera_romhack_set_zoomed_in_dist(900)
	camera_romhack_set_zoomed_out_dist(1400)
	camera_romhack_set_zoomed_in_height(300)
	camera_romhack_set_zoomed_out_height(450)
end

local function screen_transition(trans)
	-- if the local player died next to a seeker, make them a seeker
	local s = gPlayerSyncTable[0]
	if not s.seeking then
		for i = 1, (MAX_PLAYERS - 1) do
			if gNetworkPlayers[i].connected and gNetworkPlayers[i].currLevelNum == np.currLevelNum and
				gNetworkPlayers[i].currActNum == np.currActNum and gNetworkPlayers[i].currAreaIndex == np.currAreaIndex
				and gPlayerSyncTable[i].seeking then
				local m = gMarioStates[0]
				local a = gMarioStates[i]

				if (trans == WARP_TRANSITION_FADE_INTO_BOWSER or (m.floor and m.floor.type == SURFACE_DEATH_PLANE and m.pos.y <= m.floorHeight + 2048))
					and dist_between_objects(m.marioObj, a.marioObj) <= 4000 and m.playerIndex == 0 then
					s.seeking = true

					network_send_and_self(false, {
						from = np.name
					})
				end
			end
		end
	end
end

--- @param m MarioState
local function mario_update(m)
	-- this code runs for all players
	local s = gPlayerSyncTable[m.playerIndex]

	-- display all seekers as metal
	if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and s.seeking then
		m.marioBodyState.modelState = m.marioBodyState.modelState | MODEL_STATE_METAL
	end

	if m.playerIndex ~= 0 then return end
	-- for local user only

	-- reset camera cutscene and velocity
	if m.area.camera.cutscene == CUTSCENE_EXIT_PAINTING_SUCC
		or m.area.camera.cutscene == CUTSCENE_EXIT_SPECIAL_SUCC
		or m.area.camera.cutscene == CUTSCENE_EXIT_BOWSER_SUCC then
		m.area.camera.cutscene = 0
		m.forwardVel = 0
	end

	-- displaying custom health
	if m.health > 0x7FF and m.health >= healthPrev and healthTimer < 45 then
		healthTimer = healthTimer + 1
	elseif m.health <= 0x7FF or m.health < healthPrev then
		healthTimer = 0
	end

	healthShow = healthTimer < 45
	healthPrev = m.health

	if not s.seeking and seekerIsOut then
		seekerIsOut = false
	end

	if network_is_server() and (m.controller.buttonDown & L_TRIG) ~= 0 and (m.controller.buttonDown & START_BUTTON) ~= 0 and not isMenuOpen and not is_game_paused() then
		isMenuOpen = true
		menuSelection = gGlobalSyncTable.selectArea
		play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, m.marioObj.header.gfx.cameraToObject)
	end

	-- selection levels in menu custom
	if isMenuOpen then
		local nbLevels = #HnS.titles
		m.freeze = 1

		if (m.controller.buttonPressed & U_JPAD) ~= 0 or (not inSelection and m.controller.stickY >= 60) then
			menuSelection = menuSelection - 1
			inSelection = true

			if menuSelection < 1 then
				menuSelection = 1
			else
				play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, m.marioObj.header.gfx.cameraToObject)
			end
		elseif (m.controller.buttonPressed & D_JPAD) ~= 0 or (not inSelection and m.controller.stickY <= -60) then
			menuSelection = menuSelection + 1
			inSelection = true

			if menuSelection > nbLevels then
				menuSelection = nbLevels
			else
				play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, m.marioObj.header.gfx.cameraToObject)
			end
		end
		if (m.controller.buttonPressed & A_BUTTON) ~= 0 then
			if network_player_connected_count() > 1 then
				isMenuOpen = false
				start_round()
			else
				djui_chat_message_create("\\#f00000\\You must be at least 2 players.")
				play_sound(SOUND_MENU_CAMERA_BUZZ, m.marioObj.header.gfx.cameraToObject)
			end
		end
		if (m.controller.buttonPressed & B_BUTTON) ~= 0 or (m.controller.buttonDown & START_BUTTON) ~= 0 and not inSelection then
			isMenuOpen = false
		end
		if m.controller.stickY > -60 and m.controller.stickY < 60 and (m.controller.buttonDown & START_BUTTON) == 0 then
			inSelection = false
		end

		if (m.controller.buttonDown & START_BUTTON) ~= 0 then
			inSelection = true
		end

		m.controller.buttonPressed = 0
	end

	if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and m.action == ACT_IN_CANNON and m.actionState == 2 then
		cannonTimer = cannonTimer + 1
		if cannonTimer >= 150 then -- 5 seconds
			m.forwardVel = 100 * coss(m.faceAngle.x)
			m.vel.y = 100 * sins(m.faceAngle.x)

			m.pos.x = m.pos.x + 120 * coss(m.faceAngle.x) * sins(m.faceAngle.y)
			m.pos.y = m.pos.y + 120 * sins(m.faceAngle.x)
			m.pos.z = m.pos.z + 120 * coss(m.faceAngle.x) * coss(m.faceAngle.y)

			play_sound(SOUND_ACTION_FLYING_FAST, m.marioObj.header.gfx.cameraToObject)
			play_sound(SOUND_OBJ_POUNDING_CANNON, m.marioObj.header.gfx.cameraToObject)

			m.marioObj.header.gfx.node.flags = m.marioObj.header.gfx.node.flags | GRAPH_RENDER_ACTIVE

			set_camera_mode(m.area.camera, m.area.camera.defMode, 1)
			set_mario_action(m, ACT_SHOT_FROM_CANNON, 0)
			queue_rumble_data_mario(m, 60, 70)
			m.usedObj.oAction = 2
			cannonTimer = 0
		end
	elseif cannonTimer > 0 then
		cannonTimer = 0
	end

	-- warp to the beginning
	if teleported == false then
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, 0)
		m.health = 0x880
		m.specialTripleJump = 0
		teleported = true
	end

	m.numLives = 100

	-- pu prevention
	if m.playerIndex == 0 and (m.pos.x > 0x7FFF or m.pos.x < -0x8000 or m.pos.z > 0x7FFF or m.pos.z < -0x8000) then
		warp_restart_level()
	end

	if gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE then return end

	-- teleport seeker out of the castle, time to hiders to hide
	if s.seeking and gGlobalSyncTable.tickTimer < gGlobalSyncTable.timeToHide then
		seekerIsOut = true

		if np.currLevelNum ~= LEVEL_CASTLE_GROUNDS then
			warp_to_level(LEVEL_CASTLE_GROUNDS, 1, 0)
		end
	elseif s.seeking and gGlobalSyncTable.tickTimer >= gGlobalSyncTable.timeToHide and seekerIsOut then
		-- teleport seeker in the castle when timer is started
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, 0)
		seekerIsOut = false
		m.health = 0x880
	elseif (np.currAreaIndex ~= gGlobalSyncTable.selectArea and np.currLevelNum == gGlobalSyncTable.selectLevel)
		or (gGlobalSyncTable.selectArea == 2 and np.currLevelNum == LEVEL_CASTLE_GROUNDS)
		or (gGlobalSyncTable.selectArea ~= 3 and np.currLevelNum == LEVEL_VCUTM)
		or np.currActNum == 99 then
		-- force stage castle if is from different stage
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, 0)
	end

	if not isTimeDisplayed and gGlobalSyncTable.tickTimer >= gGlobalSyncTable.timeToHide then
		isTimeDisplayed = true

		if s.seeking then
			djui_chat_message_create("It's time! Try to search and catch hiders \\#f0f000\\:pikario:")
		else
			djui_chat_message_create("It's time! The seeker will catch you \\#f0f000\\:pikario:")
		end

		play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, m.marioObj.header.gfx.cameraToObject)
	elseif isTimeDisplayed and gGlobalSyncTable.tickTimer < gGlobalSyncTable.timeToHide then
		isTimeDisplayed = false
	end
end

---@param m MarioState
---@param action integer
local function before_set_mario_action(m, action)
	if m.playerIndex == 0 then
		if action == ACT_EXIT_LAND_SAVE_DIALOG then
			return ACT_IDLE
		end
	end
end

--- @param m MarioState
local function before_phys_step(m)
	-- prevent physics from being altered when bubbled
	local s = gPlayerSyncTable[m.playerIndex]

	if m.action == ACT_BUBBLED or s.seeking then return end
end

local function on_pvp_attack(attacker, victim)
	-- this code runs when a player attacks another player
	local sAttacker = gPlayerSyncTable[attacker.playerIndex]
	local sVictim = gPlayerSyncTable[victim.playerIndex]

	-- make victim a seeker
	if victim.playerIndex == 0 and sAttacker.seeking and not sVictim.seeking then
		network_send_and_self(false, {
			attackedBy = gNetworkPlayers[attacker.playerIndex].name,
			from = gNetworkPlayers[victim.playerIndex].name
		})

		sVictim.seeking = true
	end
end

--- @param m MarioState
local function on_player_connected(m)
	-- start out as a seeker
	local s = gPlayerSyncTable[m.playerIndex]
	local n = gNetworkPlayers[m.playerIndex]

	s.seeking = true
	network_player_set_description(gNetworkPlayers[m.playerIndex], "seeker", 255, 64, 64, 255)

	if clientInitialized then
		djui_chat_message_create("\\#1c1c1c\\[\\#00ff00\\+\\#1c1c1c\\] \\#ffff50\\" .. n.name .. " connected")
	end
end

--- @param m MarioState
local function on_player_disconnected(m)
	local n = gNetworkPlayers[m.playerIndex]

	djui_chat_message_create("\\#1c1c1c\\[\\#ff0000\\-\\#1c1c1c\\] \\#ffff50\\" .. n.name .. " disconnected")

	if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		local hasSeeker = false
		for i = 0, (MAX_PLAYERS - 1) do
			if gNetworkPlayers[i].connected and gPlayerSyncTable[i].seeking then
				hasSeeker = true
			end
		end

		if not hasSeeker and #players_list() >= 2 then
			djui_chat_message_create("\\#f00000\\No seeker detected! Game will be terminated if they do not rejoin within the next " .. math_floor(ticksToReset / 30) .. " seconds!")
		end
	end
end

local function hud_top_render()
	if np.currActNum == 99 then return end

	djui_hud_set_resolution(RESOLUTION_DJUI)

	local text = ""
	local hideState = false

	if gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
		text = "Waiting for players"
	elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		local sec = math_floor(gGlobalSyncTable.tickTimer / 30)
		local secLeft = math_floor(gGlobalSyncTable.timeToHide / 30)

		if sec < secLeft then
			local seconds = secLeft - sec

			if seconds > 1 then
				text = seconds .. " seconds left to hide"
			else
				text = seconds .. " second left to hide"
			end

			hideState = true
		else
			local seconds = (sec - secLeft) % 60
			local minutes = math_floor((sec - secLeft) / 60)

			local strSeconds = tostring(seconds)
			local strMinutes = tostring(minutes)

			if seconds < 10 then strSeconds = "0" .. seconds end
			if minutes < 10 then strMinutes = "0" .. minutes end

			text = strMinutes .. ":" .. strSeconds
		end
	else
		text = "Game will start soon..."
	end

	-- get width of screen and text
	local scale = 2
	local y = 0

	if is_game_paused() then
		scale = 1
		y = 50
	end

	local screenWidth = djui_hud_get_screen_width()
	local width = djui_hud_measure_text(text) * scale

	local x = (screenWidth - width) / 2

	-- render top
	djui_hud_set_font(FONT_NORMAL)
	if not is_game_paused() then
		djui_hud_set_color(0, 0, 0, 255)
		djui_hud_print_text(text, x + 4, y + 4, scale)
	end

	if hideState == true then
		djui_hud_set_color(255, 200, 200, 255)
	else
		djui_hud_set_color(255, 255, 255, 255)
	end
	djui_hud_print_text(text, x, y, scale)
end

local function hud_seeker_render()
	if gPlayerSyncTable[0].seeking and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and np.currActNum ~= 99 then
		local text = "You are seeker"

		local scale = 0.4
		local screenWidth = djui_hud_get_screen_width()
		local screenHeight = djui_hud_get_screen_height()
		local width = djui_hud_measure_text(text) * scale

		local x = (screenWidth - width) * 0.5
		local y = screenHeight - 14

		djui_hud_set_font(FONT_RECOLOR_HUD)
		djui_hud_set_color(255, 50, 50, 255)
		djui_hud_print_text(text, x, y, scale)
	end
end

local function hud_center_render()
	djui_hud_set_resolution(RESOLUTION_N64)

	if gGlobalSyncTable.tickTimer > 90 or isMenuOpen then return end

	-- set text
	local texts = { "" }

	if gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN then
		texts = {
			"All hiders",
			"have been found!"
		}
	elseif gGlobalSyncTable.roundState == ROUND_STATE_TIMEOUT then
		texts = { "Game end!" }
	elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		if seekerIsOut then
			texts = {
				"You are seeker!",
				"Please wait outside"
			}
		else
			texts = { "Here we go!" }
		end
	end

	local texts_count = #texts

	-- get width of screen and text
	local screenWidth = djui_hud_get_screen_width()
	local screenHeight = djui_hud_get_screen_height()
	local height = 32

	local y = (screenHeight - height) * 0.5 - ((texts_count - 1) * 8)

	-- render
	for i = 1, texts_count do
		local width = djui_hud_measure_text(texts[i])
		local x = (screenWidth - width) * 0.5

		djui_hud_set_font(FONT_HUD)
		djui_hud_set_color(255, 255, 255, 255)
		djui_hud_print_text(texts[i], x, y, 1)

		y = y + 16
	end
end

local function hud_timers_cap_render()
	if np.currActNum == 99 or gMarioStates[0].capTimer == 0 or cannonTimer > 0 then return end

	local text = string.format("CAP %.1f", gMarioStates[0].capTimer / 30)

	local screenWidth = djui_hud_get_screen_width()
	local screenHeight = djui_hud_get_screen_height()
	local size = 0.7

	djui_hud_set_font(FONT_HUD)
	djui_hud_set_color(255, 255, 255, 255)
	djui_hud_print_text(text, screenWidth - (djui_hud_measure_text(text) * size) - 24, screenHeight - 16, size)
end

local function hud_cannon_render()
	if cannonTimer == 0 then return end

	local text = string.format("You will be launched from the cannon in %d seconds", 5 - math_floor(cannonTimer / 30))
	local size = 0.45

	djui_hud_set_font(FONT_NORMAL)
	djui_hud_set_color(255, 255, 255, 255)
	djui_hud_print_text(text, (djui_hud_get_screen_width() / 2) - (djui_hud_measure_text(text) * size / 2), djui_hud_get_screen_height() - 32, size)
end

local function hud_vanilla_edit()
	if np.currActNum == 99 then return end

	if healthShow then
		if healthPos.x < 16 then healthPos.x = healthPos.x + 8 end
	else
		if healthPos.x > -64 then healthPos.x = healthPos.x - 8 end
	end

	djui_hud_set_color(255, 255, 255, 255)
	hud_set_value(HUD_DISPLAY_FLAGS, hud_get_value(HUD_DISPLAY_FLAGS) & ~(HUD_DISPLAY_FLAG_LIVES | HUD_DISPLAY_FLAG_STAR_COUNT | HUD_DISPLAY_FLAG_COIN_COUNT | HUD_DISPLAY_FLAG_POWER))

	if healthPos.x >= -64 then
		hud_render_power_meter_interpolated(gMarioStates[0].health, healthPos.prevX, 8, 64, 64, healthPos.x, 8, 64, 64)
	end

	if np.currLevelNum ~= LEVEL_CASTLE and np.currLevelNum ~= LEVEL_CASTLE_GROUNDS and np.currLevelNum ~= LEVEL_CASTLE_COURTYARD then
		local width = djui_hud_get_screen_width()
		djui_hud_set_font(FONT_HUD)
		djui_hud_render_texture(gTextures.coin, width - 74, 8, 1, 1)
		djui_hud_print_text("=", width - 58, 8, 1)
		djui_hud_print_text(tostring(gMarioStates[0].numCoins), width - 44, 8, 1)
	end

	healthPos.prevX = healthPos.x
end

local function select_level_render()
	djui_hud_set_resolution(RESOLUTION_N64)

	if not isMenuOpen then return end

	local title = "SELECT LEVEL"

	local screenWidth = djui_hud_get_screen_width()
	local screenHeight = djui_hud_get_screen_height()
	local size = 0.7

	local textWidth = djui_hud_measure_text(title)
	local titleX = (screenWidth / 2) - (textWidth / 2)

	djui_hud_set_font(FONT_HUD)
	djui_hud_set_color(255, 255, 255, 255)
	djui_hud_print_text(title, titleX, 40, 1)

	local x = (screenWidth / 2)
	local y = (screenHeight / 2) - 50

	local levelNameSizeMax = 0
	for i = 1, #HnS.titles do
		local sizeName = djui_hud_measure_text(HnS.titles[i]) * size
		if sizeName > levelNameSizeMax then
			levelNameSizeMax = sizeName
		end
	end

	djui_hud_set_font(FONT_RECOLOR_HUD)

	x = x - (levelNameSizeMax / 2)

	for i = 1, #HnS.titles do
		if menuSelection == i then
			local sin = math_sin(sRoundTimer / 2) * 15

			djui_hud_set_color(sin + 240, sin + 150, sin + 150, 255)
		else
			djui_hud_set_color(100, 50, 50, 255)
		end

		djui_hud_print_text(HnS.titles[i], x, y, size)
		y = y + 16
	end
end

local function on_start_command()
	isMenuOpen = true
	menuSelection = gGlobalSyncTable.selectArea

	return true
end

local function on_reset_command()
	network_send_and_self(true, {
		round = ROUND_STATE_RESETING
	})
	sRoundTimer = 0
	seekerSelected = -1
	playersExcluded = {}

	for i = 0, (MAX_PLAYERS - 1) do
		gPlayerSyncTable[i].seeking = true
	end

	return true
end

local function on_define_seeker_command(argument)
	if argument == "" then
		djui_chat_message_create("Argument must be: \\#a0a0a0\\/seeker PLAYER_NAME|ID")
		return true
	end

	for i = 0, (MAX_PLAYERS - 1) do
		local player = gNetworkPlayers[i]

		if player.connected and (player.name == argument or player.globalIndex == tonumber(argument)) and player.name ~= "" then
			seekerSelected = player.globalIndex
			djui_chat_message_create("\\#ff9090\\" .. player.name .. " \\#ffffff\\will be the seeker in the next round (\\#a0a0a0\\/start\\#ffffff\\ to start the round)")
			return true
		end
	end

	djui_chat_message_create("\\#f00000\\Player (or ID) \\#ff9090\\" .. argument .. " \\#f00000\\ does not exist")
	return true
end

local function on_change_timer_command(argument)
	if argument == "" then
		djui_chat_message_create("Argument must be: \\#a0a0a0\\/timer SECONDS")
		return true
	end

	local number = tonumber(argument)

	if number ~= nil then
		if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
			djui_chat_message_create("\\#f00000\\Round is already started! Please do \\#f06060\\/reset\\#f00000\\ before doing this command")
			return true
		end

		gGlobalSyncTable.timeToHide = number * 30
		djui_chat_message_create("You have set the timer for hiders to \\#f06060\\" .. number .. "\\#ffffff\\ seconds")
	else
		djui_chat_message_create("\\#ff9090\\" .. argument .. " \\#f00000\\is not a number")
	end

	return true
end

local function on_pause_exit()
	return gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE or gPlayerSyncTable[0].seeking
end

-----------------------
-- network callbacks --
-----------------------

local function on_round_state_changed(_, oldVal, newVal)
	if oldVal == newVal then return end

	if gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN or gGlobalSyncTable.roundState == ROUND_STATE_TIMEOUT then
		play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
	elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		local npT

		for i = 0, (MAX_PLAYERS - 1) do
			if gNetworkPlayers[i].connected and gPlayerSyncTable[i].seeking then
				npT = gNetworkPlayers[i]
				break
			end
		end

		djui_chat_message_create("\\#a0ffa0\\Game started!")
		djui_chat_message_create("\\#ffa0a0\\" .. npT.name .. " was selected as seeker!")

		isTimeDisplayed = true
		teleported = false
	elseif gGlobalSyncTable.roundState == ROUND_STATE_RESETING then
		djui_chat_message_create("\\#ffa0a0\\Game has been stopped and reset!")
	end
end

local function on_seeking_changed(tag, oldVal, newVal)
	local m = gMarioStates[tag]
	local npT = gNetworkPlayers[tag]

	-- if became a seeker
	if clientInitialized and npT.connected and newVal and not oldVal then
		local nbHiders = 0

		for i = 0, (MAX_PLAYERS - 1) do
			if gNetworkPlayers[i].connected and not gPlayerSyncTable[i].seeking then
				nbHiders = nbHiders + 1
			end
		end

		if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
			play_sound(SOUND_MENU_MESSAGE_APPEAR, m.marioObj.header.gfx.cameraToObject)

			if nbHiders > 1 then
				djui_chat_message_create(nbHiders .. " hiders left")
			elseif nbHiders == 1 then
				djui_chat_message_create(nbHiders .. " hider left")
			else
				djui_chat_message_create("\\#a0ffa0\\All hiders have been found!")
			end
		end
	end

	if newVal then
		network_player_set_description(npT, "seeker", 255, 64, 64, 255)
	else
		network_player_set_description(npT, "hider", 128, 128, 128, 255)
	end
end

local function allow_pvp_attack(m1, m2)
	if gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE then
		return true
	end

	if gGlobalSyncTable.tickTimer < gGlobalSyncTable.timeToHide then
		return false
	end

	local s1 = gPlayerSyncTable[m1.playerIndex]
	local s2 = gPlayerSyncTable[m2.playerIndex]

	return s1.seeking ~= s2.seeking
end

--- HOOKS
hook_event(HOOK_UPDATE, update)
hook_event(HOOK_ON_SCREEN_TRANSITION, screen_transition)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, before_set_mario_action)
hook_event(HOOK_MARIO_UPDATE, mario_update)
hook_event(HOOK_BEFORE_PHYS_STEP, before_phys_step)
hook_event(HOOK_ALLOW_PVP_ATTACK, allow_pvp_attack)
hook_event(HOOK_ON_PVP_ATTACK, on_pvp_attack)
hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)
hook_event(HOOK_ON_PLAYER_DISCONNECTED, on_player_disconnected)
hook_event(HOOK_ON_HUD_RENDER, function()
	hud_top_render()
	hud_center_render()
	hud_cannon_render()
	select_level_render()
end)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, function()
	djui_hud_set_resolution(RESOLUTION_N64)

	hud_seeker_render()
	hud_timers_cap_render()
	hud_vanilla_edit()
end)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit)
hook_event(HOOK_USE_ACT_SELECT, function() return false end)
hook_event(HOOK_ON_PACKET_RECEIVE, on_packet_receive)
hook_event(HOOK_ON_SYNC_VALID, function()
	clientInitialized = true
end)
hook_event(HOOK_ON_LEVEL_INIT, function()
	-- 100% save file
	if not save_file_get_using_backup_slot() then
		save_file_set_using_backup_slot(true)
		local file = get_current_save_file_num() - 1

		for course = 0, COURSE_MAX - 1 do
			save_file_set_star_flags(file, course, 0xFF)
		end

		save_file_set_flags(0xFFFFFFFF)
		gMarioStates[0].numStars = COURSE_MAX * 7 + 7
	end
end)

if network_is_server() then
	hook_chat_command("start", "Start or restart round", on_start_command)
	hook_chat_command("seeker", "Set a player as seeker before the next round", on_define_seeker_command)
	hook_chat_command("reset", "Stop round", on_reset_command)
	hook_chat_command("timer", "Change timer for hiders", on_change_timer_command)
end

-- call functions when certain sync table values change
hook_on_sync_table_change(gGlobalSyncTable, "roundState", nil, on_round_state_changed)

for i = 0, (MAX_PLAYERS - 1) do
	gPlayerSyncTable[i].seeking = true
	hook_on_sync_table_change(gPlayerSyncTable[i], "seeking", i, on_seeking_changed)
	network_player_set_description(gNetworkPlayers[i], "seeker", 255, 64, 64, 255)
end

if network_is_server() then
	clientInitialized = true
end