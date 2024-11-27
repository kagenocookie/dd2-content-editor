if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB._common_handlers then return _quest_DB._common_handlers end

local core = require('content_editor.core')
local ui = require('content_editor.ui.imgui_wrappers')
local enums = require('content_editor.enums')
local utils = require('content_editor.utils')

--- @return UIHandler
local function create_int(speed, min_range, max_range, format_string)
    min_range = min_range == nil and -99999 or min_range
    max_range = max_range == nil and 99999 or max_range
    speed = speed == nil and 0.1 or speed
    local support_extra_range = min_range <= -2147483648 or max_range > 2147483647

    return function (ctx)
        local curvalue = ctx.get()
        local changed, value
        if support_extra_range and curvalue ~= nil and (curvalue <= -2147483648 or curvalue >= 2147483647) then
            local w = imgui.calc_item_width()
            imgui.push_item_width(w / 2 - 4)
            changed,value = imgui.drag_int('##' .. ctx.label, curvalue, speed, min_range, max_range, format_string)
            imgui.same_line()
            local changed2, value2 = imgui.input_text(ctx.label, tostring(curvalue), 1)
            if imgui.is_item_hovered() then
                imgui.set_tooltip("In case of numbers outside of the -2147483646 to 2147483647 integer range, the drag UI doesn't display the value property.\nUse this text field to edit such values.")
            end
            if changed2 then
                changed = true
                value2 = tonumber(value2) --- @type any
                if value2 ~= nil then
                    value = value2
                end
            end
            imgui.pop_item_width()
        else
            changed, value = imgui.drag_int('##' .. ctx.label, curvalue, speed, min_range, max_range, format_string)
            imgui.same_line()
            imgui.text(ctx.label)
            -- changed, value = imgui.drag_int(ctx.label, curvalue, speed, min_range, max_range, format_string)
        end
        if changed then
            ctx.set(value)
        end
        return changed
    end
end

--- @return UIHandler
local function create_float(speed, min_range, max_range, format_string)
    min_range = min_range == nil and -99999 or min_range
    max_range = max_range == nil and 99999 or max_range
    speed = speed == nil and 0.1 or speed

    return function (ctx)
        local changed, value = imgui.drag_float(ctx.label, ctx.get(), speed, min_range, max_range, format_string)
        if changed then
            ctx.set(value)
        end
        return changed
    end
end

--- @type UIHandler
local function create_bool(ctx)
    local changed, newval = imgui.checkbox(ctx.label, ctx.get())
    if changed then
        ctx.set(newval)
    end
    return changed
end

--- @return UIHandler
local function create_int_slider(min_range, max_range, format_string)
    min_range = min_range == nil and -99999 or min_range
    max_range = max_range == nil and 99999 or max_range
    speed = speed == nil and 1 or speed

    return function (ctx)
        local changed, value = imgui.slider_int(ctx.label, ctx.get(), min_range, max_range, format_string)
        if changed then
            ctx.set(value)
        end
        return changed
    end
end

--- @return UIHandler
local function create_float_slider(min_range, max_range, format_string)
    min_range = min_range == nil and -99999 or min_range
    max_range = max_range == nil and 99999 or max_range

    return function (ctx)
        local changed, value = imgui.slider_float(ctx.label, ctx.get(), min_range, max_range, format_string)
        if changed then
            ctx.set(value)
        end
        return changed
    end
end


--- @param enum EnumSummary|string|nil
--- @return UIHandler
local function create_enum(enum)
    if type(enum) == 'string' then enum = enums.get_enum(enum) end
    --- @type UIHandler
    return function (context)
        local changed, value
        if not enum then
            if context.data.classname and context.data.classname:find('System.') ~= 1 then
                enum = enums.get_enum(context.data.classname)
            else
                changed, value = imgui.drag_int(context.label .. ' (Invalid enum)', context.get(), 0.1)
                if changed then context.set(value) end
                return changed
            end
        end
        if #enum.values > 15 then
            changed, value, context.data.filter = ui.filterable_enum_value_picker(context.label, context.get(), enum, context.data.filter or '')
        else
            changed, value = ui.enum_value_picker(context.label, context.get(), enum)
        end

        if changed then context.set(value) end
        return changed
    end
end

--- Lazy load an enum handler. Useful for enums that aren't resolved immediately on launch
--- @param name string
--- @return UIHandler
local function create_enum_lazy(name)
    local enum = enums.get_enum(name)
    if next(enum.values) ~= nil then return create_enum(enum) end

    local enumHandler
    --- @type UIHandler
    return function (context)
        if not enumHandler then
            enum = enums.get_enum(name)
            if next(enum.values) == nil then
                imgui.text_colored(context.label .. ': ' .. (context.get() or 0) .. '      | Unknown enum: ' .. name, core.get_color('warning'))
                return false
            end
            enumHandler = create_enum(enum)
        end
        return enumHandler(context)
    end
end

--- @param enum EnumSummary|nil Enum to construct flags from. Will be inferred from the instance type if unset.
--- @param items_per_row_count integer|nil How many items should be displayed per row before breaking into a new line
--- @return UIHandler
local function create_flags_enum(enum, items_per_row_count)
    --- @type UIHandler
    return function (context)
        local value = context.get()

        local isMultiline = false
        local changed, changed2 = false, false
        if not enum then enum = enums.get_enum(context.data.classname) end
        imgui.indent(4)
        imgui.begin_rect()
        imgui.spacing()
        imgui.indent(4)
        for i, flagValue in ipairs(enum.values) do
            local checked = (flagValue & value) ~= 0
            if i ~= 1 then
                if items_per_row_count == nil or (i%items_per_row_count ~= 1) then
                    imgui.same_line()
                else
                    isMultiline = true
                end
            end
            changed2, checked = imgui.checkbox(enum.get_label(flagValue), checked)
            if changed2 then
                changed = changed2
                if checked then
                    value = value | flagValue
                else
                    value = value & (~flagValue)
                end
                context.set(value)
            end
        end

        if isMultiline then
            imgui.text(context.label)
            imgui.spacing()
            imgui.spacing()
        else
            imgui.same_line()
            imgui.text('  |  ' .. context.label)
        end
        imgui.unindent(4)
        imgui.end_rect(1)
        imgui.unindent(4)
        return changed
    end
end

--- @param resourceClassname string
--- @return UIHandler
local function resource_holder(resourceClassname)
    local importer
    --- @type UIHandler
    return function (context)
        local res = context.get()
        imgui.text(context.label)
        if type(res) == 'string' then
            local changed, newpath = imgui.input_text('Resource path', res)
            if changed then
                context.set(newpath)
                return true
            end
            return false
        end

        local curpath = res and res:get_ResourcePath() or ''
        local changed, newpath = imgui.input_text('Resource path', context.data.newpath or curpath)
        if changed then
            context.data.newpath = newpath
        end
        if context.data.newpath and context.data.newpath ~= curpath then
            if imgui.button('Change') then
                importer = importer or usercontent.import_handlers.common.resource(resourceClassname).import
                local newres = importer(context.data.newpath, nil)
                if newres then
                    context.set(newres)
                    return true
                else
                    print('ERROR: failed to create resource ', resourceClassname, context.data.newpath)
                end
            end
            imgui.same_line()
            if imgui.button('Cancel') then
                context.data.newpath = nil
            end
        end

        return false
    end
end

--- @param enumProvider fun(context: UIContainer): EnumSummary|nil
--- @return UIHandler
local function create_dynamic_enum_filterable(enumProvider)
    --- @type UIHandler
    return function (context)
        local enum = enumProvider(context)
        local value = context.get()
        local changed, newValue
        if not enum then
            changed, newValue = imgui.drag_int(context.label, value)
            imgui.text_colored('<dynamic enum failed to resolve>', 0xff9999ff)
        else
            changed, newValue, context.data.filter = ui.filterable_enum_value_picker(context.label, value, enum, context.data.filter or '')
        end
        if changed then context.set(newValue) end
        return changed
    end
end

--- @param innerHandler UIHandler
--- @param get_toggled fun(value: any, ctx: UIContainer): boolean
--- @param set_toggled fun(value: UIContainer, toggle: boolean)
--- @param inline boolean|nil
--- @return fun(context: UIContainer):(changed: boolean, childContext: UIContainer|nil)
local function toggleable_value(innerHandler, get_toggled, set_toggled, inline)
    if inline == nil then inline = true end
    --- @type UIHandler
    return function (context)
        local value = context.get()
        if value == nil then
            -- if the value is nil, leave the handling of doing a Create to the inner handler
            return innerHandler(context)
        end
        local toggled = get_toggled(value, context)
        if toggled then
            if not inline then imgui.begin_rect() end
            local changed, toggle = imgui.checkbox(inline and ('(Enabled)##' .. context.label) or context.label, toggled)
            if changed and not toggle then
                set_toggled(context, toggle)
                return true
            end
            if inline then
                imgui.same_line()
                changed = innerHandler(context)
            else
                imgui.indent(24)
                changed = innerHandler(context)
                imgui.unindent(24)
                imgui.end_rect(2)
            end
            return changed
        else
            local changed, toggle = imgui.checkbox('(Disabled) ' .. context.label, toggled)
            if changed and toggle then
                set_toggled(context, toggle)
            end
            return changed
        end
    end
end

local function create_expandable(innerHandler)
    --- @type UIHandler
    return function (context)
        if imgui.tree_node(context.label) then
            local changed = innerHandler(context)
            imgui.tree_pop()
            return changed
        end
        return false
    end
end

---@param valueClassname string
---@param valueFieldHandler UIHandler
---@return UIHandler
local function create_nullable_value_type(valueClassname, valueFieldHandler)
    return toggleable_value(
        valueFieldHandler,
        function (nullable)
            return nullable._HasValue
        end,
        function (context, toggled)
            local val = context.get()
            if toggled then
                local newval = usercontent._ui_utils.create_instance(valueClassname)
                val._HasValue = true
                val._Value = newval
                context.set(val)
            else
                val._HasValue = false
                context.set(val)
            end
        end
    )
end

--- @param fields string[]
--- @param imgui_callback function
--- @return UIHandler
local function create_vec_n(fields, imgui_callback, imgui_value_creator)
    return function (ctx)
        local value = ctx.get() or {}
        local newval = imgui_value_creator()
        for _, f in ipairs(fields) do
            newval[f] = value[f] or 0
        end

        local changed
        changed, newval = imgui_callback(ctx.label, newval, 0.1)
        if changed then
            for _, f in ipairs(fields) do
                value[f] = newval[f]
            end
            ctx.set(value)
        end
        return changed
    end
end

local float_vec2 = create_vec_n({'x', 'y'}, imgui.drag_float2, function() return Vector2f.new(0, 0) end)
local float_vec3 = create_vec_n({'x', 'y', 'z'}, imgui.drag_float3, function() return Vector3f.new(0, 0, 0) end)
local float_vec4 = create_vec_n({'x', 'y', 'z', 'w'}, imgui.drag_float4, function() return Vector4f.new(0, 0, 0, 0) end)
local int_vec2 = create_vec_n({'x', 'y'}, function (label, val, n)
    local changed, newval = imgui.drag_float2(label, val, n, nil, nil, '%.0f')
    return changed, { x = math.floor(newval.x), y = math.floor(newval.y) }
end, function() return Vector2f.new(0, 0) end)
local int_vec3 = create_vec_n({'x', 'y', 'z'}, function (label, val, n)
    local changed, newval = imgui.drag_float3(label, val, n, nil, nil, '%.0f')
    return changed, { x = math.floor(newval.x), y = math.floor(newval.y), z = math.floor(newval.z) }
end, function() return Vector3f.new(0, 0, 0) end)

--- @type UIHandler
local function handle_color(ctx)
    local value = ctx.get()
    local rgba = value.rgba
    local newval = Vector4f.new((rgba & 0xff) / 255, ((rgba & 0xff00) >> 8) / 255, ((rgba & 0xff0000) >> 16) / 255, ((rgba & 0xff000000) >> 24) / 255)
    local changed
    changed, newval = imgui.color_edit4(ctx.label, newval)
    if changed then
        value.rgba = math.floor(newval.x*255) + (math.floor(newval.y*255) << 8) + (math.floor(newval.z*255) << 16) + (math.floor(newval.w*255) << 24)
        ctx.set(value)
    end
    return changed
end

--- @type UIHandler
local function stringHandler(context)
    local curstr = context.get()
    local changed, newvalue = imgui.input_text(context.label, curstr)
    if changed then
        local isRaw = type(curstr) == 'string' or type(curstr) ~= 'userdata' and curstr == nil and type(context.parent) == 'table'
        context.set(isRaw and newvalue or sdk.create_managed_string(newvalue))
    end
    return changed
end

local readonly_default_tostring = function (a) return tostring(a) end

--- @param displayValue nil|fun(value: any): string
--- @return UIHandler
local function readonlyValue(displayValue)
    displayValue = displayValue or readonly_default_tostring
    --- @type UIHandler
    return function (context)
        local val = context.get()
        imgui.text(context.label .. ': ' .. displayValue(val))
        return false
    end
end

local hour_slider = create_int_slider(0, 23, '%d h')
local minute_slider = create_int_slider(0, 59, '%d m')
local week_slider = create_int_slider(0, 4, '%d week')
local float_0_1 = create_float(1, 0, 1)
local float_0_100 = create_float(1, 0, 100)
local float_0_200 = create_float(1, 0, 200)
local float_0_1000 = create_float(1, 0, 1000)

--- @param field string
--- @param prefix string|boolean|nil
--- @return function
local function tostring_field_translator(field, prefix)
    return function (value, ctx)
        if type(prefix) == 'string' then
            return prefix .. tostring(value and utils.translate_guid(value[field]))
        elseif prefix then
            local type = ctx and ctx.data.classname or value.get_type_definition and value:get_type_definition():get_name() or 'Name'
            return type .. ': ' .. tostring(value and utils.translate_guid(value[field]))
        else
            return tostring(value and utils.translate_guid(value[field]))
        end
    end
end

local translatable_guid_field = { extensions = { { type = 'translate_guid' } } }

_quest_DB._common_handlers = {
    int = create_int,
    int_slider = create_int_slider,
    float = create_float,
    float_slider = create_float_slider,
    bool = create_bool,
    enum = create_enum,
    enum_lazy = create_enum_lazy,
    enum_flags = create_flags_enum,
    enum_dynamic = create_dynamic_enum_filterable,
    vec2 = float_vec2,
    vec3 = float_vec3,
    vec4 = float_vec4,
    vec2_int = int_vec2,
    vec3_int = int_vec3,
    color = handle_color,

    resource_holder = resource_holder,

    expandable_tree = create_expandable,
    toggleable = toggleable_value,
    nullable_valuetype = create_nullable_value_type,

    readonly_label = readonlyValue,
    string = stringHandler,
    preset = {
        hour_slider = hour_slider,
        minute_slider = minute_slider,
        week_slider = week_slider,
        float_0_1 = float_0_1,
        float_0_100 = float_0_100,
        float_0_200 = float_0_200,
        float_0_1000 = float_0_1000,
    },

    helpers = {
        tostring_field_translator = tostring_field_translator,
        translatable_guid_field = translatable_guid_field,
    }
}

return _quest_DB._common_handlers