if usercontent == nil then usercontent = {} end
if usercontent.messages then return usercontent.messages end

local udb = require('content_editor.database')

local core = require('content_editor.core')

local type_guid = sdk.find_type_definition('System.Guid')
local guidParse = type_guid:get_method('Parse(System.String)')

local function parse_guid(guid_str) return guidParse:call(nil, guid_str) end

-- I'm not seeing a realistic chance of running out of IDs if we just use mData4 (uint64) as group ID and mData1 (uint32) as an in-group identifier, ignoring the 2 shorts
-- So just use the first and last parts of GUIDs for custom strings, ez and fast
-- For basegame guid overrides, use the full guid; we can compact mData1/2/3 into one int64 via bit operations, so we do two int64 table lookups instead of having to do a full :ToString() call

--- @class MessageGroupEntity : DBEntity
--- @field messages table<integer, table<integer, any>> {[m4]:{[m1 + m2<<32 + m3<<48]: string }}
--- @field next_msg_id integer

--- @class MessageGroupData : DBEntity
--- @field messages table<string, table<string, string>> {[m4]:{[m1 + m2<<32 + m3<<48]: string }}
--- @field next_msg_id integer

-- {[m4]:{[m1 + m2<<32 + m3<<48]: managed_string }}
local guid_overrides = {}

local missing_guids = {}
local editor_msg_lists = {}

--#region Core message guid utils

--- @param m1 integer int32
--- @param m2 integer int16
--- @param m3 integer int16
--- @param m4 integer int64
--- @return integer, integer
local function get_guid_ids(m1, m2, m3, m4)
    local id1 = m1 + (m2 << 32) + (m3 << 48)
    local id2 = m4
    return id1, id2
end

--- @param m1 integer int32
--- @param m2 integer int16
--- @param m3 integer int16
--- @return integer
local function get_guid_id1(m1, m2, m3)
    return m1 + (m2 << 32) + (m3 << 48)
end

--- @param guid string
--- @return integer
local function get_guid_id1_from_string(guid)
    return get_guid_id1(
        tonumber(guid:sub(1, 8), 16),
        tonumber(guid:sub(10, 13), 16),
        tonumber(guid:sub(15, 18), 16)
    )
end

--- @param guid string
--- @return integer
local function get_guid_id2_from_string(guid)
    local low = tonumber(guid:sub(20, 23), 16)
    local high = tonumber(guid:sub(25), 16) -- int48
    -- we need to flip the byte orders
    return ((low & 0xff00) >> 8) +
        ((low & 0xff) << 8) +
        ((high & 0xff0000000000) >> 24) +
        ((high & 0xff00000000) >> 8) +
        ((high & 0xff000000) << 8) +
        ((high & 0xff0000) << 24) +
        ((high & 0xff00) << 40) +
        ((high & 0xff) << 56)
end

--- @param guid string
--- @return integer, integer
local function get_ids_from_string(guid)
    return get_guid_id1_from_string(guid), get_guid_id2_from_string(guid)
end

local function ids_to_guid_str(id1, id2)
    local m1 = id1 & 0xffffffff
    local m2 = (id1 >> 32) & 0xffff
    local m3 = (id1 >> 48) & 0xffff
    -- we need to flip the byte orders for m4/m5
    local m4 = ((id2 & 0xff) << 8) + ((id2 & 0xff00) >> 8)
    local m5 = ((id2 & 0xff0000) << 24) +
        ((id2 & 0xff000000) << 8) +
        ((id2 & 0xff00000000) >> 8) +
        ((id2 & 0xff0000000000) >> 24) +
        ((id2 & 0xff000000000000) >> 40) +
        ((id2 & 0xff00000000000000) >> 56)

    return string.format('%08x-%04x-%04x-%04x-%012x', m1, m2, m3, m4, m5)
end

local function convert_guid_to_ids(str_or_guid)
    if type(str_or_guid) == 'string' then
        return get_ids_from_string(str_or_guid)
    else
        return get_guid_ids(str_or_guid.mData1, str_or_guid.mData2, str_or_guid.mData3, str_or_guid.mData4L)
    end
end

--- @param str string
--- @return boolean
local function is_valid_guid(str)
    return str:len() == 36 and pcall(parse_guid, str)
end


--- @param guid System.Guid
--- @return nil|any message Managed string pointer or nil
local function find_guid_override(guid)
    local groupId = guid.mData4L
    local o1 = guid_overrides[groupId]
    if not o1 then return nil end

    id1 = get_guid_id1(guid.mData1, guid.mData2, guid.mData3)
    local override = o1[id1]
    if override then
        return override
    end

    if guid.mData2 == 0 and guid.mData3 == 0 then
        -- custom GUIDs
        local msgGroup = udb.get_entity('message_group', groupId)
        if not msgGroup then
            local guidstr = guid:ToString()
            if not missing_guids[guidstr] then
                print('WARNING: missing message for custom guid ' .. guidstr)
                missing_guids[guidstr] = true
            end
            return nil
        end
    end
    return nil
end

--- @param message string|nil
--- @param subId integer
--- @param groupId integer
local function update_guid_override(message, subId, groupId)
    local o1 = guid_overrides[groupId]
    if not o1 then
        o1 = {}
        guid_overrides[groupId] = o1
    end
    local prevOverride = o1[subId]
    if prevOverride then
        prevOverride:force_release()
    end
    if message == nil then
        o1[subId] = nil
    else
        -- using permanent refs because just add_ref() seems to not work here (gets garbage collected) for some reason
        -- basically the first instance works fine, but if we reassign / change the string, it will get destroyed
        -- could be some managed string specific thing or maybe I'm missing something obvious
        o1[subId] = sdk.create_managed_string(message):add_ref_permanent()
    end
end

--#endregion

--- @param instance MessageGroupEntity
local function remove_linked_msgs(instance)
    -- we don't properly support leaving multiple bundles overriding the same string here
    -- if another bundle shares a guid, it'll be removed from the cache either way and deactivated until re-edited or script reset
    for id2, msgGroup in pairs(instance.messages) do
        for id1, _ in pairs(msgGroup) do
            update_guid_override(nil, id1, id2)
        end
    end
end

udb.register_entity_type('message_group', {
    export = function (instance)
        --- @cast instance MessageGroupEntity
        return { messages = instance.messages, next_msg_id = instance.next_msg_id }
    end,
    import = function (data, instance)
        --- @cast data MessageGroupData
        --- @cast instance MessageGroupEntity

        -- ensure we clean up any existing references
        if instance.messages then
            remove_linked_msgs(instance)
        end

        instance.messages = {}
        instance.next_msg_id = data.next_msg_id or 1
        local msg_list, msg_i = nil, 1
        if core.editor_enabled then
            msg_list = {}
            editor_msg_lists[data.id] = msg_list
        end
        for id2_str, msgGroup in pairs(data.messages or {}) do
            local o1 = {}
            local id2 = tonumber(id2_str) --[[@as integer]]
            instance.messages[id2] = o1
            for id1_str, msg in pairs(msgGroup) do
                local id1 = tonumber(id1_str) --[[@as integer]]
                o1[id1] = msg
                update_guid_override(msg, id1, id2)
                if msg_list then
                    msg_list[msg_i] = { ids_to_guid_str(id1, id2), msg }
                    msg_i = msg_i + 1
                end
            end
        end
    end,
    delete = function (instance)
        --- @cast instance MessageGroupEntity
        remove_linked_msgs(instance)
        return 'ok'
    end,
    generate_label = function (entity)
        return 'Message group ' .. entity.id
    end,
    insert_id_range = {10, 4294967200, 1},
    root_types = {},
})

sdk.hook(
    sdk.find_type_definition('via.gui.message'):get_method('get(System.Guid)'),
    function (args)
        local guid = sdk.to_valuetype(args[2], 'System.Guid') --- @type System.Guid
        local override = find_guid_override(guid)
        if override then
            thread.get_hook_storage().text = sdk.to_ptr(override)
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function (ret)
        return thread.get_hook_storage().text or ret
    end
)

--- @param bundle string
local function create_new_message_group(bundle)
    --- @type MessageGroupEntity
    local entity = {
        messages = {},
        next_msg_id = 1,
    }
    udb.insert_new_entity('message_group', bundle, entity)
    return entity
end

--- @param messageGroup MessageGroupEntity
--- @param text string
local function create_new_message_with_id(messageGroup, text, id1, id2)
    messageGroup.messages[id2] = messageGroup.messages[id2] or {}
    messageGroup.messages[id2][id1] = text
    udb.mark_entity_dirty(messageGroup)
    update_guid_override(text, id1, id2)
    if core.editor_enabled then
        editor_msg_lists[messageGroup.id][#editor_msg_lists[messageGroup.id]+1] = { ids_to_guid_str(id1, id2), text }
    end
end

--- @param messageGroup MessageGroupEntity
--- @param text string
local function create_new_message(messageGroup, text)
    local id1 = messageGroup.next_msg_id
    messageGroup.next_msg_id = messageGroup.next_msg_id + 1
    create_new_message_with_id(messageGroup, text, id1, messageGroup.id)
end

--- @param messageGroup MessageGroupEntity
--- @param messageGuid string|System.Guid
--- @param text string
local function add_message_override(messageGroup, messageGuid, text)
    local id1, id2 = convert_guid_to_ids(messageGuid)
    create_new_message_with_id(messageGroup, text, id1, id2)
end

if core.editor_enabled then
    local editor = require('content_editor.editor')
    local ui = require('content_editor.ui')

    editor.define_window('messages', 'Messages', function (state)
        local selectedItem = ui.editor.entity_picker('message_group', state, nil, 'Message group')
        if editor.active_bundle and imgui.button('Create new message group') then
            local grp = create_new_message_group(editor.active_bundle)
            ui.editor.set_selected_entity_picker_entity(state, 'message_group', grp)
        end

        if selectedItem then
            --- @cast selectedItem MessageGroupEntity
            imgui.spacing()
            imgui.indent(8)
            imgui.begin_rect()
            ui.editor.show_entity_metadata(selectedItem)
            if next(missing_guids) then
                if imgui.tree_node('Missing translations') then
                    for key, _ in pairs(missing_guids) do
                        imgui.text(key)
                        imgui.push_id(key)
                        if imgui.button('Add translation') then
                            local id1, id2 = get_ids_from_string(key)
                            create_new_message_with_id(selectedItem, 'New message', id1, id2)
                        end
                        imgui.pop_id()
                    end
                    imgui.tree_pop()
                end
            end

            if imgui.button('Add new message') then
                create_new_message(selectedItem, 'New message')
            end

            imgui.same_line()
            state.msg_filter = select(2, imgui.input_text('Search', state.msg_filter or ''))

            local filter = state.msg_filter ~= '' and state.msg_filter or nil
            local filter_id1, filter_id2
            if filter and is_valid_guid(filter) then
                filter_id1, filter_id2 = get_ids_from_string(filter)
            end

            local halfwidth = imgui.calc_item_width() / 2
            local changed1, changed2, newGuid, newMsg
            for i, guid_msg_pair in ipairs(editor_msg_lists[selectedItem.id] or {}) do
                local id1, id2 = get_ids_from_string(guid_msg_pair[1])
                if filter_id1 and filter_id2 then
                    if id1 ~= filter_id1 or id2 ~= filter_id2 then
                        goto continue
                    end
                elseif filter then
                    if not guid_msg_pair[2]:find(filter) then
                        goto continue
                    end
                end

                imgui.set_next_item_width(halfwidth)
                local should_remove = false
                imgui.push_id(id1)
                imgui.push_id(id2)
                changed1, newGuid = imgui.input_text('Guid', guid_msg_pair[3] or guid_msg_pair[1])
                if changed1 then guid_msg_pair[3] = newGuid end

                imgui.same_line()
                imgui.set_next_item_width(halfwidth)
                changed2, newMsg = imgui.input_text('Message', guid_msg_pair[4] or guid_msg_pair[2])
                if changed2 then guid_msg_pair[4] = newMsg end

                imgui.same_line()
                if imgui.button('Remove') then
                    should_remove = true
                end

                if guid_msg_pair[3] or guid_msg_pair[4] then
                    if imgui.button('Revert changes') then
                        guid_msg_pair[3] = nil
                        guid_msg_pair[4] = nil
                    end
                    imgui.same_line()
                    local guid_is_invalid = guid_msg_pair[3] and not is_valid_guid(newGuid)
                    if imgui.button('Confirm change') and not guid_is_invalid then
                        update_guid_override(nil, id1, id2)
                        id1, id2 = get_ids_from_string(newGuid)
                        update_guid_override(newMsg, id1, id2)
                        guid_msg_pair[1] = newGuid
                        guid_msg_pair[2] = newMsg
                        selectedItem.messages[id2] = selectedItem.messages[id2] or {}
                        selectedItem.messages[id2][id1] = newMsg
                        udb.mark_entity_dirty(selectedItem)
                        guid_msg_pair[3] = nil
                        guid_msg_pair[4] = nil
                    end
                    if guid_is_invalid then
                        imgui.text_colored('GUID is invalid', core.get_color('warning'))
                    end
                end

                if should_remove then
                    update_guid_override(nil, id1, id2)
                    table.remove(editor_msg_lists[selectedItem.id], i)
                    selectedItem.messages[id2][id1] = nil
                    udb.mark_entity_dirty(selectedItem)
                end
                imgui.pop_id()
                imgui.pop_id()
                ::continue::
            end

            if imgui.button('Add new message##2') then
                create_new_message(selectedItem, 'New message')
            end

            imgui.end_rect(4)
            imgui.unindent(8)
            imgui.spacing()
        end
    end)

    editor.add_editor_tab('messages')
end

usercontent.messages = {
    create_new_message_group = create_new_message_group,
    create_new_message = create_new_message,
    add_message_override = add_message_override,
}
return usercontent.messages