-- name: Hide'n Seek
-- incompatible: gamemode
-- description: A hide and seek modified :D\n\n\\#dcdcdc\\Concept by \\#00f000\\Super Keeberghrh\n\\#dcdcdc\\Modified by \\#f0f000\\GuiguiBlocCraft

if VERSION_NUMBER < 37 then
	print("[HnS] Version " .. VERSION_NUMBER .. " is lower than 37.")
	djui_popup_create("\\#f00000\\You must use \\#f0f000\\CoopDX 1.0 or more\\#f00000\\ to use this mod.", 3)
	return 0
end

-- constants
local ROUND_STATE_WAIT        = 0
local ROUND_STATE_ACTIVE      = 1
local ROUND_STATE_SEEKERS_WIN = 2
local ROUND_STATE_RESETING    = 3
local ROUND_STATE_UNKNOWN_END = 4

-- globals
gGlobalSyncTable.roundState = ROUND_STATE_WAIT -- current round state
gGlobalSyncTable.hiderCaps = false
gGlobalSyncTable.seekerCaps = false
gGlobalSyncTable.banKoopaShell = false
gGlobalSyncTable.disableBLJ = false
gGlobalSyncTable.tickTimer = 0 -- 30 tick per second
gGlobalSyncTable.selectLevel = LEVEL_CASTLE
gGlobalSyncTable.selectArea = 1
gGlobalSyncTable.timeToHide = 60 * 30
djui_set_popup_disabled_override(true)

-- variables
local np = gNetworkPlayers[0]
local clientInitialized = false
local displayNametags = gServerSettings.nametags
local sRoundTimer = 0
local cannonTimer = 0
local seekerIsOut = false
local seekerSelected = -1
local capDuration = 0
local itsTimeDisplayed = false
local playersExcluded = {}
local isMenuOpen = false
local menuSelection = 1
local inSelection = false
local advertPU = false
local puX = 0
local puZ = 0

HnS = {}
HnS.titles = {
	"Castle Main Floor",
	"Castle Upper Floor",
	"Castle Basement"
}
HnS.levels = {
	{LEVEL_CASTLE, 1},
	{LEVEL_CASTLE, 2},
	{LEVEL_CASTLE, 3}
}

-- server settings
gServerSettings.bubbleDeath = 0
gServerSettings.skipIntro = 1
gServerSettings.pauseAnywhere = 0
gServerSettings.playerInteractions = PLAYER_INTERACTIONS_SOLID
gLevelValues.disableActs = true
gLevelValues.zoomOutCameraOnPause = false

-- Remove all names
for i = 0, COURSE_MAX - 1 do
	smlua_text_utils_course_name_replace(i, "Level Hidden")
end

-- localize functions to improve performance
local
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server, hook_event, play_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font, djui_hud_set_color, djui_hud_render_rect, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height, djui_hud_measure_text, warp_to_level, stop_cap_music, dist_between_objects, math_floor, math_ceil, math_sin, table_insert, set_camera_mode =
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server, hook_event, play_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font, djui_hud_set_color, djui_hud_render_rect, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height, djui_hud_measure_text, warp_to_level, stop_cap_music, dist_between_objects, math.floor, math.ceil, math.sin, table.insert, set_camera_mode

local function on_or_off(value)
	if value then return "enabled" end
	return "disabled"
end

local function players_list()
	local activePlayers = {}

	for i = 0, (MAX_PLAYERS-1) do
		if gNetworkPlayers[i].connected then
			table_insert(activePlayers, gPlayerSyncTable[i])
		end
	end

	return activePlayers
end

local function start_round()
	gGlobalSyncTable.selectLevel = HnS.levels[menuSelection][1]
	gGlobalSyncTable.selectArea = HnS.levels[menuSelection][2]

	-- reset seekers
	for i=0,(MAX_PLAYERS-1) do
		gPlayerSyncTable[i].seeking = false
		gPlayerSyncTable[i].isTeleported = false
	end

	-- pick random seeker
	local playerSelected = 0
	local playersList = players_list()

	if #playersExcluded >= #playersList then
		playersExcluded = {}
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
		gGlobalSyncTable.roundState = ROUND_STATE_WAIT
	end

	playersList[playerSelected].seeking = true

	gGlobalSyncTable.roundState = ROUND_STATE_ACTIVE
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

		for i = 0, (MAX_PLAYERS-1) do
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
			gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
			sRoundTimer = 0
		end

		-- check to see if the round should end
		if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
			if not hasHider then
				gGlobalSyncTable.roundState = ROUND_STATE_SEEKERS_WIN
				sRoundTimer = 0
			elseif not hasSeeker then
				gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
				sRoundTimer = 0
			end
		end
	end

	gServerSettings.nametags = displayNametags == 1 and gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE

	if not clientInitialized and np.currAreaSyncValid then
		clientInitialized = true
	end
end

local function screen_transition(trans)
	-- if the local player died next to a seeker, make them a seeker
	local s = gPlayerSyncTable[0]
	if not s.seeking then
		for i=1,(MAX_PLAYERS-1) do
			if gNetworkPlayers[i].connected and gNetworkPlayers[i].currLevelNum == np.currLevelNum and
				gNetworkPlayers[i].currActNum == np.currActNum and gNetworkPlayers[i].currAreaIndex == np.currAreaIndex
				and gPlayerSyncTable[i].seeking then

				local m = gMarioStates[0]
				local a = gMarioStates[i]

				if (trans == WARP_TRANSITION_FADE_INTO_BOWSER or (m.floor and m.floor.type == SURFACE_DEATH_PLANE and m.pos.y <= m.floorHeight + 2048))
					and dist_between_objects(m.marioObj, a.marioObj) <= 4000 and m.playerIndex == 0 then
						s.seeking = true
				end
			end
		end
	end
end

--- @param m MarioState
local function mario_update(m)
	if gGlobalSyncTable.disableBLJ and m.forwardVel <= -55 then
		m.forwardVel = -55
	end

	-- this code runs for all players
	local s = gPlayerSyncTable[m.playerIndex]

	-- display all seekers as metal
	if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and s.seeking then
		m.marioBodyState.modelState = m.marioBodyState.modelState | MODEL_STATE_METAL
	end

	if m.playerIndex ~= 0 then return end
	-- for local user only

	if not s.seeking and seekerIsOut then
		seekerIsOut = false
	end

	if network_is_server() and (m.controller.buttonDown & L_TRIG) ~= 0 and (m.controller.buttonDown & START_BUTTON) ~= 0 and not isMenuOpen then
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

	capDuration = m.capTimer

	if m.action == ACT_IN_CANNON and m.actionState == 2 then
		cannonTimer = cannonTimer + 1
		if cannonTimer >= 150 then -- 150 is 5 seconds
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

	-- remove caps
	if gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE
		and ((gGlobalSyncTable.seekerCaps and s.seeking)
			or (gGlobalSyncTable.hiderCaps and not s.seeking)) then
				m.flags = m.flags & ~MARIO_WING_CAP -- remove wing cap if seeking/hiding
				m.flags = m.flags & ~MARIO_METAL_CAP -- remove metal cap if seeking/hiding
				stop_cap_music()
				m.capTimer = 0
	end

	-- warp to the beninging
	if s.isTeleported == false then
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, np.currActNum)
		m.health = 0x880
		m.specialTripleJump = 0
		s.isTeleported = true
	end

	m.numLives = 99

	-- pu prevention
	if m.pos.x >= 0 then
		puX = math_floor((8192 + m.pos.x) / 65536)
	else
		puX = math_ceil((-8192 + m.pos.x) / 65536)
	end
	if m.pos.z >= 0 then
		puZ = math_floor((8192 + m.pos.z) / 65536)
	else
		puZ = math_ceil((-8192 + m.pos.z) / 65536)
	end
	if puX ~= 0 or puZ ~= 0 then
		m.health = 0
		advertPU = true
	else
		advertPU = false
	end

	if gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE then return end

	-- teleport seeker out of the castle, time to hiders to hide
	if s.seeking and gGlobalSyncTable.tickTimer < gGlobalSyncTable.timeToHide then
		seekerIsOut = true

		if np.currLevelNum ~= LEVEL_CASTLE_GROUNDS then
			warp_to_level(LEVEL_CASTLE_GROUNDS, 1, np.currActNum)
		end
	elseif s.seeking and gGlobalSyncTable.tickTimer >= gGlobalSyncTable.timeToHide and seekerIsOut then
		-- teleport seeker in the castle when timer is started
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, np.currActNum)
		seekerIsOut = false
		m.health = 0x880
	elseif np.currAreaIndex ~= gGlobalSyncTable.selectArea and np.currLevelNum == gGlobalSyncTable.selectLevel
		or (gGlobalSyncTable.selectArea == 2 and np.currLevelNum == LEVEL_WMOTR)
		or (gGlobalSyncTable.selectArea ~= 3 and np.currLevelNum == LEVEL_VCUTM) then
		-- force stage castle if is from different stage
		warp_to_level(gGlobalSyncTable.selectLevel, gGlobalSyncTable.selectArea, np.currActNum)
	end

	if not itsTimeDisplayed and gGlobalSyncTable.tickTimer >= gGlobalSyncTable.timeToHide then
		itsTimeDisplayed = true

		if s.seeking then
			djui_chat_message_create("It's time! Try to search and catch hiders \\#f0f000\\:pikario:")
		else
			djui_chat_message_create("It's time! Seeker will catch you \\#f0f000\\:pikario:")
		end

		play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, m.marioObj.header.gfx.cameraToObject)
	elseif itsTimeDisplayed and gGlobalSyncTable.tickTimer < gGlobalSyncTable.timeToHide then
		itsTimeDisplayed = false
	end
end

---@param m MarioState
---@param action integer
local function before_set_mario_action(m, action)
	if m.playerIndex == 0 then
		if action == ACT_EXIT_LAND_SAVE_DIALOG then
			set_camera_mode(m.area.camera, m.area.camera.defMode, 1)
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
		local nAttacker = gNetworkPlayers[attacker.playerIndex]
		djui_chat_message_create("\\#ffff50\\" .. nAttacker.name .. " catch you!")

		sVictim.seeking = true
	end
end

--- @param m MarioState
local function on_player_connected(m)
	-- start out as a seeker
	local s = gPlayerSyncTable[m.playerIndex]
	local n = gNetworkPlayers[m.playerIndex]

	s.seeking = true
	s.isTeleported = true
	network_player_set_description(gNetworkPlayers[m.playerIndex], "seeker", 255, 64, 64, 255)

	if clientInitialized then
		djui_chat_message_create("\\#1c1c1c\\[\\#00ff00\\+\\#1c1c1c\\] \\#ffff50\\" .. n.name .. " connected")
	end
end

--- @param m MarioState
local function on_player_disconnected(m)
	local n = gNetworkPlayers[m.playerIndex]

	djui_chat_message_create("\\#1c1c1c\\[\\#ff0000\\-\\#1c1c1c\\] \\#ffff50\\" .. n.name .. " disconnected")
end

local function hud_top_render()
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
			local seconds = math_floor((sec - secLeft) % 60)
			local minutes = math_floor((sec - secLeft) / 60)

			if seconds < 10 then seconds = "0" .. seconds end
			if minutes < 10 then minutes = "0" .. minutes end

			text = minutes .. ":" .. seconds
		end
	else
		text = "Game will start soon..."
	end

	local scale = 2

	-- get width of screen and text
	local screenWidth = djui_hud_get_screen_width()
	local width = djui_hud_measure_text(text) * scale

	local x = (screenWidth - width) / 2
	local y = 0

	-- render top
	djui_hud_set_font(FONT_NORMAL)
	djui_hud_set_color(0, 0, 0, 128)
	if is_game_paused() then
		width = djui_hud_measure_text(text)
		scale = 1
		x = (screenWidth - width) / 2
		y = 50
	else
		djui_hud_render_rect(x - 6, y, width + 12, 32 * scale)
	end

	if hideState == true then
		djui_hud_set_color(255, 200, 200, 255)
	else
		djui_hud_set_color(255, 255, 255, 255)
	end
	djui_hud_print_text(text, x, y, scale)
end

local function hud_seeker_render()
	if gPlayerSyncTable[0].seeking and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
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

	if (gGlobalSyncTable.tickTimer > 90 and cannonTimer == 0 and not advertPU) or isMenuOpen then return end

	-- set text
	local texts = {""}

	if cannonTimer > 0 then
		texts = {
			"Camping not permitted!",
			"",
			"Ejected out of the",
			"cannon in " .. tostring(5 - math_floor(cannonTimer / 30)) .. " seconds"
		}
	elseif advertPU then
		texts = {
			"Camping in",
			"Parallel universe are",
			"not authorized!"
		}
	elseif gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN then
		texts = {
			"All hiders",
			"have been found!"
		}
	elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		if seekerIsOut then
			texts = {
				"You are seeker!",
				"Please wait outside"
			}
		else
			texts = {"Here we go!"}
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
	if capDuration == 0 then return end

	local text = string.format("CAP %.1f", capDuration / 30)

	local screenWidth = djui_hud_get_screen_width()
	local screenHeight = djui_hud_get_screen_height()
	local size = 0.7

	djui_hud_set_font(FONT_HUD)
	djui_hud_set_color(255, 255, 255, 255)
	djui_hud_print_text(text, screenWidth - (djui_hud_measure_text(text) * size) - 24, screenHeight - 16, size)
end

local function select_level_render()
	djui_hud_set_resolution(RESOLUTION_N64)

	if not isMenuOpen then return end

	local title = "SELECT LEVEL"

	local screenWidth = djui_hud_get_screen_width()
	local screenHeight = djui_hud_get_screen_height()
	local size = 0.7

	local width = djui_hud_measure_text(title)
	local titleX = (screenWidth / 2) - (width / 2)

	djui_hud_set_font(FONT_HUD)
	djui_hud_set_color(255, 255, 255, 255)
	djui_hud_print_text(title, titleX, 40, 1)

	local x = (screenWidth / 2) * size
	local y = (screenHeight / 2) * size

	levelNameSizeMax = 0
	for i = 1, #HnS.titles do
		local sizeName = djui_hud_measure_text(HnS.titles[i])
		if sizeName > levelNameSizeMax then
			levelNameSizeMax = sizeName
		end
	end

	djui_hud_set_font(FONT_RECOLOR_HUD)

	for i = 1, #HnS.titles do
		if menuSelection - 1 == i - 1 then
			djui_hud_set_color(255, 255, 255, 255)
			djui_hud_render_texture(gTextures.star, x - (20 * size), y + (10 * size), size, size)
			djui_hud_set_color(math_sin(sRoundTimer / 2) * 15 + 240, 150, 150, 255)
		else
			djui_hud_set_color(100, 50, 50, 255)
		end

		djui_hud_print_text(HnS.titles[i], x, y, size)
		y = y + 16
	end
end

local function on_hider_cap_command()
	gGlobalSyncTable.hiderCaps = not gGlobalSyncTable.hiderCaps
	djui_chat_message_create("Hider Caps: " .. on_or_off(gGlobalSyncTable.hiderCaps))
	return true
end

local function on_seeker_cap_command()
	gGlobalSyncTable.seekerCaps = not gGlobalSyncTable.seekerCaps
	djui_chat_message_create("Seeker Caps: " .. on_or_off(gGlobalSyncTable.seekerCaps))
	return true
end

local function on_koopa_shell_command()
	gGlobalSyncTable.banKoopaShell = not gGlobalSyncTable.banKoopaShell
	djui_chat_message_create("Koopa Shells: " .. on_or_off(not gGlobalSyncTable.banKoopaShell))
	return true
end

local function on_blj_command()
	gGlobalSyncTable.disableBLJ = not gGlobalSyncTable.disableBLJ
	djui_chat_message_create("BLJs: " .. on_or_off(not gGlobalSyncTable.disableBLJ))
	return true
end

local function on_start_command()
	isMenuOpen = true
	menuSelection = gGlobalSyncTable.selectArea

	return true
end

local function on_reset_command()
	gGlobalSyncTable.roundState = ROUND_STATE_RESETING
	sRoundTimer = 0
	seekerSelected = -1
	playersExcluded = {}

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
			djui_chat_message_create("Seeker will be \\#ff9090\\" .. player.name .. " \\#ffffff\\after a \\#a0a0a0\\/start\\#ffffff\\ command!")
			return true
		end
	end

	djui_chat_message_create("\\#f00000\\Player (or ID) \\#ff9090\\" .. argument .. " \\#f00000\\ is not exist")
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
		djui_chat_message_create("You have set the timer for hiders on \\#f06060\\" .. number .. "\\#ffffff\\ seconds")
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

	if gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN then
		play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
	elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
		for i = 0, (MAX_PLAYERS-1) do
			if gNetworkPlayers[i].connected and gPlayerSyncTable[i].seeking then
				local npT = gNetworkPlayers[i]

				djui_chat_message_create("\\#a0ffa0\\Game started!")
				djui_chat_message_create("\\#ffa0a0\\" .. npT.name .. " was selected as seeker!")
			end
		end

		itsTimeDisplayed = true
	elseif gGlobalSyncTable.roundState == ROUND_STATE_RESETING then
		djui_chat_message_create("\\#ffa0a0\\Game was stopped and reset!")
	end
end

local function on_seeking_changed(tag, oldVal, newVal)
	local m = gMarioStates[tag]
	local npT = gNetworkPlayers[tag]

	-- if became a seeker
	if npT.connected and newVal and not oldVal then
		local nbHiders = 0

		for i = 0, (MAX_PLAYERS-1) do
			if gNetworkPlayers[i].connected and not gPlayerSyncTable[i].seeking then
				nbHiders = nbHiders + 1
			end
		end

		if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
			play_sound(SOUND_MENU_MESSAGE_APPEAR, m.marioObj.header.gfx.cameraToObject)

			if nbHiders > 1 then
				djui_chat_message_create(npT.name .. " is now a seeker (" .. nbHiders .. " hiders left)")
			elseif nbHiders == 1 then
				djui_chat_message_create(npT.name .. " is now a seeker (" .. nbHiders .. " hider left)")
			else
				djui_chat_message_create(npT.name .. " is now a seeker")
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

local function allow_interact(_, _, intee)
	if intee == INTERACT_KOOPA_SHELL and gGlobalSyncTable.banKoopaShell then
		return false
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

-----------
-- hooks --
-----------

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
	select_level_render()
end)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, function()
	djui_hud_set_resolution(RESOLUTION_N64)

	hud_seeker_render()
	hud_timers_cap_render()
end)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit)
hook_event(HOOK_ALLOW_INTERACT, allow_interact)
hook_event(HOOK_USE_ACT_SELECT, function() return false end)

if network_is_server() then
	hook_chat_command("start", "Start or restart round", on_start_command)
	hook_chat_command("seeker", "Define a seeker before \\#a0a0a0\\/start\\#ffffff\\ command", on_define_seeker_command)
	hook_chat_command("reset", "Stop round", on_reset_command)
	hook_chat_command("timer", "Change timer for hiders", on_change_timer_command)
	hook_chat_command("hiders-caps", "Turn caps for hiders on or off", on_hider_cap_command)
	hook_chat_command("seekers-caps", "Turn caps for seekers on or off", on_seeker_cap_command)
	hook_chat_command("koopa-shell", "Turn the koopa shell on or off", on_koopa_shell_command)
	hook_chat_command("bljs", "Turn bljs on or off", on_blj_command)
end

-- call functions when certain sync table values change
hook_on_sync_table_change(gGlobalSyncTable, "roundState", nil, on_round_state_changed)

for i = 0, (MAX_PLAYERS - 1) do
	gPlayerSyncTable[i].seeking = true
	hook_on_sync_table_change(gPlayerSyncTable[i], "seeking", i, on_seeking_changed)
	network_player_set_description(gNetworkPlayers[i], "seeker", 255, 64, 64, 255)
end