if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._ui_contexts then return _userdata_DB._ui_contexts end

-- The idea here is that we use additional dynamic objects to store UI metadata in parallel to the actual objects
-- This lets us easily keep UI state without having to rely on some magic string logic
-- Every object using these should correctly deal with creating/deleting instances, otherwise it'll keep growing in size after changes are made
-- Not necessarily fun for a public API but since it's primarily just internal, ¯\_(ツ)_/¯

--- @class UIContainer
--- @field data table
--- @field object any|nil
--- @field owner DBEntity|nil
--- @field ui UIHandler|nil
--- @field parent UIContainer|nil
--- @field label string
--- @field field string|integer
--- @field get fun(): any|nil
--- @field set fun(value: any|nil)
--- @field children table<string|integer, UIContainer>

--- @type table<string, UIContainer>
local root_containers = {}

--- @param value any Not null
--- @param owner DBEntity|nil
--- @param label string
--- @param editorId any
--- @return UIContainer
local function create(value, owner, label, editorId)
    --- @type UIContainer
    local ctx
    ctx = {
        parent = nil,
        object = value,
        data = { classname = type(value) == 'userdata' and value.get_type_definition and value:get_type_definition():get_full_name() or 'unknown: ' .. tostring(value) },
        children = {},
        field = '',
        owner = owner,
        label = label,
        set = function() error('Setter unsupported in current UI context') end,
        get = function () return ctx.object end,
    }
    root_containers[value] = ctx
    if owner ~= nil and not root_containers[owner] then
        root_containers[owner] = ctx
    elseif owner == nil and editorId ~= nil then
        root_containers[editorId] = ctx
    end
    return ctx
end

--- @param parent UIContainer
--- @param childname string|integer
--- @param objectValue any
--- @param label string
--- @param accessors ObjectFieldAccessors
--- @param classname string
--- @return UIContainer
local function create_child(parent, childname, objectValue, label, accessors, classname)
    --- @type UIContainer
    local ctx
    ctx = {
        parent = parent,
        object = objectValue,
        data = { classname = classname },
        children = {},
        owner = parent.owner,
        field = childname,
        label = label,
        get = function() return accessors.get(parent.object, childname) end,
        set = function(value) accessors.set(parent.object, value, childname) ctx.object = value end,
    }
    parent.children[childname] = ctx
    return ctx
end

--- @param root_owner DBEntity|table|REManagedObject
--- @return UIContainer|nil
local function get_root_from_owner(root_owner)
    return root_containers[root_owner]
end

--- @param context UIContainer
local function get_context_root(context)
    local parent = context
    while parent and parent.parent ~= nil do
        parent = parent.parent
    end
    return parent
end

--- @param parent UIContainer
--- @param fieldName string|integer
--- @return UIContainer|nil
local function get_child(parent, fieldName)
    return parent.children[fieldName]
end

--- @param ctx UIContainer
local function delete_children(ctx)
    for _, child in pairs(ctx.children) do
        delete_children(child)
    end
    ctx.children = {}
end

--- @param parentCtx UIContainer
--- @param childkey string|integer
local function delete_child(parentCtx, childkey)
    if parentCtx.children[childkey] then
        delete_children(parentCtx.children[childkey])
        parentCtx.children[childkey] = nil
    end
end

--- @param parentCtx UIContainer
--- @param childContext UIContainer
local function delete_child_by_context(parentCtx, childContext)
    for key, child in pairs(parentCtx.children) do
        if child == childContext then
            delete_child(parentCtx, key)
            return
        end
    end
end

--- @param ctx UIContainer
local function delete(ctx)
    delete_children(ctx)
    if ctx.parent then
        delete_child_by_context(ctx.parent, ctx)
    end
    if ctx.object and ctx.object == ctx.owner then
        root_containers[ctx.object] = nil
    end
end

--- @param parentCtx UIContainer
--- @param childContext UIContainer
local function forget_child_by_context(parentCtx, childContext)
    for key, child in pairs(parentCtx.children) do
        if child == childContext then
            parentCtx.children[key] = nil
            childContext.parent = nil
            return
        end
    end
end

--- @param parent UIContainer
--- @param fieldName string|number
--- @param newContext UIContainer
local function replace_child(parent, fieldName, newContext)
    local ctx = parent.children[fieldName]
    if ctx then
        delete_children(ctx)
    end
    if newContext.parent and newContext.parent ~= parent then
        forget_child_by_context(newContext.parent, newContext)
    end
    newContext.parent = parent
    parent.children[fieldName] = newContext
end

--- @param ctx UIContainer
local function get_absolute_field_path(ctx)
    local p = ctx.field
    ctx = ctx.parent
    while ctx ~= nil do
        p = ctx.field .. '.' .. p
        ctx = ctx.parent
    end
    return p
end

--- @param prefix string|integer
--- @param ctx UIContainer
local function debug_view_ctx(prefix, ctx)
    imgui.text('[DEBUG] UI context: ' .. prefix .. ' = ' .. tostring(ctx.object))
    imgui.indent(8)
    if next(ctx.data) ~= nil then
        imgui.text(json.dump_string(ctx.data))
    end
    for name, child in pairs(ctx.children) do
        debug_view_ctx(name, child)
    end
    imgui.unindent(8)
end

local function debug_view(root_owner)
    local ctx = root_containers[root_owner]
    if not ctx then
        imgui.text('[DEBUG] UI CONTEXT: null')
        return
    end
    debug_view_ctx(tostring(root_owner), ctx)
end

_userdata_DB._ui_contexts = {
    create = create,
    create_child = create_child,
    delete = delete,
    delete_child = delete_child,
    delete_children = delete_children,
    get_root = get_root_from_owner,
    get_child = get_child,
    replace_child = replace_child,
    get_context_root = get_context_root,
    get_absolute_path = get_absolute_field_path,

    debug_view = debug_view,
}

return _userdata_DB._ui_contexts