-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
--
-- SPDX-License-Identifier: Apache-2.0

-- Turn the typeset draft into a stream of tokens (JSON Lines).
--
-- \cxxmark{...} puts a user_defined whatsit carrying a string where it is
-- used. Each paragraph gets a "par" mark at its start. When a page is
-- shipped out, its box is walked in order: glyphs become text, interword
-- glue becomes a space, the end of a line becomes a "nl" token, and marks
-- become "mark" tokens. The page itself is discarded by the caller.

cxx = cxx or {}

local USER_ID = 0x63787878 -- "cxxx"
local WHATSIT = node.id("whatsit")
local USER_DEFINED = node.subtype("user_defined")
local GLYPH, GLUE, HLIST, VLIST, DISC, KERN =
  node.id("glyph"), node.id("glue"), node.id("hlist"), node.id("vlist"),
  node.id("disc"), node.id("kern")

local out = assert(io.open(tex.jobname .. ".tokens.jsonl", "w"))
local pending = {} -- text not yet written

local function json_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
    elseif c == '\n' then return '\\n' elseif c == '\t' then return '\\t'
    else return string.format('\\u%04x', c:byte()) end
  end) .. '"'
end

local function flush_text()
  if #pending > 0 then
    out:write('{"text":', json_string(table.concat(pending)), '}\n')
    pending = {}
  end
end

local function emit(kind, value)
  flush_text()
  if value then
    out:write('{"', kind, '":', json_string(value), '}\n')
  else
    out:write('{"', kind, '":true}\n')
  end
end

function cxx.mark(s)
  local n = node.new(WHATSIT, USER_DEFINED)
  n.user_id = USER_ID
  n.type = 115 -- string
  n.value = s
  node.write(n)
end

-- Glyph slots are turned back into Unicode with the data TeX Live itself
-- uses: pdftex.map names the .enc file of each font, the .enc file names the
-- glyph in each slot, and the Adobe glyph lists give the Unicode text of
-- each glyph name.
local function read_file(name, format)
  local path = kpse.find_file(name, format)
  if not path then return nil end
  local f = io.open(path, "r"); local s = f:read("a"); f:close()
  return s
end

local glyph_unicode = {}
for _, list in ipairs({ "texglyphlist.txt", "glyphlist.txt" }) do
  local s = read_file(list, "map") or ""
  for name, codes in s:gmatch("\n([%w%._]+);([%x ]+)") do
    if not glyph_unicode[name] then
      local chars = {}
      for code in codes:gmatch("%x+") do chars[#chars + 1] = utf8.char(tonumber(code, 16)) end
      glyph_unicode[name] = table.concat(chars)
    end
  end
end
-- Glyph names follow the Adobe conventions: ".suffix" marks a variant of
-- the glyph, "a_b" a ligature of a and b, uniXXXX/uXXXXX a code point.
local function unicode_of(name)
  name = name:gsub("%..*", "")
  if glyph_unicode[name] then return glyph_unicode[name] end
  local hex = name:match("^uni(%x%x%x%x)$") or name:match("^u(%x%x%x%x%x?%x?)$")
  if hex then return utf8.char(tonumber(hex, 16)) end
  if name:find("_") then
    local parts = {}
    for part in name:gmatch("[^_]+") do
      local s = unicode_of(part)
      if not s then return nil end
      parts[#parts + 1] = s
    end
    return table.concat(parts)
  end
  return nil
end

local font_enc = {} -- tfm name -> enc file
for line in (read_file("pdftex.map", "map") or ""):gmatch("[^\n]+") do
  local tfm, enc = line:match("^(%S+).-<%[?(%S+%.enc)")
  if tfm then font_enc[tfm] = enc end
end
-- Fonts with a built-in encoding.
local builtin_enc = { cmbx = "lm-rm.enc", cmmib = "lm-mathit.enc" }

local enc_slots = {} -- enc file -> slot -> glyph name
local function slots_of(enc)
  if enc_slots[enc] == nil then
    local s = read_file(enc, "enc files")
    local slots = false
    if s then
      s = s:gsub("%%[^\n]*", "")
      local body = s:match("%[(.-)%]")
      slots = {}
      local i = 0
      for name in body:gmatch("/([^%s/%[%]]+)") do slots[i] = name; i = i + 1 end
    end
    enc_slots[enc] = slots
  end
  return enc_slots[enc]
end

-- Script capitals of rsfs (Unicode leaves holes for the letterlike symbols).
local script = { B = 0x212C, E = 0x2130, F = 0x2131, H = 0x210B, I = 0x2110,
  L = 0x2112, M = 0x2133, R = 0x211B }
local function rsfs_char(c)
  local ch = string.char(c)
  if not ch:match("%u") then return nil end
  return utf8.char(script[ch] or (0x1D49C + c - 65))
end

local font_decoder = {} -- font id -> function(slot) -> text or nil
local function decoder_of(id)
  local dec = font_decoder[id]
  if dec == nil then
    local name = dummy_font_names[id] or ""
    local base = name:match("^[^:]+"):gsub("%s.*", "")
    if base:match("^rsfs") then
      dec = rsfs_char
    else
      local enc = font_enc[base] or builtin_enc[base:match("^%a+")]
      local slots = enc and slots_of(enc)
      dec = slots and function(c) local g = slots[c]; return g and unicode_of(g) end or false
    end
    font_decoder[id] = dec
  end
  return dec
end

local function glyph_text(n)
  local dec = decoder_of(n.font)
  local s = dec and dec(n.char)
  if s then return s end
  return string.format("\\x{%s:%d}", dummy_font_names[n.font] or tostring(n.font), n.char)
end

local walk
function walk(head, in_vlist)
  for n in node.traverse(head) do
    local id = n.id
    if id == GLYPH then
      pending[#pending + 1] = glyph_text(n)
    elseif id == GLUE then
      if not in_vlist and n.width > 0 then pending[#pending + 1] = " " end
    elseif id == DISC then
      if n.replace then walk(n.replace, false) end
    elseif id == HLIST then
      walk(n.head, false)
      if in_vlist and n.subtype == 1 then emit("nl") end -- a line of a paragraph
    elseif id == VLIST then
      walk(n.head, true)
    elseif id == WHATSIT and n.subtype == USER_DEFINED and n.user_id == USER_ID then
      if n.value == "par" then emit("par") else emit("mark", n.value) end
    end
  end
end

function cxx.shipout(boxnumber)
  local box = tex.getbox(boxnumber)
  if box then walk(box.head, box.id == VLIST) end
  flush_text()
end

luatexbase.add_to_callback("pre_linebreak_filter", function(head)
  local n = node.new(WHATSIT, USER_DEFINED)
  n.user_id = USER_ID
  n.type = 115
  n.value = "par"
  -- The first node of a paragraph is its local_par node; the mark goes after it.
  local _, h = node.insert_after(head, head, n)
  return head
end, "cxx paragraph marks")

function cxx.finish() flush_text(); out:close() end
