local C, Ct, Cg, P, Cmt, V
do
  local _obj_0 = require("lpeg")
  C, Ct, Cg, P, Cmt, V = _obj_0.C, _obj_0.Ct, _obj_0.Cg, _obj_0.P, _obj_0.Cmt, _obj_0.V
end
local bytes
bytes = function(...)
  return P(string.char(...))
end
local read_chars
read_chars = function(len)
  return P(len)
end
local preview_bytes
preview_bytes = function(len, hex)
  if len == nil then
    len = 10
  end
  if hex == nil then
    hex = true
  end
  return Cmt(C(P(len)), function(_, pos, str)
    local bs = {
      str:byte(1, len)
    }
    if hex then
      do
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #bs do
          local b = bs[_index_0]
          _accum_0[_len_0] = string.format("%x", b)
          _len_0 = _len_0 + 1
        end
        bs = _accum_0
      end
    end
    print(table.concat(bs, " "))
    return true
  end)
end
local read_int
read_int = function(len, endian)
  if endian == nil then
    endian = "big"
  end
  return P(len) / function(str)
    local out = 0
    local _exp_0 = endian
    if "big" == _exp_0 then
      local offset = len - 1
      local _list_0 = {
        str:byte(1, len)
      }
      for _index_0 = 1, #_list_0 do
        local b = _list_0[_index_0]
        out = out + (2 ^ (8 * offset) * b)
        offset = offset - 1
      end
    elseif "little" == _exp_0 then
      for idx, b in ipairs({
        str:byte(1, len)
      }) do
        out = out + (2 ^ (8 * (idx - 1)) * b)
      end
    else
      error("unknown endian")
    end
    return out
  end
end
local PNG_IHDR = Ct(Cg(read_int(4), "width") * Cg(read_int(4), "height") * Cg(read_int(1), "bit_depth"))
local PNG_IHDR_CHUNK = P(4) * P("IHDR") * PNG_IHDR
local PNG_CHUNK = Cmt(Ct(Cg(read_int(4), "length") * Cg(read_chars(4), "type")), function(subject, pos, cap)
  local out = pos + cap.length + 4
  if out > #subject then
    return false
  end
  return out
end)
local PNG = bytes(137, 80, 78, 71, 13, 10, 26, 10) * P({
  PNG_IHDR_CHUNK + PNG_CHUNK * V(1)
})
local JPEG_SOI = bytes(255, 216)
local JPEG_EOI = bytes(255, 217)
local JPEG_SOS = bytes(255, 218)
local JPEG_FRAME = Ct(Cg(read_int(1), "bit_depth") * Cg(read_int(2), "height") * Cg(read_int(2), "width"))
local JPEG_FRAME_SEGMENT = bytes(255) * (bytes(192) + bytes(193) + bytes(194)) * P(2) * JPEG_FRAME
local JPEG_SEGMENT = bytes(255) * Cmt(Ct(Cg(read_int(1), "marker") * Cg(read_int(2), "length")), function(subject, pos, cap)
  local real_length = cap.length - 2
  local out = pos + real_length
  if out > #subject then
    return false
  end
  return out
end)
local JPEG = JPEG_SOI * P({
  JPEG_FRAME_SEGMENT + (JPEG_SEGMENT - JPEG_SOS - JPEG_EOI) * V(1)
})
local unpack_byte
unpack_byte = function(index, char)
  assert(#index == 8, "index should be 8 chars long, assignment for each bit")
  local num = string.byte(char)
  local out = { }
  local counts = { }
  for i = 8, 1, -1 do
    local k = index:sub(i, i)
    local bit
    if num % 2 == 1 then
      bit = 1
    else
      bit = 0
    end
    local _update_0 = k
    out[_update_0] = out[_update_0] or 0
    local _update_1 = k
    counts[_update_1] = counts[_update_1] or 0
    out[k] = out[k] + bit * 2 ^ counts[k]
    local _update_2 = k
    counts[_update_2] = counts[_update_2] + 1
    num = (num - bit) / 2
  end
  return out
end
local GIF = P({
  P("GIF") * (P("87a") + P("89a")) * V("logical_screen_descriptor") * V("rest"),
  rest = V("image_descriptor") + (V("graphic_extension") + V("comment_extension") + V("application_extension")) * V("rest"),
  image_descriptor = bytes(44) * P(2) * P(2) * Ct(Cg(read_int(2, "little"), "width") * Cg(read_int(2, "little"), "height")),
  graphic_extension = bytes(33, 249) * P(6),
  comment_extension = bytes(33, 254) * Cmt(read_int(1), function(subject, pos, length)
    if length == 0 then
      return false
    end
    local out = pos + length
    if out > #subject then
      return false
    end
    return out
  end) ^ 1 * bytes(0),
  application_extension = bytes(33, 255) * P(17),
  logical_screen_descriptor = P(2) * P(2) * Cmt(C(P(1)) * P(2), function(subject, pos, byte)
    local global_color_table_flag, color_resolution, sort_flag, size_of_global_color_table
    do
      local _obj_0 = unpack_byte("abbbcddd", byte)
      global_color_table_flag, color_resolution, sort_flag, size_of_global_color_table = _obj_0.a, _obj_0.b, _obj_0.c, _obj_0.d
    end
    if global_color_table_flag == 1 then
      local global_color_table_size = 3 * 2 ^ (size_of_global_color_table + 1)
      local out = pos + global_color_table_size
      if out > #subject then
        return false
      end
      return out
    else
      return true
    end
  end)
})
local scan_image_from_bytes
scan_image_from_bytes = function(bytes)
  local out = PNG:match(bytes)
  if out then
    return "png", out
  end
  out = JPEG:match(bytes)
  if out then
    return "jpeg", out
  end
  out = GIF:match(bytes)
  if out then
    return "gif", out
  end
  return nil, "failed to detect image"
end
return {
  scan_image_from_bytes = scan_image_from_bytes,
  JPEG = JPEG,
  GIF = GIF,
  PNG = PNG
}
