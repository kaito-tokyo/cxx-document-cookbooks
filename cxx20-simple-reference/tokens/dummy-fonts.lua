-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
--
-- SPDX-License-Identifier: Apache-2.0

-- Every font requested is replaced by a font with 256 characters of
-- fixed size and enough parameters for math; nothing is read from disk.
local designsize = 655360 -- 10pt
dummy_font_names = {} -- font id -> requested name
local function dummy(name, size)
  if size < 0 then size = math.floor(-size * designsize / 1000) end
  local w, h, d = size // 2, size * 7 // 10, size // 5
  local characters = {}
  for i = 0, 255 do characters[i] = { width = w, height = h, depth = d } end
  local parameters = { slant = 0, space = size // 3, space_stretch = size // 6,
    space_shrink = size // 9, x_height = size // 2, quad = size, extra_space = size // 9 }
  for i = 8, 22 do parameters[i] = size // 10 end
  local id = font.define({ name = name, fullname = name, size = size, designsize = designsize,
    type = "real", characters = characters, parameters = parameters })
  dummy_font_names[id] = name
  return id
end
luatexbase.remove_from_callback("define_font", "luaotfload.define_font")
luatexbase.add_to_callback("define_font", dummy, "dummy fonts")
