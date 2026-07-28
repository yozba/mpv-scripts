-- losslesscut.lua
-- mpvで再生中のローカルファイルを、ffmpegの -c copy でロスレストリミングして書き出す
--
-- 操作フロー（videoclipに倣った設計）:
--   c : メニューを開く（1回目）
--   s : 開始点をセット（現在の再生位置）
--   e : 終了点をセット（現在の再生位置）
--   c : 書き出し実行（開始・終了点がセットされている状態で2回目を押す）
--   ESC : キャンセルしてメニューを閉じる
--
-- メニューが開いている間だけ s/e/ESC が割り当てられる。
-- メニューを開いていない時は mpv 標準の s（スクリーンショット）等の挙動を邪魔しない。
--
-- 配置場所:
--   Linux/Mac : ~/.config/mpv/scripts/losslesscut.lua
--   Windows   : %APPDATA%/mpv/scripts/losslesscut.lua
--
-- 設定ファイル（videoclipと同じ仕組み。無くても動く。無いキーはデフォルト値が使われる）:
--   Linux/Mac : ~/.config/mpv/script-opts/losslesscut.conf
--   Windows   : %APPDATA%/mpv/script-opts/losslesscut.conf
--
--   設定例:
--     output_dir=~/Videos
--     key_menu=c
--     key_start=s
--     key_end=e
--     key_cancel=ESC
--     ffmpeg_path=ffmpeg
--     map_all_streams=no
--
-- 注意:
--   -c copy は再エンコードしないため、実際のカット開始点は
--   直前のキーフレームにスナップされる（フレーム単位の完全一致ではない）。

local options = require 'mp.options'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local opts = {
    output_dir = "~/Videos",
    key_menu = "c",
    key_start = "s",
    key_end = "e",
    key_cancel = "ESC",
    ffmpeg_path = "ffmpeg",
    map_all_streams = false,
}
options.read_options(opts, "losslesscut")

local output_dir = mp.command_native({"expand-path", opts.output_dir})

local start_time = nil
local end_time = nil
local menu_active = false

local function notify(text, duration)
    mp.osd_message(text, duration or 2)
    msg.info(text)
end

local function fmt_time(t)
    if t == nil then
        return "-未設定-"
    end
    return string.format("%.3f", t)
end

local function status_text()
    return string.format(
        "[losslesscut]\n開始: %s / 終了: %s\n%s:開始点  %s:終了点  %s:書き出し  %s:キャンセル",
        fmt_time(start_time), fmt_time(end_time),
        opts.key_start, opts.key_end, opts.key_menu, opts.key_cancel
    )
end

local function reset_points()
    start_time = nil
    end_time = nil
end

local function set_start()
    start_time = mp.get_property_number("time-pos")
    notify(status_text(), 3)
end

local function set_end()
    end_time = mp.get_property_number("time-pos")
    notify(status_text(), 3)
end

local function close_menu()
    if not menu_active then
        return
    end
    mp.remove_key_binding("losslesscut-set-start")
    mp.remove_key_binding("losslesscut-set-end")
    mp.remove_key_binding("losslesscut-cancel")
    menu_active = false
end

local function cancel_menu()
    reset_points()
    close_menu()
    notify("キャンセルしました", 2)
end

local function open_menu()
    if menu_active then
        return
    end
    mp.add_forced_key_binding(opts.key_start, "losslesscut-set-start", set_start)
    mp.add_forced_key_binding(opts.key_end, "losslesscut-set-end", set_end)
    mp.add_forced_key_binding(opts.key_cancel, "losslesscut-cancel", cancel_menu)
    menu_active = true
    notify(status_text(), 5)
end

local function build_output_path(input_path)
    local dir, filename = utils.split_path(input_path)
    local name, ext = filename:match("^(.+)%.([^.]+)$")
    if not name then
        name = filename
        ext = "mkv"
    end
    local ts = os.date("%Y%m%d_%H%M%S")
    local out_name = string.format("%s_cut_%s.%s", name, ts, ext)
    return utils.join_path(output_dir, out_name)
end

local function do_export()
    local input_path = mp.get_property("path")
    if input_path == nil then
        notify("再生中のファイルが取得できません", 3)
        return
    end
    if input_path:match("^https?://") then
        notify("URL（ストリーミング）の入力には対応していません", 3)
        return
    end

    local abs_input_path = input_path
    if not (input_path:match("^/") or input_path:match("^%a:[/\\]")) then
        local working_dir = mp.get_property("working-directory")
        abs_input_path = utils.join_path(working_dir, input_path)
    end

    local duration = end_time - start_time
    local output_path = build_output_path(abs_input_path)

    local args = {
        opts.ffmpeg_path, "-y",
        "-ss", tostring(start_time),
        "-i", abs_input_path,
        "-t", tostring(duration),
    }
    if opts.map_all_streams then
        table.insert(args, "-map")
        table.insert(args, "0")
    end
    table.insert(args, "-c")
    table.insert(args, "copy")
    table.insert(args, "-avoid_negative_ts")
    table.insert(args, "make_zero")
    table.insert(args, output_path)

    notify("書き出し中...", 9999)

    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
    }, function(success, result, error)
        if success and result and result.status == 0 then
            notify(string.format("書き出し完了: %s", output_path), 4)
        else
            notify("書き出し失敗。詳細はmpvログを確認してください", 5)
            msg.error(utils.to_string(result))
        end
        reset_points()
        close_menu()
    end)
end

local function on_menu_key()
    if not menu_active then
        open_menu()
        return
    end
    if start_time and end_time then
        if end_time <= start_time then
            notify("終了点が開始点より前です", 3)
            return
        end
        do_export()
    else
        notify("開始点と終了点を両方セットしてください", 3)
    end
end

mp.add_key_binding(opts.key_menu, "losslesscut-menu", on_menu_key)
