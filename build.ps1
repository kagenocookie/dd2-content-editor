param([String]$Version="v0.6.0", [Int32]$injectVersion = 0)

function PrepareFiles {
    param (
        [string] $BaseSourceFolder,
        [string] $Folder,
        [string[]] $FileList
    )
    Write-Output "Preparing submod $Folder ..."

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
            New-Item -Path $targetfolder -ItemType Directory -Force
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
        New-Item -Path $targetfolder -ItemType Directory -Force
    }
    $content = $(Get-Content .\addon_template.ini)
    $content = $content.Replace("_VERSION_", "$Version").Replace("_NAME_", "$Name").Replace("_DESCRIPTION_", "$Description")
    Out-File -FilePath $outpath -InputObject $content
    ((Get-Content $outpath) -join "`n") + "`n" | Set-Content -NoNewline $outpath
}

if ($injectVersion) {
    $versionParts = $Version.Substring(1).Split('.')
    $versionTable = Join-String -Separator ', ' -InputObject $versionParts
    $versionedFile = ((Get-Content 'reframework/autorun/content_editor/core.lua') -replace 'local version = {([^}]+)}', "local version = {$versionTable}" -join "`n") + "`n"
    Out-File -FilePath 'reframework/autorun/content_editor/core.lua' -InputObject $versionedFile -NoNewline
}

# core game-agnostic zip
PrepareFiles -Folder "content_editor" -FileList (
    "reframework/autorun/content_editor",
    "reframework/autorun/content_editor.lua",
    "readme.md",
    "editor.png"
)
Copy-Item -Path modinfo.ini -Destination "_build/content_editor/modinfo.ini"

Set-Location _build/content_editor
& "C:/Program Files/7-Zip/7z.exe" a ../../content_editor_core.zip *
Set-Location ../..

# DD2 specific zip
PrepareFiles -Folder "content_editor/reframework/autorun" -FileList ("dd2/|editors/core")
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

Set-Location _build
& "C:/Program Files/7-Zip/7z.exe" a ../content_editor_dd2.zip *

Set-Location ..
Remove-Item .\_build -Recurse
