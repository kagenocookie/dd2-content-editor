if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_translations then return usercontent._ui_translations end

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local config = require('content_editor._internal').config

local fallbackLanguage = 'en'
local word_translations = {}
local keyed_translations = {}
local languages = {}

local translationsLoaded = false
local function setupTranslations()
    core.log_debug('setting up translations...')
    local allTexts = core.get_files('i18n')
    local langs = {}
    local basepath = core.get_path('i18n'):gsub('/', '\\') .. '\\'
    for _, fn in ipairs(allTexts) do
        local data = json.load_file(fn)

        fn = fn:gsub('^' .. basepath, '')
        local lang = fn:match('^(%w+)')
        if lang then
            if not langs[lang] then langs[lang] = true end
            fn = fn:sub(#lang + 2)
            if fn == 'word_translations.json' then
                word_translations[lang] = data
            else
                local context = fn:match('^(%w+)[\\/]')
                if context then
                    fn = fn:sub(#context + 1)
                    context = context:sub(1, -1)
                else
                    context = 'global'
                end
                local target = keyed_translations[context]
                if not target then
                    target = {}
                    keyed_translations[context] = target
                end
                if target[lang] then
                    utils.table_assign(target[lang], data)
                else
                    target[lang] = data
                end
            end
        end
    end

    languages = utils.get_sorted_table_keys(langs)
    translationsLoaded = true
    core.log_debug('translations setup')
end

--- Translate a specific predefined string into the chosen language
--- @param key string
--- @param context string|nil
--- @param lang string|nil
--- @return string translated, boolean foundTranslation
local function translate(key, context, lang)
    if not translationsLoaded then setupTranslations() end
    lang = lang or config.data.editor.language or fallbackLanguage
    context = context or 'global'

    local data = keyed_translations[context]
    data = data and data[lang]
    if data and data[key] then
        return data[key], true
    end

    if lang ~= fallbackLanguage then
        return translate(key, context, fallbackLanguage)
    end
    if not data then print('invalid context or lang', lang, key, context) end
    return key, false
end

--- Translate a specific predefined string into the chosen language with the given template key strings replaced
--- @param key string
--- @param context string|nil
--- @param lang string|nil
--- @return string translated, boolean foundTranslation
local function translate_templated(key, context, template, lang)
    local translated, valid = translate(key, context, lang)
    for k, v in pairs(template) do
        translated = translated:gsub('$' .. k, tostring(v))
    end

    -- fallback in case there's no file provided translation and we have template params, at least append all of them at the end of the message
    if not valid and key == translated then
        translated = translated .. ';'
        for k, v in pairs(template) do
            translated = translated .. ' ' .. k .. '=' .. tostring(v)
        end
    end
    return translated, valid
end

--- Attempt to translate strings word by word (e.g. developer comments that are usually in japanese). This just does a simple find & replace for all defined words so expect grammar issues.
--- @param text string
--- @param lang string|nil
--- @return string
local function per_word_translate(text, lang)
    if not translationsLoaded then setupTranslations() end
    local words = lang and word_translations[lang] or word_translations[fallbackLanguage] or {}
    text = text:gsub('%%', '%%%%')
    for _, pair in ipairs(words) do
        if #pair >= 2 then
            text = text:gsub(pair[1], pair[2] .. ' ')
        end
    end
    return text
end

local function get_languages() return languages end

usercontent._ui_translations = {
    languages = get_languages,
    translate = translate,
    translate_t = translate_templated,
    per_word_translate = per_word_translate,
}
return usercontent._ui_translations