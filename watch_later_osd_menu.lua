--[[
    MPV "Watch Later" OSD Menu
    https://github.com/JKubovy/MPV-Watch-Later-OSD-Menu

    Author: Jan Kubovy <Xsichtik@gmail.com>
    License: Unlicense
    You need to have set 'write-filename-in-watch-later-config' in mpv.conf!
]]

local settings = {
	header = "",
	key_showmenu = "SHIFT+ENTER",

	key_moveup = "UP",
	key_movedown = "DOWN",
	key_movepageup = "PGUP",
	key_movepagedown = "PGDWN",
	key_movebegin = "HOME",
	key_moveend = "END",
	key_playfile = "ENTER",
	key_playfile_with_save = "SHIFT+ENTER",
	key_closeplaylist = "ESC",

	playlist_sliced_prefix = "...",
	playlist_sliced_suffix = "...",
	watch_later_folder = "~~home/watch_later",
	loop_cursor = true,
	showamount = 9,
	playlist_display_timeout = 0,
	style_ass_tags = "{\\fs12\\b0\\bord1}",
	text_padding_x = 10,
	text_padding_y = 30,

	normal_file = "○ %name",
	hovered_file = "● %name",
}

local utils = require("mp.utils")
local assdraw = require("mp.assdraw")

--global variables
local plen = 0
local cursor = 0
local files = nil

function parse_watch_later_files()	-- return table(index:(filepath, filename, mtime))
	local watch_later_path = mp.command_native({"expand-path", settings.watch_later_folder})
	local files = {}
	for _,file in ipairs(utils.readdir(watch_later_path, "files")) do
		local filepath = watch_later_path .. '/' .. file
		local first_line = io.lines(filepath)()
		if first_line:find("^#%s") == nil then
			mp.osd_message("You need to set 'write-filename-in-watch-later-config' in mpv.conf")
			return {}
		end
		local trimmed_first_line = first_line:gsub("#%s", "")
		files[#files+1] = {filepath = trimmed_first_line, filename = string.match(trimmed_first_line, "[/\\]?([^/\\]+)%..+$"), mtime = utils.file_info(filepath).mtime}
	end
	table.sort(files, function(a,b) return a.mtime > b.mtime end)
	if #files == 0 then
		mp.osd_message("No saved files")
		return {}
	end
	return files
end

function parse_filename(string, name, index)
	local base = tostring(plen):len()
	return string:gsub("%%N", "\\N")
		:gsub("%%pos", string.format("%0"..base.."d", index+1))
		:gsub("%%name", name)
	 	-- undo name escape
		:gsub("%%%%", "%%")
end

function parse_filename_by_index(index)
	local template = settings.normal_file
	if index == (cursor + 1) then
	template = settings.hovered_file
	end
	return parse_filename(template, files[index].filename, index)
end


function draw_playlist()
	local ass = assdraw.ass_new()
	local _, _, a = mp.get_osd_size()
	local h = 360
	local w = h * a
	ass:append(settings.style_ass_tags)

	-- TODO: padding should work even on different osd alignments
	if mp.get_property("osd-align-x") == "left" and mp.get_property("osd-align-y") == "top" then
		ass:pos(settings.text_padding_x, settings.text_padding_y)
	end

	if settings.header ~= "" then
		ass:append(settings.header.."\\N")
	end

	-- (visible index, playlist index) pairs of playlist entries that should be rendered
	local visible_indices = {}

	local one_based_cursor = cursor + 1
	table.insert(visible_indices, one_based_cursor)

	local offset = 1;
	local visible_indices_length = 1;
	while visible_indices_length < settings.showamount and visible_indices_length < plen do
		-- add entry for offset steps below the cursor
		local below = one_based_cursor + offset
		if below <= plen then
			table.insert(visible_indices, below)
			visible_indices_length = visible_indices_length + 1;
		end

		-- add entry for offset steps above the cursor
		-- also need to double check that there is still space, this happens if we have even numbered limit
		local above = one_based_cursor - offset
		if above >= 1 and visible_indices_length < settings.showamount and visible_indices_length < plen then
			table.insert(visible_indices, 1, above)
			visible_indices_length = visible_indices_length + 1;
		end

		offset = offset + 1
	end

	-- both indices are 1 based
	for display_index, playlist_index in pairs(visible_indices) do
		if display_index == 1 and playlist_index ~= 1 then
			ass:append(settings.playlist_sliced_prefix.."\\N")
		elseif display_index == settings.showamount and playlist_index ~= plen then
			ass:append(settings.playlist_sliced_suffix)
		else
			-- parse_filename_by_index expects 1 based index
			ass:append(parse_filename_by_index(playlist_index).."\\N")
		end
	end

	w,h = 0, 0
	mp.set_osd_ass(w, h, ass.text)
end

function moveup()
	if cursor~=0 then
		cursor = cursor-1
	elseif settings.loop_cursor then
		cursor = plen-1
	end
	draw_playlist()
end

function movedown()
	if cursor ~= plen-1 then
		cursor = cursor + 1
	elseif settings.loop_cursor then
		cursor = 0
	end
	draw_playlist()
end

function movepageup()
	if cursor == 0 then return end
	cursor = cursor - settings.showamount
	if cursor < 0 then cursor = 0 end
	draw_playlist()
end

function movepagedown()
	if cursor == plen-1 then return end
	cursor = cursor + settings.showamount
	if cursor >= plen then cursor = plen-1 end
	draw_playlist()
end

function movebegin()
	if cursor == 0 then return end
	cursor = 0
	draw_playlist()
end

function moveend()
	if cursor == plen-1 then return end
	cursor = plen-1
	draw_playlist()
end

function playfile()
	if plen == 0 then return end
	remove_keybinds()
	print(files[cursor+1].filepath)
	mp.commandv("loadfile", files[cursor+1].filepath)
end

function playfile_with_save()
	if plen == 0 then return end
	remove_keybinds()
	mp.command("write-watch-later-config")
	mp.commandv("loadfile", files[cursor+1].filepath)
end

function bind_keys(keys, name, func, opts)
	if keys == nil or keys == "" then
		mp.add_key_binding(keys, name, func, opts)
		return
	end
	local i = 1
	for key in keys:gmatch("[^%s]+") do
		local prefix = i == 1 and '' or i
		mp.add_key_binding(key, name..prefix, func, opts)
		i = i + 1
	end
end

function bind_keys_forced(keys, name, func, opts)
	if keys == nil or keys == "" then
		mp.add_forced_key_binding(keys, name, func, opts)
		return
	end
	local i = 1
	for key in keys:gmatch("[^%s]+") do
		local prefix = i == 1 and '' or i
		mp.add_forced_key_binding(key, name..prefix, func, opts)
		i = i + 1
	end
end

function unbind_keys(keys, name)
	if keys == nil or keys == "" then
		mp.remove_key_binding(name)
		return
	end
	local i = 1
	for key in keys:gmatch("[^%s]+") do
		local prefix = i == 1 and '' or i
		mp.remove_key_binding(name..prefix)
		i = i + 1
	end
end

function add_keybinds()
	bind_keys_forced(settings.key_moveup, 'moveup', moveup, "repeatable")
	bind_keys_forced(settings.key_movedown, 'movedown', movedown, "repeatable")
	bind_keys_forced(settings.key_movepageup, 'movepageup', movepageup, "repeatable")
	bind_keys_forced(settings.key_movepagedown, 'movepagedown', movepagedown, "repeatable")
	bind_keys_forced(settings.key_movebegin, 'movebegin', movebegin, "repeatable")
	bind_keys_forced(settings.key_moveend, 'moveend', moveend, "repeatable")
	bind_keys_forced(settings.key_playfile, 'playfile', playfile)
	bind_keys_forced(settings.key_playfile_with_save, 'playfile_with_save', playfile_with_save)
	bind_keys_forced(settings.key_closeplaylist, 'closeplaylist', remove_keybinds)
end

function remove_keybinds()
	keybindstimer:kill()
	keybindstimer = mp.add_periodic_timer(settings.playlist_display_timeout, remove_keybinds)
	keybindstimer:kill()
	mp.set_osd_ass(0, 0, "")
	unbind_keys(settings.key_moveup, 'moveup')
	unbind_keys(settings.key_movedown, 'movedown')
	unbind_keys(settings.key_movepageup, 'movepageup')
	unbind_keys(settings.key_movepagedown, 'movepagedown')
	unbind_keys(settings.key_movebegin, 'movebegin')
	unbind_keys(settings.key_moveend, 'moveend')
	unbind_keys(settings.key_playfile, 'playfile')
	unbind_keys(settings.key_playfile_with_save, 'playfile_with_save')
	unbind_keys(settings.key_closeplaylist, 'closeplaylist')
end

keybindstimer = mp.add_periodic_timer(settings.playlist_display_timeout, remove_keybinds)
keybindstimer:kill()

function load_globals()
	files = parse_watch_later_files()
	cursor = 0
	plen = #files
end

function showmenu()
	load_globals()
	if #files == 0 then

		return
	end
	add_keybinds()
	draw_playlist()
end

bind_keys(settings.key_showmenu, "showmenu", showmenu)
