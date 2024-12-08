local core = require('content_editor.core')
local udb = require('content_editor.database')
local definitions = require('content_editor.definitions')
local utils = require('content_editor.utils')
local helpers = require('content_editor.helpers')
local typecache = require('content_editor.typecache')

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')
    local callbacks = require('content_editor.callbacks')
    local sounds = require('content_editor.features.sounds')
    -- local storage = editor.persistent_storage.get('sound_viewer', {
    --     bookmarked = {}
    -- })

    --- @class SoundContainerData
    --- @field container app.WwiseContainerApp
    --- @field gameobject via.GameObject

    local cache = { valid = nil }
    local function rescan_sound_containers()
        local containers = ce_find(':app.WwiseContainerApp')
        if not containers then return false end
        --- @cast containers app.WwiseContainerApp[]

        cache.entities = {} ---@type SoundContainerData[]
        cache.entity_names = {} ---@type string[]
        cache.userfiles = {} ---@type table<string, soundlib.SoundContainerListData>
        cache.paths = {} ---@type string[]
        for _, cont in ipairs(containers) do
            local go = cont:get_GameObject()
            cache.entities[#cache.entities+1] = {
                container = cont,
                gameobject = go
            }
            cache.entity_names[#cache.entity_names+1] = go:get_Name()--[[@as string]]

            for udl in utils.list_iterator(cont._UserDataList) do
                --- @cast udl soundlib.SoundContainerListData
                if not cache.userfiles[udl:get_Path()] then
                    cache.userfiles[udl:get_Path()] = udl
                    cache.paths[#cache.paths+1] = udl:get_Path()--[[@as string]]
                end
            end
        end

        cache.valid = true
        return true
    end

    local intervals = {}
    local function test_all_sound_triggers(gameObject, startindex, endindex)
        local soundcontainer = utils.get_gameobject_component(gameObject, 'soundlib.SoundContainer')
        local triggers = soundcontainer and soundcontainer:get_field('_TriggerInfoList')
        if triggers then
            local n, count = startindex or 0, endindex or triggers:get_Count()
            intervals[#intervals+1] = callbacks.hook_interval('UpdateBehavior', function ()
                if n >= count then return true end
                local trig = triggers[n]
                print('Triggering sound trigger ', n, trig._TriggerId)
                sounds.trigger_on_gameobject(trig._TriggerId, gameObject, nil)
                n = n + 1
            end, 2)
        end
    end

    local t_soundtriggerdata = sdk.find_type_definition('soundlib.SoundTriggerInfoListData')
    local preview_entity
    editor.define_window('sound_viewer', 'Sound viewer', function (state)
        if not cache.valid or imgui.button('Rescan data') then
            if not rescan_sound_containers() then
                imgui.text_colored('Could not find any sound data', core.get_color('error'))
                return
            end
        end

        local changed
        changed, preview_entity, state.go_filter = ui.basic.combo_filterable('Target entity', preview_entity, cache.entity_names, state.go_filter, cache.entities)
        if preview_entity then
            if imgui.button('Preview all sound triggers') then
                test_all_sound_triggers(preview_entity.gameobject)
            end
            imgui.same_line()
            if imgui.button('Stop all sounds') then
                preview_entity.container:onUnload()
                for _, intv in ipairs(intervals) do
                    callbacks.cancel_hook('UpdateBehavior', intv)
                end
                intervals = {}
            end
        end

        changed, state.userfile, state.userfile_filter = ui.basic.combo_filterable('Userfile', state.userfile, cache.paths, state.userfile_filter)
        local userfile = state.userfile and cache.userfiles[state.userfile]
        if userfile then
            local triggerlists = {}
            local selectedTrigData
            for _, item in pairs(userfile._UserDataList) do
                --- @cast item soundlib.SoundContainableUserData
                if item:get_type_definition():is_a(t_soundtriggerdata) then
                    local path = item:get_Path()--[[@as string]]
                    if imgui.small_button(path) or state.selected_trigger_data == path then
                        selectedTrigData = item
                        state.selected_trigger_data = path
                    end
                    triggerlists[#triggerlists+1] = item
                end
            end

            if selectedTrigData then
                ui.handlers.show(selectedTrigData)
            end
        end
    end)
end
