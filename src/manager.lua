local json = require("src/json")
local Utils = require("src/utils")

local Manager = {}

local LOGIC_EVENT_NAME = "wikisync_logic"
local GAME_STATE_EVENT_NAME = "wikisync_gamestate"

local SECONDS_BETWEEN_UPLOADS = 10
local SECONDS_BETWEEN_MANIFEST_CHECKS = 1200
local MANIFEST_URL_PATH = "/runescape/manifest"
local SUBMIT_URL_PATH = "/runescape/submit"

function Manager:init()
    self.manifest = {}
    self.oldPlayerData = Utils:newPlayerData()

    self.cyclesSinceSuccessfulCall = 0
    self.ticksSinceLastSubmissionAttempt = 0
    self.ticksSinceLastManifestCheck = 0

    self.isSubmitting = false
    self.isFetchingManifest = false

    -- Using server tick instead of client tick to reduce overhead
    Event.ServerLogic.Subscribe(LOGIC_EVENT_NAME, function()
        self.ticksSinceLastManifestCheck = self.ticksSinceLastManifestCheck + 1

        if not self.isSubmitting and self.ticksSinceLastSubmissionAttempt >= (SECONDS_BETWEEN_UPLOADS / 0.6) then
            self:DoSync()
        else
            self.ticksSinceLastSubmissionAttempt = self.ticksSinceLastSubmissionAttempt + 1
        end

        if self.ticksSinceLastManifestCheck >= (SECONDS_BETWEEN_MANIFEST_CHECKS / 0.6) then
            self.ticksSinceLastManifestCheck = 0
            self:UpdateManifest()
        end
    end)

    Event.GameStateChanged.Subscribe(GAME_STATE_EVENT_NAME, function (event)
        if event.newState == GameState.GAME then
            self:DoSync()
        end
    end)

    self:UpdateManifest()
end

-- Does the main work for gathering and submitting the data
function Manager:DoSync()
    self.ticksSinceLastSubmissionAttempt = 0

    if self.isSubmitting then
        -- Make sure that we don't keep trying to submit if we're already trying
        return
    end

    if not Player.IsAvailable() then
        return
    end

    if not self.manifest or next(self.manifest) == nil then
        log("Not submitting due to missing or invalid manifest")
        return
    end

    local username = Player.GetEntity().displayName
    local newPlayerData = self:GetPlayerData()

    Utils:subtract(newPlayerData, self.oldPlayerData)
    if Utils:playerDataIsEmpty(newPlayerData) then
        log("Doing nothing - no changes")
        return
    end

    self:SubmitData(username, 'STANDARD', newPlayerData, self.oldPlayerData)
end

-- Get the current player data
function Manager:GetPlayerData()
    local data = Utils:newPlayerData()

    missingVarps = {}
    missingVarbs = {}

    for ix, vp in ipairs(self.manifest.varps) do
        local varp = var.VarPlayer.FromID(vp)
        if not varp then
            table.insert(missingVarps, vp)
            goto continue
        end

        data.varp[tostring(vp)] = varp.value

        ::continue::
    end

    if next(missingVarps) ~= nil then
        log('Could not find requested varps: ' .. table.concat(missingVarps, ', '))
    end

    -- varbits are still VarPlayers, but in the client API, they use negative integers and are offset by one
    for ix, vb in ipairs(self.manifest.varbits) do
        new_vb = -(vb + 1)

        local varb = var.VarPlayer.FromID(new_vb)
        if not varb then
            table.insert(missingVarbs, vb)
            goto continue
        end

        data.varbit[tostring(vb)] = varb.value

        ::continue::
    end

    if next(missingVarbs) ~= nil then
        log('Could not find requested varbs: ' .. table.concat(missingVarbs, ', '))
    end

    -- Get all skill levels
    for k, v in pairs(getmetatable(SkillType).__index) do
        local skillName = k:lower():gsub("^%a", string.upper)
        if skillName == 'Hitpoints' then skillName = 'Constitution' end

        local skillLevel = Player.GetLevelUncapped(v)
        data.level[skillName] = skillLevel
    end

    return data
end

-- Actually submit the data to our endpoint
function Manager:SubmitData(username, profileType, delta, old)
    -- If cyclesSinceSuccessfulCall is not a perfect square, we should not try to submit.
    -- This gives us quadratic backoff.
    self.cyclesSinceSuccessfulCall = self.cyclesSinceSuccessfulCall + 1
    if math.sqrt(self.cyclesSinceSuccessfulCall) ^ 2 ~= self.cyclesSinceSuccessfulCall then
        return
    end

    self.isSubmitting = true

    local submission = {
        username = username,
        profile = profileType,
        data = delta
    }
    log("Attempting submission for " .. username)
    req = HTTPRequest.new(Plugin.urls.wikisync, SUBMIT_URL_PATH)
    req:AddHeader("Content-Type", "application/json")
    req:Post(json.encode(submission), function (req)
        self.isSubmitting = false

        if req.successful then
            log("Successfully submitted data")
            self.cyclesSinceSuccessfulCall = 0
            Utils:merge(old, delta)
        else
            log("Failed to submit data: response code " .. req.responseCode)
        end
    end)
end

function Manager:UpdateManifest()
    log("Fetching remote manifest")
    HTTPRequest.new(Plugin.urls.wikisync, MANIFEST_URL_PATH)
        :Get(function (req)
            if not req.successful or not req.data then
                log("Problem fetching manifest: response code " .. req.responseCode)
                return
            end

            self.manifest = json.decode(req.data)
            log("Successfully fetched manifest")
        end)
end

return Manager

