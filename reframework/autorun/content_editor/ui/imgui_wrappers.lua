if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_wrappers then return usercontent._ui_wrappers end

local utils = require('content_editor.utils')

local DEFAULT_WIDTH = 300

local function table_to_imgui(tbl)
    if type(tbl) == 'userdata' then
        object_explorer:handle_address(tbl)
        return
    end
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            if imgui.tree_node(k) then
                table_to_imgui(v)
                imgui.tree_pop()
            end
        else
            imgui.text(k .. ' : ' .. tostring(v))
        end
    end
end

---@param text string
---@param color integer|nil
---@param prefix boolean|nil
local function imgui_tooltip(text, color, prefix)
    if not prefix then
        imgui.same_line()
    end
    imgui.text_colored("(?)", type(color) == 'number' and color or 0xffffaaaa)
    if imgui.is_item_hovered() then
        imgui.set_tooltip(text)
    end
    if prefix then
        imgui.same_line()
    end
end

local function setting_checkbox(label, container, key, saveFunc, tooltip)
    local changed
    local val = container[key]
    changed, val = imgui.checkbox(label, val)
    if tooltip then
        imgui_tooltip(tooltip)
    end
    if changed then container[key] = val saveFunc() end
    return changed
end

local function setting_text(label, container, key, saveFunc, lines, tooltip)
    local changed
    local val = container[key]
    if lines and lines > 1 then
        changed, val = imgui.input_text_multiline(label, val, lines)
    else
        changed, val = imgui.input_text(label, val)
    end
    if tooltip then
        imgui_tooltip(tooltip)
    end
    if changed then container[key] = val saveFunc() end
    return changed
end

--- @param text string
--- @param tooltip string
--- @return boolean
local function imgui_treenode_tooltip(text, tooltip)
    local tn = imgui.tree_node(text)
    imgui_tooltip(tooltip)
    return tn
end

--- Adds a suffix to a treenode label where the suffix can change without resetting the UI collapsed state
--- @param str string
--- @param suffix string
--- @param color integer|nil
--- @return boolean
local function imgui_treenode_suffix(str, suffix, color)
    local show = imgui.tree_node(str)
    if suffix then
        imgui.same_line()
        imgui.text_colored(suffix, color or 0xffcccccc)
    end
    return show
end

local function combo_with_input(label, value, labels, values, id)
    local changed, waschanged
    imgui.push_id(id)

    imgui.set_next_item_width(imgui.calc_item_width() / 3 * 2)
    local idx = utils.table_index_of(values, value)
    changed, idx = imgui.combo('##combo', idx, labels)
    if changed or values[idx] ~= value then
        value = values[idx]
        waschanged = true
    end

    imgui.same_line()
    imgui.set_next_item_width(imgui.calc_item_width() / 3)
    changed, value = imgui.input_text('##text', value)
    if changed then waschanged = true end

    imgui.same_line()
    imgui.text(label)

    imgui.pop_id()
    return waschanged, value
end

---Filter a list of strings by a substring
---@generic T2
---@param filter string
---@param list string[]
---@param list2 T2[]|nil A second paired list that will also get included whenever the `list` entry with the same index passes the filter
---@return string[], T2[]|nil
local function filter_entries(filter, list, list2)
    local l1 = {}
    local l2 = list2 and {} or nil
    local inserted = 1
    for i = 1, #list do
        local label = list[i]
        if label:find(filter, 1, true) then
            l1[inserted] = label
            if list2 then l2[inserted] = list2[i] end
            inserted = inserted + 1
        end
    end
    return l1, l2
end

local UI_DEFAULT_MARGIN = 4

--- @param label string
--- @param index integer
--- @param options string[]
--- @param filter string
--- @return boolean changed, integer value, string filter
local function _combo_filterable_internal(label, index, options, filter)
    local changed
    imgui.set_next_item_width(imgui.calc_item_width() / 3 * 2)
    changed, newIndex = imgui.combo('##combo_c__' .. label, index, options)
    imgui.same_line()
    imgui.set_next_item_width(imgui.calc_item_width() / 3)
    local filterChanged, newFilter = imgui.input_text('##combo_f__' .. label, filter or '')
    if filterChanged then
        filter = newFilter
    end
    if index ~= newIndex and not changed and filter and filter ~= '' and imgui.button('Apply search result') then
        changed = true
    end

    imgui.same_line()
    imgui.text(label)

    if changed then
        return true, newIndex, filter
    end
    return false, index, filter
end

--- @generic TVal
--- @param label string
--- @param value any
--- @param labels string[]
--- @param filter string
--- @param values TVal[]|nil A pair array of the labels array, to use custom values instead of using the labels directly
--- @return boolean changed, TVal value, string filter
local function combo_filterable(label, value, labels, filter, values)
    local visible_labels, visible_values
    if filter and filter ~= '' then
        visible_labels, visible_values = filter_entries(filter, labels, values)
        visible_values = visible_values or visible_labels
    else
        visible_labels, visible_values = labels, values or labels
    end
    local idx = utils.table_index_of(visible_values, value)
    local changed, newIdx, newFilter = _combo_filterable_internal(label, idx, visible_labels, filter)
    if newIdx ~= 0 then
        value = visible_values[newIdx]
    end
    return changed, value, newFilter
end

---@param label string IMGUI label
---@param value integer The current enum value
---@param enum EnumSummary Enum to filter on
---@param filter string Current filter string
---@return boolean changed, integer newValue, string filter
local function imgui_filterable_enum_value_picker(label, value, enum, filter)
    return combo_filterable(label, value, enum.displayLabels or enum.labels, filter, enum.values)
end

---@param label string IMGUI label
---@param currentLabel string The enum's label will be used for the stored variable, since the numeric values tend to be random
---@param enum EnumSummary Enum to filter on
---@param filter string Current filter string
---@return boolean changed, string newLabel, string filter
local function imgui_filterable_enum_picker(label, currentLabel, enum, filter)
    local changed, newValue
    local value = enum.labelToValue[currentLabel]
    changed, newValue, filter = imgui_filterable_enum_value_picker(label, value, enum, filter)
    return changed, enum.valueToLabel[newValue], filter
end

---@param label string
---@param currentLabel string
---@param enum EnumSummary
---@return boolean, string
local function imgui_enum_picker(label, currentLabel, enum)
    local changed
    local idx = enum.find_index_by_label(currentLabel)
    changed, idx = imgui.combo(label, idx, enum.displayLabels or enum.labels)
    if changed then
        return true, enum.labels[idx]
    end
    return false, currentLabel
end

---@param label string
---@param currentValue integer
---@param enum EnumSummary
---@return boolean, integer
local function imgui_enum_value_picker(label, currentValue, enum)
    local changed
    local idx = enum.find_index_by_value(currentValue)
    changed, idx = imgui.combo(label, idx, enum.displayLabels or enum.labels)
    if changed then
        return true, enum.values[idx]
    end
    return false, currentValue
end

--- @param tabs string[]
--- @param selectedTabIndex integer 1-based tab index
--- @param header string|nil
--- @return boolean changed, integer newSelectedIndex
local function imgui_tabs(tabs, selectedTabIndex, inline, header)
    local changed = false
    if not inline then
        imgui.spacing()
        imgui.indent(16)
    end
    imgui.begin_rect()
    local w_total = imgui.calc_item_width() - 32
    local w = 0
    if header then imgui.text(header) if inline then imgui.same_line() end end
    local tab_margin = 8
    local char_w = 6
    for i = 1, #tabs do
        if i > 1 then
            if w >= w_total then
                w = 0
            else
                imgui.same_line()
            end
        end

        w = w + (#tabs[i] * char_w) + tab_margin
        if i == selectedTabIndex then
            imgui.begin_disabled(true)
            imgui.text(tabs[i])
            imgui.end_disabled()
        else
            if imgui.button(tabs[i]) then
                selectedTabIndex = i
                changed = true
            end
        end
    end
    imgui.end_rect(4)
    if not inline then
        imgui.unindent(16)
        imgui.spacing()
    end

    return changed, selectedTabIndex
end

---@param text string
local function linecount(text)
    local m = text:gmatch('\n')
    local count = 1
    while m() do
        count = count + 1
    end
    return count
end

local function lineHeight(lines)
    return 6 + lines * (imgui.get_default_font_size() + 2)
end

--- @param label string
--- @param value string
--- @param maxlines integer|nil
local function expanding_multiline_input(label, value, maxlines)
    maxlines = maxlines or 10
    local w = imgui.calc_item_width()
    local h = value and lineHeight(math.min(maxlines, linecount(value))) or 1
    local changed, newvalue = imgui.input_text_multiline(label, value or '', Vector2f.new(w, h))
    return changed, newvalue
end

usercontent._ui_wrappers = {
    DEFAULT_WIDTH = DEFAULT_WIDTH,

    table_to_imgui = table_to_imgui,
    combo_with_input = combo_with_input,
    combo_filterable = combo_filterable,

    tooltip = imgui_tooltip,
    treenode_tooltip = imgui_treenode_tooltip,
    treenode_suffix = imgui_treenode_suffix,
    enum_picker = imgui_enum_picker,
    enum_value_picker = imgui_enum_value_picker,
    filterable_enum_picker = imgui_filterable_enum_picker,
    filterable_enum_value_picker = imgui_filterable_enum_value_picker,
    expanding_multiline_input = expanding_multiline_input,

    tabs = imgui_tabs,

    setting_checkbox = setting_checkbox,
    setting_text = setting_text,

    _filter_entries = filter_entries,
}

return usercontent._ui_wrappers
