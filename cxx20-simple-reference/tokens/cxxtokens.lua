-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
--
-- SPDX-License-Identifier: Apache-2.0

-- Turn the typeset draft into a stream of tokens (JSON Lines).
--
-- \cxxmark{...} puts a user_defined whatsit carrying a string where it is
-- used. Each paragraph gets a "par" mark at its start. When a page is
-- shipped out, its box is walked in order: glyphs become text, interword
-- glue becomes a space, the end of a line becomes a "nl" token, marks become
-- "mark" tokens, and hyperref's destinations and links become "anchor",
-- "link" and "endlink" tokens. The page is then emptied of everything but
-- its \write nodes (and destinations), so that .aux, .idx, .out and the
-- other files are still written, and no glyph reaches the PDF.
--
-- The stream goes to the file named by the CXXTOKENS_OUT environment
-- variable, a path relative to the working directory; without it, nothing
-- is written (for the first run of the draft).

cxx = cxx or {}

local USER_ID = 0x63787878 -- "cxxx"
local WHATSIT = node.id("whatsit")
local USER_DEFINED = node.subtype("user_defined")
local GLYPH, GLUE, HLIST, VLIST, DISC, KERN =
  node.id("glyph"), node.id("glue"), node.id("hlist"), node.id("vlist"),
  node.id("disc"), node.id("kern")

local out_path = os.getenv("CXXTOKENS_OUT")
-- Recent LuaTeX applies openout_any to io.open too, so the path should be
-- relative to the working directory (run.sh moves the file afterwards).
local out = out_path and out_path ~= "" and assert(io.open(out_path, "w"),
  "cxxtokens.lua: cannot write " .. tostring(out_path))
local pending = {} -- text not yet written

local function json_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
    elseif c == '\n' then return '\\n' elseif c == '\t' then return '\\t'
    else return string.format('\\u%04x', c:byte()) end
  end) .. '"'
end

local function flush_text()
  if not out then pending = {} return end
  if #pending > 0 then
    out:write('{"text":', json_string(table.concat(pending)), '}\n')
    pending = {}
  end
end

local function emit(kind, value)
  flush_text()
  if not out then return end
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

-- Math. Each formula reaches mlist_to_hlist as a noad tree, after all
-- macros have been expanded. It is written back as TeX that MathJax reads,
-- with characters in Unicode, and the formula is replaced by a single mark.
local MATH_INLINE, MATH_DISPLAY = USER_ID + 1, USER_ID + 2
local NOAD, FRACTION, ACCENT, RADICAL, FENCE, STYLE, CHOICE =
  node.id("noad"), node.id("fraction"), node.id("accent"), node.id("radical"),
  node.id("fence"), node.id("style"), node.id("choice")
local MATH_CHAR, MATH_TEXT_CHAR, SUB_BOX, SUB_MLIST =
  node.id("math_char"), node.id("math_text_char"), node.id("sub_box"), node.id("sub_mlist")
local noad_kind = node.subtypes("noad")
local fence_kind = node.subtypes("fence")
local MU_GLUE = 99

-- Characters that mean something else in TeX.
local tex_special = { ["{"] = "\\{", ["}"] = "\\}", ["#"] = "\\#", ["%"] = "\\%",
  ["&"] = "\\&", ["_"] = "\\_", ["$"] = "\\$", ["\\"] = "\\backslash ",
  ["~"] = "\\sim ", ["^"] = "\\hat{}" }

-- Big operators and extensible delimiters in the math extension font have
-- glyph names such as summationdisplay or parenleftbig.
local function math_glyph(fontid, c)
  local dec = decoder_of(fontid)
  local s = dec and dec(c)
  if s then return s end
  local name = dummy_font_names[fontid] or ""
  local enc = font_enc[(name:gsub("%s.*", ""))]
  local slots = enc and slots_of(enc)
  local g = slots and slots[c]
  -- The bar of \mapsto (named mapsto in Latin Modern's encoding).
  if g == "mapstochar" or g == "mapsto" then return "\\mapstochar " end
  if g then
    local base = g:gsub("%..*", ""):gsub("display$", ""):gsub("text$", "")
      :gsub("[Bb]ig+$", ""):gsub("ex$", ""):gsub("[tb][pt]$", ""):gsub("mid$", "")
    s = unicode_of(base)
    if s then return s end
  end
  return string.format("\\x{%s:%d}", name, c)
end

-- The family of a text font in math selects a TeX alphabet command.
local function alphabet(fontid)
  local name = dummy_font_names[fontid] or ""
  if name:match("lmtt") then return "\\mathtt"
  elseif name:match("lmss") then return "\\mathsf"
  elseif name:match("bx") then return "\\mathbf"
  elseif name:match("lmri") then return "\\mathit"
  elseif name:match("^ec%-") or name:match("^rm%-") or name:match("^ts1%-") then return "\\mathrm"
  end
  return nil
end

local function math_char(n)
  local fontid = node.family_font(n.fam)
  local s = math_glyph(fontid, n.char)
  s = tex_special[s] or s
  local a = alphabet(fontid)
  if a and s:match("^%a$") then return a .. "{" .. s .. "}" end
  return s
end

-- MathJax takes these delimiters by name only.
local delim_name = { ["{"] = "\\{", ["}"] = "\\}", ["⌊"] = "\\lfloor", ["⌋"] = "\\rfloor",
  ["⌈"] = "\\lceil", ["⌉"] = "\\rceil", ["〈"] = "\\langle", ["〉"] = "\\rangle",
  ["⟨"] = "\\langle", ["⟩"] = "\\rangle", ["‖"] = "\\|", ["∥"] = "\\|",
  ["↑"] = "\\uparrow", ["↓"] = "\\downarrow", ["↕"] = "\\updownarrow",
  ["⇑"] = "\\Uparrow", ["⇓"] = "\\Downarrow", ["⇕"] = "\\Updownarrow",
  ["\\backslash "] = "\\backslash" }
local function delim(d)
  if not d then return "." end
  local s
  if d.small_char == 0 and d.small_fam == 0 then
    if d.large_char == 0 and d.large_fam == 0 then return "." end
    s = math_glyph(node.family_font(d.large_fam), d.large_char)
  else
    s = math_glyph(node.family_font(d.small_fam), d.small_char)
  end
  return delim_name[s] or s
end

local mlist_tex, box_text

local function field_tex(f)
  if not f then return "" end
  if f.id == MATH_CHAR or f.id == MATH_TEXT_CHAR then return math_char(f)
  elseif f.id == SUB_MLIST then return mlist_tex(f.head)
  elseif f.id == SUB_BOX then return box_text(f.head)
  end
  return ""
end

local function braced(f) return "{" .. field_tex(f) .. "}" end

local function scripts(n, s)
  if n.sub then s = s .. "_" .. braced(n.sub) end
  if n.sup then s = s .. "^" .. braced(n.sup) end
  return s
end

local accent_command = { circumflex = "\\hat", hat = "\\hat", tilde = "\\tilde",
  macron = "\\bar", dotaccent = "\\dot", dieresis = "\\ddot", acute = "\\acute",
  grave = "\\grave", breve = "\\breve", caron = "\\check", vector = "\\vec",
  ring = "\\mathring" }
local function accent_tex(a)
  if not a then return nil end
  local fontid = node.family_font(a.fam)
  local name = dummy_font_names[fontid] or ""
  local enc = font_enc[(name:gsub("%s.*", ""))] or builtin_enc[name:match("^%a+") or ""]
  local slots = enc and slots_of(enc)
  local g = slots and slots[a.char]
  g = g and g:gsub("%..*", ""):gsub("math$", ""):gsub("wide$", ""):gsub("wider$", "")
  return accent_command[g or ""] or ("\\overset{" .. math_glyph(fontid, a.char) .. "}")
end

local style_command = { display = "\\displaystyle ", text = "\\textstyle ",
  script = "\\scriptstyle ", scriptscript = "\\scriptscriptstyle " }

function mlist_tex(head)
  local out = {}
  for n in node.traverse(head) do
    local id = n.id
    if id == NOAD then
      local kind = noad_kind[n.subtype]
      local nucleus = n.nucleus
      local s = field_tex(nucleus)
      local single = nucleus and (nucleus.id == MATH_CHAR or nucleus.id == MATH_TEXT_CHAR)
      if kind == "opdisplaylimits" or kind == "oplimits" or kind == "opnolimits" then
        s = (single and s or "\\mathop{" .. s .. "}") ..
          (kind == "oplimits" and "\\limits " or kind == "opnolimits" and "\\nolimits " or "")
      elseif kind == "under" then s = "\\underline{" .. s .. "}"
      elseif kind == "over" then s = "\\overline{" .. s .. "}"
      elseif not single and (kind == "bin" or kind == "rel" or kind == "open" or kind == "close"
          or kind == "punct" or kind == "inner") then
        s = "\\math" .. kind .. "{" .. s .. "}"
      elseif not single and nucleus and nucleus.id == SUB_MLIST and (n.sub or n.sup) then
        s = "{" .. s .. "}"
      end
      out[#out + 1] = scripts(n, s)
    elseif id == FRACTION then
      local num, den = braced(n.num), braced(n.denom)
      local l, r = n.left and delim(n.left), n.right and delim(n.right)
      if n.width == 0 then
        out[#out + 1] = "\\genfrac{" .. (l or "") .. "}{" .. (r or "") .. "}{0pt}{}" .. num .. den
      elseif l or r then
        out[#out + 1] = "\\genfrac{" .. (l or "") .. "}{" .. (r or "") .. "}{}{}" .. num .. den
      else
        out[#out + 1] = "\\frac" .. num .. den
      end
    elseif id == RADICAL then
      local degree = n.degree and mlist_tex(n.degree.head or n.degree) or ""
      out[#out + 1] = scripts(n, "\\sqrt" .. (degree ~= "" and "[" .. degree .. "]" or "") .. braced(n.nucleus))
    elseif id == ACCENT then
      local a = accent_tex(n.accent or n.top_accent)
      out[#out + 1] = scripts(n, (a or "") .. braced(n.nucleus))
    elseif id == FENCE then
      local kind = fence_kind[n.subtype]
      local cmd = kind == "left" and "\\left" or kind == "right" and "\\right" or kind == "middle" and "\\middle"
      if cmd then out[#out + 1] = cmd .. delim(n.delim) .. " " end
    elseif id == STYLE then
      out[#out + 1] = style_command[n.style] or ""
    elseif id == CHOICE then
      out[#out + 1] = mlist_tex(n.text)
    elseif id == GLUE then
      local mu = n.subtype == MU_GLUE and n.width / 65536 or n.width / (655360 / 18)
      if mu >= 30 then out[#out + 1] = "\\qquad "
      elseif mu >= 15 then out[#out + 1] = "\\quad "
      elseif mu >= 4.5 then out[#out + 1] = "\\; "
      elseif mu >= 3.5 then out[#out + 1] = "\\: "
      elseif mu > 0 then out[#out + 1] = "\\, "
      elseif mu < 0 then out[#out + 1] = "\\! "
      end
    elseif id == KERN then
      if n.kern < 0 then out[#out + 1] = "\\! " end
    elseif id == HLIST or id == VLIST then
      out[#out + 1] = box_text(n.head)
    end
  end
  return table.concat(out)
end

local list_kind = {}
for i, name in pairs(node.subtypes("hlist")) do list_kind[name] = i end
local PENALTY = node.id("penalty")

local function is_math_mark(n)
  return n.id == WHATSIT and n.subtype == USER_DEFINED
    and (n.user_id == MATH_INLINE or n.user_id == MATH_DISPLAY)
end

-- The rows of an \halign packed in a vlist (array, cases, tabular), or nil.
local function alignment_rows(v)
  local rows = {}
  for r in node.traverse(v.head) do
    if r.id == HLIST and r.subtype == list_kind.alignment then rows[#rows + 1] = r end
  end
  return #rows > 0 and rows or nil
end

local array_tex

-- A box inside math (\text, \mbox, \hbox, \vcenter, a cell): runs of glyphs
-- as \text{...} or \texttt{...}, formulas nested in it as they are, and
-- alignments as array.
function box_text(head)
  local out, run, tt = {}, {}, false
  local function flush()
    local s = table.concat(run)
    if s:match("%S") then out[#out + 1] = (tt and "\\texttt{" or "\\text{") .. s .. "}" end
    run, tt = {}, false
  end
  local function collect(h)
    for n in node.traverse(h) do
      if n.id == GLYPH then
        if (dummy_font_names[n.font] or ""):match("lmtt") then tt = true end
        -- MathJax (without the textmacros extension) shows \text contents as
        -- they are, except \{, \} and $.
        run[#run + 1] = (glyph_text(n):gsub("[{}$]", "\\%0"))
      elseif n.id == GLUE then
        if n.width > 0 then run[#run + 1] = " " end
      elseif n.id == VLIST then
        local rows = alignment_rows(n)
        if rows then flush(); out[#out + 1] = array_tex(rows) else collect(n.head) end
      elseif n.id == HLIST then
        collect(n.head)
      elseif is_math_mark(n) then
        flush()
        local v = n.value
        if not v:match("^%s*$") and not v:match("^\\%a+style%s*$") then out[#out + 1] = "{" .. v .. "}" end
      end
    end
  end
  collect(head)
  flush()
  return table.concat(out)
end

function array_tex(rows)
  local lines, ncols = {}, 0
  for _, r in ipairs(rows) do
    local cells = {}
    for c in node.traverse(r.head) do
      if c.id == HLIST and c.subtype == list_kind.cell then cells[#cells + 1] = box_text(c.head) end
    end
    if #cells > ncols then ncols = #cells end
    lines[#lines + 1] = table.concat(cells, " & ")
  end
  return "\\begin{array}{" .. string.rep("l", ncols) .. "}" .. table.concat(lines, " \\\\ ") .. "\\end{array}"
end

-- Whether a list holds glyphs outside of formulas.
local function has_text(head)
  for x in node.traverse(head) do
    if x.id == GLYPH then return true end
    if (x.id == HLIST or x.id == VLIST) and has_text(x.head) then return true end
  end
  return false
end

-- A tabular is typeset as a formula holding an \halign in a \vcenter (or a
-- \vtop or \vbox for the [t] and [b] positions). Its cells hold text, while
-- each cell of a math array (array, cases) is a formula of its own. A
-- tabular is not math: it is typeset as usual.
local function is_tabular(head)
  local found = false
  for n in node.traverse(head) do
    if n.id == NOAD and n.nucleus and n.nucleus.id == SUB_BOX
        and n.nucleus.head and n.nucleus.head.id == VLIST and alignment_rows(n.nucleus.head) then
      local box = n.nucleus.head
      local rows = box and box.id == VLIST and alignment_rows(box)
      if not rows then return false end
      local text = false
      for _, r in ipairs(rows) do
        for c in node.traverse(r.head) do
          if c.id == HLIST and c.subtype == list_kind.cell and has_text(c.head) then text = true end
        end
      end
      if not text then return false end
      found = true
    elseif n.id == FENCE or n.id == GLUE or n.id == KERN or n.id == PENALTY or n.id == STYLE then
    elseif n.id == NOAD and not n.nucleus then
    else
      return false
    end
  end
  return found
end

local function tidy(s)
  local prev
  repeat
    prev = s
    -- \mathrm{a}\mathrm{b} -> \mathrm{ab}
    s = s:gsub("(\\math%a%a)(%b{})%1{", function(cmd, body) return cmd .. body:sub(1, -2) end)
  until s == prev
  -- \bigl( and friends: an empty \left X\right. in a box between mathopen/mathclose.
  s = s:gsub("\\math(%a+){{\\mathinner{\\left(.-) \\right%. }}}", function(kind, d)
    if kind == "open" then return "\\bigl" .. d .. " " elseif kind == "close" then return "\\bigr" .. d .. " " end
  end)
  s = s:gsub("{\\mathinner{\\left(.-) \\right%. }}", "\\big%1 ")
  s = s:gsub("\\mathopen{}", "")
  -- The bar of \mapsto is a glyph of its own.
  s = s:gsub("\\mapstochar%s*→", "\\mapsto ")
  -- A control word directly followed by a letter.
  s = s:gsub("(\\%a+)([\192-\255])", "%1 %2")
  return s
end

-- Whatsits of a formula that must survive it: \write nodes (a \label in an
-- equation), destinations, links, and "anchor" marks.
local math_keep = {}
for _, name in ipairs({ "open", "write", "close", "late_lua", "pdf_dest",
    "pdf_start_link", "pdf_end_link" }) do
  math_keep[node.subtype(name)] = true
end
local function math_whatsits(head, list)
  for n in node.traverse(head) do
    if n.id == WHATSIT and (math_keep[n.subtype] or (n.subtype == USER_DEFINED
        and n.user_id == USER_ID and n.value:match("^anchor "))) then
      list[#list + 1] = node.copy(n)
    elseif n.id == HLIST or n.id == VLIST then
      math_whatsits(n.head, list)
    elseif n.id == NOAD or n.id == ACCENT or n.id == RADICAL or n.id == FRACTION then
      local fields = n.id == FRACTION and { n.num, n.denom } or { n.nucleus, n.sub, n.sup }
      for i = 1, #fields + 3 do
        local f = fields[i]
        if f and (f.id == SUB_MLIST or f.id == SUB_BOX) then math_whatsits(f.head, list) end
      end
    end
  end
  return list
end

luatexbase.add_to_callback("mlist_to_hlist", function(head, display_type, penalties)
  if is_tabular(head) then return node.mlist_to_hlist(head, display_type, penalties) end
  local n = node.new(WHATSIT, USER_DEFINED)
  n.user_id = display_type == "display" and MATH_DISPLAY or MATH_INLINE
  n.type = 115
  n.value = tidy(mlist_tex(head))
  local tail = n
  for _, w in ipairs(math_whatsits(head, {})) do n, tail = node.insert_after(n, tail, w) end
  node.flush_list(head)
  return n
end, "cxx math as TeX")

local link_target
local PDF_DEST, PDF_START_LINK, PDF_END_LINK =
  node.subtype("pdf_dest"), node.subtype("pdf_start_link"), node.subtype("pdf_end_link")

-- The target of a link: a destination name in this document, or a URI.
function link_target(n)
  local a = n.action
  if a then
    if a.action_type == 1 then -- goto
      local name = a.named_id == 1 and a.action_id or ("num:" .. tostring(a.action_id))
      if a.file and a.file ~= "" then return a.file .. "#" .. name end
      return name
    elseif a.action_type == 3 and a.data then -- user
      local uri = a.data:match("/URI%s*%((.-)%)")
      if uri then return uri end
      return a.data
    end
  end
  return n.link_attr or ""
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
    elseif id == WHATSIT and n.subtype == PDF_DEST then
      emit("anchor", n.named_id == 1 and n.dest_id or ("num:" .. tostring(n.dest_id)))
    elseif id == WHATSIT and n.subtype == PDF_START_LINK then
      emit("link", link_target(n))
    elseif id == WHATSIT and n.subtype == PDF_END_LINK then
      emit("endlink")
    elseif id == WHATSIT and n.subtype == USER_DEFINED then
      if n.user_id == USER_ID then
        if n.value == "par" then emit("par")
        elseif n.value:match("^anchor ") then emit("anchor", n.value:sub(8))
        else emit("mark", n.value) end
      elseif n.user_id == MATH_INLINE then emit("math", n.value)
      elseif n.user_id == MATH_DISPLAY then emit("displaymath", n.value)
      end
    end
  end
end

-- Nodes kept on the shipped-out page.
local keep = {}
for _, name in ipairs({ "open", "write", "close", "late_lua", "pdf_dest" }) do
  keep[node.subtype(name)] = true
end

local function kept_nodes(head, list)
  for n in node.traverse(head) do
    if n.id == WHATSIT and keep[n.subtype] then
      list[#list + 1] = node.copy(n)
    elseif n.id == HLIST or n.id == VLIST then
      kept_nodes(n.head, list)
    elseif n.id == DISC and n.replace then
      kept_nodes(n.replace, list)
    end
  end
  return list
end

function cxx.shipout(boxnumber)
  local box = tex.getbox(boxnumber)
  if not box then return end
  if out then
    walk(box.head, box.id == VLIST)
    flush_text()
  end
  local list = kept_nodes(box.head, {})
  local head
  for i = #list, 1, -1 do list[i].next = head; head = list[i] end
  local old = box.head
  box.head = head
  node.flush_list(old)
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

function cxx.finish() flush_text(); if out then out:close() end end
