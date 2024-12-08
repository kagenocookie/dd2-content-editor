param([String]$Version="", [String]$CommitHash = "")

function PrepareFiles {
    param (
        [string] $BaseSourceFolder,
        [string] $Folder,
        [string[]] $FileList
    )
    Write-Output "Preparing subfolder $Folder ..."

    foreach ($file in $FileList)
    {
        if ($file.Contains('|')) {
            $outfile = $file.Substring($file.IndexOf('|') + 1)
            $infile = $file.Replace('|', '')
        } else {
            $outfile = $file
            $infile = $file
        }

        $outpath = "_build/$Folder/$outfile"
        $targetfolder = Split-Path $outpath -Parent
        if (!(Test-Path $targetfolder -PathType Container)) {
            New-Item -Path $targetfolder -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $infile -Recurse -Destination $outpath -Force -Container:$false
    }
}

function MakeModinfo {
    param (
        [string] $Folder,
        [string] $Name,
        [string] $Version,
        [string] $Description
    )
    $outpath = "_build/$Folder/modinfo.ini"
    $targetfolder = Split-Path $outpath -Parent
    if (!(Test-Path $targetfolder -PathType Container)) {
        New-Item -Path $targetfolder -ItemType Directory -Force | Out-Null
    }
    $content = $(Get-Content .\addon_template.ini)
    $content = $content.Replace("_VERSION_", "$Version").Replace("_NAME_", "$Name").Replace("_DESCRIPTION_", "$Description")
    Out-File -FilePath $outpath -InputObject $content
    ((Get-Content $outpath) -join "`n") + "`n" | Set-Content -NoNewline $outpath
}

# core game-agnostic zip
PrepareFiles -Folder "content_editor" -FileList (
    "reframework/autorun/content_editor",
    "reframework/autorun/content_editor.lua",
    "readme.md",
    "editor.png"
)
Copy-Item -Path modinfo.ini -Destination "_build/content_editor/modinfo.ini"

if ($CommitHash) {
    $CommitHash = $CommitHash.Substring(0, 7)
    Write-Output "Building for commit hash: $CommitHash"
    $versionedFile = ((Get-Content '_build/content_editor/reframework/autorun/content_editor/core.lua') -replace "table\.concat\(version, '\.'\)", "table.concat(version, '.') .. '-$CommitHash'" -join "`n") + "`n"
    Out-File -FilePath '_build/content_editor/reframework/autorun/content_editor/core.lua' -InputObject $versionedFile
}

if (!$Version) {
    $Version = 'v0.0.0'
}
if ($Version) {
    Write-Output "Building version: $Version"
    $versionParts = $Version.Substring(1).Split('.')
    $versionTable = Join-String -Separator ', ' -InputObject $versionParts
    $versionedFile = ((Get-Content '_build/content_editor/reframework/autorun/content_editor/core.lua') -replace 'local version = {([^}]+)}', "local version = {$versionTable}" -join "`n") + "`n"
    Out-File -FilePath '_build/content_editor/reframework/autorun/content_editor/core.lua' -InputObject $versionedFile -NoNewline
}

Set-Location _build/content_editor
& "C:/Program Files/7-Zip/7z.exe" a ../../content_editor_core.zip * | Out-Null
Set-Location ../..

# DD2 specific zip
PrepareFiles -Folder "content_editor/reframework/autorun" -FileList (
    "dd2/|editors/core",
    "dd2/editors/|devtools.lua"
)
PrepareFiles -Folder "content_editor/reframework/data/usercontent" -FileList (
    "dd2/|enums",
    "dd2/|presets",
    "dd2/|rsz"
)


MakeModinfo "quest_editor" "Quest editor" "v0.1.0" "(WIP) DD2 Content editor quests addon"
PrepareFiles -Folder "quest_editor/reframework/autorun" -FileList (
    "dd2/editors/|editor_quest.lua",
    "dd2/|editors/quests"
)
PrepareFiles -Folder "quest_editor" -FileList (
    "dd2/|natives/stm/appdata/quest/qu8000"
    # "natives/stm/appsystem/scene/quest.scn.20"
)

MakeModinfo "event_editor" "Event editor" $Version "DD2 Content editor events addon"
PrepareFiles -Folder "event_editor/reframework/autorun" -FileList (
    "dd2/editors/|editor_events.lua",
    "dd2/|editors/events"
)

MakeModinfo "shop_editor" "Shop editor" $Version "DD2 Content editor shops addon"
PrepareFiles -Folder "shop_editor/reframework/autorun" -FileList ("dd2/editors/|editor_shops.lua")

MakeModinfo "param_editor" "Parameter editor" $Version "DD2 Content editor human, job parameter addon"
PrepareFiles -Folder "param_editor/reframework/autorun" -FileList ("dd2/editors/|editor_human_params.lua")

MakeModinfo "item_editor" "Item editor" $Version "DD2 Content editor item addon"
PrepareFiles -Folder "item_editor/reframework/autorun" -FileList (
    "dd2/editors/|editor_items.lua",
    "dd2/|editors/items"
)

MakeModinfo "weather_editor" "Weathers editor" $Version "DD2 Content editor weathers addon"
PrepareFiles -Folder "weather_editor/reframework/autorun" -FileList (
    "dd2/editors/|editor_weathers.lua",
    "dd2/|editors/weathers"
)

MakeModinfo "experimental_editors" "Experimental editors" 'v0.0.1' "WIP DD2 experimental editors (AI data, chests, sounds, NPCs, ...), not fully tested and functionality might change at some point"
PrepareFiles -Folder "experimental_editors/reframework/autorun" -FileList (
    "dd2/editors/|editor_ai.lua",
    "dd2/editors/|editor_chests.lua",
    "dd2/editors/|editor_sound_viewer.lua",
    "dd2/editors/|editor_npc.lua"
)

Set-Location _build
& "C:/Program Files/7-Zip/7z.exe" a ../content_editor_dd2.zip * | Out-Null

Set-Location ..
Remove-Item .\_build -Recurse
