if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.callbacks then return _userdata_DB.callbacks end

local hooked_callbacks = {}
local active_hooks = {}

--- An ID of the hook that can be used to cancel it externally.
--- @alias HookID integer

--- Trigger a hook function whenever a game callback is invoked.
--- @param callback ModuleEntryCallback
--- @param hook fun(): boolean|nil Returning true removes the hook and makes it not get called again until re-added.
--- @return HookID
local function add_hook(callback, hook)
    local hookContainer = active_hooks[callback]
    local counter = hooked_callbacks[callback]
    if counter == nil then
        counter = 0
        local finishedCallbacks = {}
        local debug = _userdata_DB.__internal.config.data.editor.devmode
        active_hooks[callback] = {}
        hookContainer = active_hooks[callback]

        if debug then
            re.on_application_entry(callback, function ()
                for i, h in pairs(hookContainer) do
                    if h() then finishedCallbacks[#finishedCallbacks+1] = i end
                end
                if next(finishedCallbacks) then
                    for _, i in ipairs(finishedCallbacks) do
                        hookContainer[i] = nil
                    end
                    finishedCallbacks = {}
                end
            end)
        else
            re.on_application_entry(callback, function ()
                for i, h in pairs(hookContainer) do
                    local success, result = pcall(h)
                    if not success then
                        print(callback .. ' error: ', result)
                        finishedCallbacks[#finishedCallbacks+1] = i
                    elseif result == true then
                        finishedCallbacks[#finishedCallbacks+1] = i
                    end
                end
                if next(finishedCallbacks) then
                    for _, i in ipairs(finishedCallbacks) do
                        hookContainer[i] = nil
                    end
                    finishedCallbacks = {}
                end
            end)
        end
    end

    counter = counter + 1

    hooked_callbacks[callback] = counter
    hookContainer[counter] = hook
    return counter
end

--- Trigger a callback only once. Identical to calling hook(), but typed correctly so it ends after one execution (return true)
--- @param callback ModuleEntryCallback
--- @param hook fun(): true
--- @return HookID
local function hook_once(callback, hook)
    return add_hook(callback, hook)
end

--- Trigger a callback exactly once after a minimum amount of time has passed.
--- @param callback ModuleEntryCallback
--- @param hook fun()
--- @param delayTimeSeconds number
--- @return integer HookID
local function hook_delay(callback, hook, delayTimeSeconds)
    local endTime = os.clock() + delayTimeSeconds
    return add_hook(callback, function ()
        if os.clock() >= endTime then
            hook()
            return true
        end
    end)
end

--- Trigger a callback at regular intervals of the given time
--- @param callback ModuleEntryCallback
--- @param hook fun(): boolean|nil
--- @param intervalTimeSeconds number
--- @param triggerFirstTime boolean|nil Whether the hook should get executed immediately the next time the callback is executed. Otherwise, first trigger will be after the given interval.
--- @return integer HookID
local function hook_interval(callback, hook, intervalTimeSeconds, triggerFirstTime)
    local nextTime = triggerFirstTime and 0 or os.clock() + intervalTimeSeconds
    return add_hook(callback, function ()
        local t = os.clock()
        if t >= nextTime then
            nextTime = t + intervalTimeSeconds
            if hook() then
                return true
            end
        end
    end)
end

--- Convenience method to trigger a hook on the next UpdateBehavior callback.
--- @param hook fun(): true
local function hook_next_frame(hook)
    return add_hook('UpdateBehavior', hook)
end

--- @param callback ModuleEntryCallback
--- @param hookId HookID
local function cancel_hook(callback, hookId)
    local hookContainer = active_hooks[callback]
    if hookContainer then
        hookContainer[hookId] = nil
    end
end

_userdata_DB.callbacks = {
    hook = add_hook,
    hook_once = hook_once,
    hook_delay = hook_delay,
    next_frame = hook_next_frame,
    hook_interval = hook_interval,
    cancel_hook = cancel_hook,
}
return _userdata_DB.callbacks