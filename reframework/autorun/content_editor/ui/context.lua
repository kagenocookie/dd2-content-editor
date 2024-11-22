if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_contexts then return usercontent._ui_contexts end

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

local setter_error = function() error('Setter unsupported in current UI context') end

--- @type UIContainer
local root_context = {
    children = {},
    field = '',
    data = { classname = '/' },
    get = function () end,
    set = setter_error,
    label = '',
}

--- @param parent UIContainer
--- @param fieldName string|integer
--- @return UIContainer|nil
local function get_child(parent, fieldName)
    return parent.children[fieldName]
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

--- @param value any Not null
--- @param owner DBEntity|nil
--- @param label string
--- @param editorId any
--- @return UIContainer
local function create_root(value, owner, label, editorId)
    local classname = type(value) == 'userdata' and value.get_type_definition and value:get_type_definition():get_full_name() or 'unknown: ' .. tostring(value)
    local newctx
    newctx = create_child(root_context, editorId, value, label, {}--[[@as any]], classname)
    newctx.owner = owner
    newctx.parent = nil
    newctx.set = setter_error
    newctx.get = function () return newctx.object end

    if owner ~= nil then root_context.children[owner] = newctx end
    if editorId ~= nil then root_context.children[editorId] = newctx end
    root_context.children[value] = newctx

    return newctx
end

--- @param parent UIContainer|nil
--- @param childname string|integer
--- @param objectValue any
--- @param label string
--- @param accessors ObjectFieldAccessors|nil
--- @param classname string
--- @return UIContainer context, boolean newContext
local function get_or_create_child(parent, childname, objectValue, label, accessors, classname)
    parent = parent or root_context
    local ctx = get_child(parent, childname)
    if ctx then return ctx, false end
    if accessors then
        return create_child(parent, childname, objectValue, label, accessors, classname), true
    else
---@diagnostic disable-next-line: param-type-mismatch
        ctx = create_child(parent, childname, objectValue, label, nil, classname)
        ctx.get = function () return ctx.object end
        ctx.set = setter_error
        return ctx, true
    end
end

--- @param root_owner any
--- @return UIContainer|nil
local function get_root_from_owner(root_owner)
    return root_context.children[root_owner]
end

--- @param context UIContainer
local function get_context_root(context)
    local parent = context
    while parent and parent.parent ~= nil do
        parent = parent.parent
    end
    return parent
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
local function delete(ctx, editorId)
    delete_children(ctx)
    if ctx.parent then
        delete_child_by_context(ctx.parent, ctx)
    end
    if ctx.object and ctx.object == ctx.owner then
        root_context.children[ctx.object] = nil
    end
    if editorId then
        root_context.children[editorId] = nil
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
    local ctx = root_context.children[root_owner]
    if not ctx then
        imgui.text('[DEBUG] UI CONTEXT: null')
        return
    end
    debug_view_ctx(tostring(root_owner), ctx)
end

usercontent._ui_contexts = {
    create_root = create_root,
    create_child = create_child,
    get_or_create_child = get_or_create_child,
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

return usercontent._ui_contexts