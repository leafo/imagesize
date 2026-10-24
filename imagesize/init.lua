local C, Ct, Cg, P, R, Cmt, V
do
  local _obj_0 = require("lpeg")
  C, Ct, Cg, P, R, Cmt, V = _obj_0.C, _obj_0.Ct, _obj_0.Cg, _obj_0.P, _obj_0.R, _obj_0.Cmt, _obj_0.V
end
local bytes
bytes = function(...)
  return P(string.char(...))
end
local byte_range
byte_range = function(a, b)
  return R(string.char(a, b))
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
local decode_int
decode_int = function(str, pos, len, endian)
  if endian == nil then
    endian = "big"
  end
  local first, last, step
  local _exp_0 = endian
  if "big" == _exp_0 then
    first, last, step = pos, pos + len - 1, 1
  elseif "little" == _exp_0 then
    first, last, step = pos + len - 1, pos, -1
  else
    first, last, step = error("unknown endian")
  end
  local out = 0
  for i = first, last, step do
    out = out * 256 + str:byte(i)
  end
  return out
end
local read_int
read_int = function(len, endian)
  if endian == nil then
    endian = "big"
  end
  return P(len) / function(str)
    return decode_int(str, 1, len, endian)
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
local JPEG_MARKER = bytes(255) ^ 1
local JPEG_SOI = bytes(255, 216)
local JPEG_EOI = JPEG_MARKER * bytes(217)
local JPEG_SOS = JPEG_MARKER * bytes(218)
local JPEG_FRAME = Ct(Cg(read_int(1), "bit_depth") * Cg(read_int(2), "height") * Cg(read_int(2), "width"))
local JPEG_SOF = byte_range(192, 195) + byte_range(197, 199) + byte_range(201, 203) + byte_range(205, 207)
local JPEG_FRAME_SEGMENT = JPEG_MARKER * JPEG_SOF * P(2) * JPEG_FRAME
local JPEG_SEGMENT = JPEG_MARKER * Cmt(Ct(Cg(read_int(1), "marker") * Cg(read_int(2), "length")), function(subject, pos, cap)
  if cap.length < 2 then
    return false
  end
  local real_length = cap.length - 2
  local out = pos + real_length
  if out > #subject then
    return false
  end
  return out
end)
local parse_exif_orientation
parse_exif_orientation = function(str, start, stop)
  if not (start + 5 <= stop and str:sub(start, start + 5) == "Exif\0\0") then
    return 
  end
  local tiff = start + 6
  if not (tiff + 7 <= stop) then
    return 
  end
  local endian
  local _exp_0 = str:sub(tiff, tiff + 1)
  if "II" == _exp_0 then
    endian = "little"
  elseif "MM" == _exp_0 then
    endian = "big"
  else
    return 
  end
  if not (decode_int(str, tiff + 2, 2, endian) == 42) then
    return 
  end
  local ifd = tiff + decode_int(str, tiff + 4, 4, endian)
  if not (ifd + 1 <= stop) then
    return 
  end
  for i = 0, decode_int(str, ifd, 2, endian) - 1 do
    local entry = ifd + 2 + i * 12
    if entry + 11 > stop then
      return 
    end
    if decode_int(str, entry, 2, endian) == 0x0112 then
      local orientation = decode_int(str, entry + 8, 2, endian)
      if orientation < 1 or orientation > 8 then
        return 
      end
      return orientation
    end
  end
end
local JPEG_EXIF_SEGMENT = JPEG_MARKER * bytes(225) * Cmt(read_int(2), function(subject, pos, length)
  if length < 2 then
    return false
  end
  local out = pos + length - 2
  if out > #subject then
    return false
  end
  return out, parse_exif_orientation(subject, pos, out - 1)
end)
local JPEG = JPEG_SOI * P({
  JPEG_FRAME_SEGMENT + JPEG_EXIF_SEGMENT * V(1) + (JPEG_SEGMENT - JPEG_SOS - JPEG_EOI) * V(1)
}) / function(...)
  local caps = {
    ...
  }
  local frame = caps[#caps]
  if #caps > 1 then
    frame.orientation = caps[1]
  end
  return frame
end
local gif_size
gif_size = function(version, screen_width, screen_height, frame)
  if frame.width == 0 or frame.height == 0 then
    return {
      width = screen_width,
      height = screen_height
    }
  end
  if version == "87a" or frame.width > screen_width or frame.height > screen_height then
    return frame
  end
  return {
    width = screen_width,
    height = screen_height
  }
end
local GIF = P({
  P("GIF") * C(P("87a") + P("89a")) * V("logical_screen_descriptor") * V("rest"),
  rest = V("image_descriptor") + V("extension") * V("rest"),
  image_descriptor = bytes(44) * P(2) * P(2) * Ct(Cg(read_int(2, "little"), "width") * Cg(read_int(2, "little"), "height")),
  extension = bytes(33) * P(1) * V("sub_blocks"),
  sub_blocks = Cmt(read_int(1), function(subject, pos, length)
    if length == 0 then
      return false
    end
    local out = pos + length
    if out > #subject then
      return false
    end
    return out
  end) ^ 0 * bytes(0),
  logical_screen_descriptor = read_int(2, "little") * read_int(2, "little") * Cmt(read_int(1) * P(2), function(subject, pos, packed)
    if packed < 128 then
      return true
    end
    local out = pos + 3 * 2 ^ (packed % 8 + 1)
    if out > #subject then
      return false
    end
    return out
  end)
}) / gif_size
local webp_vp8_size = read_int(2, "little") / function(n)
  return n % 0x4000
end
local WEBP_VP8 = P("VP8 ") * P(4) * P(3) * bytes(157, 1, 42) * Ct(Cg(webp_vp8_size, "width") * Cg(webp_vp8_size, "height"))
local WEBP_VP8L = P("VP8L") * P(4) * bytes(47) * read_int(4, "little") / function(n)
  return {
    width = n % 0x4000 + 1,
    height = math.floor(n / 0x4000) % 0x4000 + 1
  }
end
local webp_vp8x_size = read_int(3, "little") / function(n)
  return n + 1
end
local WEBP_VP8X = P("VP8X") * P(4) * P(4) * Ct(Cg(webp_vp8x_size, "width") * Cg(webp_vp8x_size, "height"))
local WEBP = P("RIFF") * P(4) * P("WEBP") * (WEBP_VP8 + WEBP_VP8L + WEBP_VP8X)
local bmp_header_size
bmp_header_size = function(n)
  return bytes(n, 0, 0, 0)
end
local BMP_CORE = bmp_header_size(12) * Ct(Cg(read_int(2, "little"), "width") * Cg(read_int(2, "little"), "height") * P(2) * Cg(read_int(2, "little"), "bit_depth"))
local BMP_INFO_SIZES = bmp_header_size(16) + bmp_header_size(40) + bmp_header_size(52) + bmp_header_size(56) + bmp_header_size(64) + bmp_header_size(108) + bmp_header_size(124)
local BMP_INFO = BMP_INFO_SIZES * Cmt(read_int(4, "little") * read_int(4, "little") * P(2) * read_int(2, "little"), function(subject, pos, width, height, bit_depth)
  if width >= 0x80000000 then
    return false
  end
  if height >= 0x80000000 then
    height = 0x100000000 - height
  end
  return true, {
    width = width,
    height = height,
    bit_depth = bit_depth
  }
end)
local BMP = P("BM") * P(12) * (BMP_CORE + BMP_INFO)
local detect_image_from_bytes
detect_image_from_bytes = function(bytes)
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
  out = WEBP:match(bytes)
  if out then
    return "webp", out
  end
  out = BMP:match(bytes)
  if out then
    return "bmp", out
  end
  return nil, "failed to detect image"
end
return {
  detect_image_from_bytes = detect_image_from_bytes,
  JPEG = JPEG,
  GIF = GIF,
  PNG = PNG,
  WEBP = WEBP,
  BMP = BMP,
  version = "1.0.0"
}
