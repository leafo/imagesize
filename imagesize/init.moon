
import C, Ct, Cg, P, R, Cmt, V from require "lpeg"

bytes = (...) -> P string.char ...
byte_range = (a, b) -> R string.char a, b

read_chars = (len) -> P len

-- debug function to read the next n bytes off the current position
preview_bytes = (len=10, hex=true) ->
  Cmt C(P(len)), (_, pos, str) ->
    bs = { str\byte 1, len }
    if hex
      bs = [string.format "%x", b for b in *bs]

    print table.concat bs, " "
    true

-- decode len bytes of str starting at pos to a Lua number. Only * and + are
-- used so the result stays an integer on Lua 5.3+, where 2^n is a float
decode_int = (str, pos, len, endian="big") ->
  first, last, step = switch endian
    when "big"
      pos, pos + len - 1, 1
    when "little"
      pos + len - 1, pos, -1
    else
      error "unknown endian"

  out = 0
  for i=first, last, step
    out = out * 256 + str\byte i

  out

-- read the bytes in big endian and capture to a Lua number
read_int = (len, endian="big") ->
  P(len) / (str) -> decode_int str, 1, len, endian


-- PNG: https://en.wikipedia.org/wiki/Portable_Network_Graphics#File_format

-- the IHDR chunk should be the first chunk and contain the size information
-- entire chunk is 13 bytes but we only care about the front of it
PNG_IHDR = Ct Cg(read_int(4), "width") * Cg(read_int(4), "height") * Cg(read_int(1), "bit_depth")

-- the length, chunk name, then the chunk data
PNG_IHDR_CHUNK = P(4) * P("IHDR") * PNG_IHDR

-- reads over a chunk and does nothing
PNG_CHUNK = Cmt Ct(Cg(read_int(4), "length") * Cg(read_chars(4), "type")), (subject, pos, cap) ->
  -- + 4 to ignore the CRC footer on the chunk
  out = pos + cap.length + 4

  if out > #subject
    return false

  out

-- spec says we should see the IHDR chunk first, but this can be used to pass over other chunks if it's out of order for some reason
PNG = bytes(137, 80, 78, 71, 13, 10, 26, 10) * P {
  PNG_IHDR_CHUNK + PNG_CHUNK * V(1)
}

-- JPG: https://en.wikipedia.org/wiki/JPEG#JPEG_files

-- any number of 0xFF fill bytes may precede a marker
JPEG_MARKER = bytes(255)^1

-- segments that do not have a 2 bytes length
JPEG_SOI = bytes 255, 216
JPEG_EOI = JPEG_MARKER * bytes 217
JPEG_SOS = JPEG_MARKER * bytes 218 -- the length of this goes to end of file

-- this only parses the front of the frame data, more stuff follows but we don't care
JPEG_FRAME = Ct Cg(read_int(1), "bit_depth") * Cg(read_int(2), "height") * Cg(read_int(2), "width")
-- SOF0-SOF15, the gaps are DHT (C4), JPG (C8), and DAC (CC)
JPEG_SOF = byte_range(192, 195) + byte_range(197, 199) + byte_range(201, 203) + byte_range(205, 207)
JPEG_FRAME_SEGMENT = JPEG_MARKER * JPEG_SOF * P(2) * JPEG_FRAME

-- this reads over a segment and does nothing, we use the frame segment grammar above to parse the data from the frame
JPEG_SEGMENT = JPEG_MARKER * Cmt Ct(Cg(read_int(1), "marker") * Cg(read_int(2), "length")), (subject, pos, cap) ->
  -- advance past the dylanmic length of the segment
  -- the length here includes the two bytes for the length field
  -- LPeg raises an error if the returned position moves backwards
  return false if cap.length < 2
  real_length = cap.length - 2
  out = pos + real_length

  if out > #subject
    return false

  out

-- EXIF: https://www.cipa.jp/std/documents/e/DC-008-2012_E.pdf
-- APP1 data is "Exif\0\0" followed by a TIFF header and IFD0, which is where
-- the orientation tag lives. Returns nil if anything is missing or out of
-- bounds, stop is the index of the last byte of the segment
parse_exif_orientation = (str, start, stop) ->
  return unless start + 5 <= stop and str\sub(start, start + 5) == "Exif\0\0"

  tiff = start + 6
  return unless tiff + 7 <= stop

  endian = switch str\sub tiff, tiff + 1
    when "II" then "little"
    when "MM" then "big"
    else return

  return unless decode_int(str, tiff + 2, 2, endian) == 42

  ifd = tiff + decode_int str, tiff + 4, 4, endian
  return unless ifd + 1 <= stop

  for i=0, decode_int(str, ifd, 2, endian) - 1
    entry = ifd + 2 + i * 12
    return if entry + 11 > stop

    if decode_int(str, entry, 2, endian) == 0x0112
      orientation = decode_int str, entry + 8, 2, endian
      return if orientation < 1 or orientation > 8
      return orientation

JPEG_EXIF_SEGMENT = JPEG_MARKER * bytes(225) * Cmt read_int(2), (subject, pos, length) ->
  return false if length < 2
  out = pos + length - 2
  return false if out > #subject
  out, parse_exif_orientation subject, pos, out - 1

-- try to read segments until we get a frame segments. The first orientation
-- found in an APP1 segment is merged into the frame
JPEG = JPEG_SOI * P({
  JPEG_FRAME_SEGMENT + JPEG_EXIF_SEGMENT * V(1) + (JPEG_SEGMENT - JPEG_SOS - JPEG_EOI) * V(1)
}) / (...) ->
  caps = {...}
  frame = caps[#caps]
  frame.orientation = caps[1] if #caps > 1
  frame

-- GIF: https://en.wikipedia.org/wiki/GIF#File_format
-- https://www.w3.org/Graphics/GIF/spec-gif89a.txt
-- http://giflib.sourceforge.net/whatsinagif/bits_and_bytes.html
-- gif uses little endian

-- unpacks each bit into var with the single character name at the index of the bit
-- eg. unpack_byte("aaaabbbb", string.char(100))  -> { a = 6 [left 4 bits], b = 4 [right 4 bits]}
unpack_byte = (index, char) ->
  assert #index == 8, "index should be 8 chars long, assignment for each bit"

  num = string.byte char
  out = { }
  counts = { }

  for i=8,1,-1
    k = index\sub i,i

    bit = if num % 2 == 1
      1
    else
      0

    out[k] or= 0
    counts[k] or= 0
    out[k] = out[k] + bit * 2 ^ counts[k]
    counts[k] += 1

    -- remove odd bit, shift right by 1
    num = (num - bit) / 2

  out

-- Matches how Firefox and Chromium size a GIF: use the logical screen, unless
-- the first frame is larger than it or the file is GIF87a, since some files
-- have a bogus logical screen size
gif_size = (version, screen_width, screen_height, frame) ->
  if frame.width == 0 or frame.height == 0
    return { width: screen_width, height: screen_height }

  if version == "87a" or frame.width > screen_width or frame.height > screen_height
    return frame

  { width: screen_width, height: screen_height }

GIF = P({
  P("GIF") * C(P("87a") + P("89a")) * V("logical_screen_descriptor") * V"rest"

  rest: V"image_descriptor" + V"extension" * V"rest"

  image_descriptor: bytes(44) * P(2) * P(2) * Ct Cg(read_int(2, "little"), "width") * Cg(read_int(2, "little"), "height")

  -- every extension (graphic control, comment, application, plain text, or
  -- unknown) is a label byte followed by sub-blocks, so they can all be
  -- skipped the same way
  extension: bytes(33) * P(1) * V"sub_blocks"

  -- each sub-block is a length byte then that many bytes, terminated by a 0 length
  sub_blocks: Cmt(read_int(1), (subject, pos, length) ->
    return false if length == 0
    out = pos + length
    return false if out > #subject
    out
  )^0 * bytes(0)

  -- two two-byte sizes then packed byte describing global color table, then 2 more remaining bytes
  logical_screen_descriptor: read_int(2, "little") * read_int(2, "little") * Cmt C(P(1)) * P(2), (subject, pos, byte) ->
    {
      a: global_color_table_flag
      b: color_resolution
      c: sort_flag
      d: size_of_global_color_table
    } = unpack_byte "abbbcddd", byte

    if global_color_table_flag == 1
      -- consome the global color table
      global_color_table_size = 3 * 2^(size_of_global_color_table+1)
      out = pos + global_color_table_size
      return false if out > #subject
      out
    else
      true
}) / gif_size

-- WebP: https://developers.google.com/speed/webp/docs/riff_container
-- the first chunk determines how the size is stored

-- lossy: 3 byte frame tag, start code, then 14 bit dimensions with 2 bit scale
webp_vp8_size = read_int(2, "little") / (n) -> n % 0x4000
WEBP_VP8 = P("VP8 ") * P(4) * P(3) * bytes(157, 1, 42) * Ct Cg(webp_vp8_size, "width") * Cg(webp_vp8_size, "height")

-- lossless: signature byte, then 14 bits each of width - 1 and height - 1
WEBP_VP8L = P("VP8L") * P(4) * bytes(47) * read_int(4, "little") / (n) ->
  {
    width: n % 0x4000 + 1
    height: math.floor(n / 0x4000) % 0x4000 + 1
  }

-- extended (alpha, animation, metadata): flags and reserved bytes, then 24 bit canvas width - 1 and height - 1
webp_vp8x_size = read_int(3, "little") / (n) -> n + 1
WEBP_VP8X = P("VP8X") * P(4) * P(4) * Ct Cg(webp_vp8x_size, "width") * Cg(webp_vp8x_size, "height")

WEBP = P("RIFF") * P(4) * P("WEBP") * (WEBP_VP8 + WEBP_VP8L + WEBP_VP8X)

-- BMP: https://en.wikipedia.org/wiki/BMP_file_format
-- the 14 byte file header is followed by a DIB header whose size identifies its version

bmp_header_size = (n) -> bytes n, 0, 0, 0

-- OS/2 1.x BITMAPCOREHEADER has unsigned 16 bit dimensions
BMP_CORE = bmp_header_size(12) * Ct Cg(read_int(2, "little"), "width") * Cg(read_int(2, "little"), "height") * P(2) * Cg(read_int(2, "little"), "bit_depth")

-- every later header (OS/2 2.x, BITMAPINFOHEADER through BITMAPV5HEADER) has
-- signed 32 bit dimensions, where a negative height means rows are stored top-down
BMP_INFO_SIZES = bmp_header_size(16) + bmp_header_size(40) + bmp_header_size(52) + bmp_header_size(56) + bmp_header_size(64) + bmp_header_size(108) + bmp_header_size(124)
BMP_INFO = BMP_INFO_SIZES * Cmt read_int(4, "little") * read_int(4, "little") * P(2) * read_int(2, "little"), (subject, pos, width, height, bit_depth) ->
  return false if width >= 0x80000000
  height = 0x100000000 - height if height >= 0x80000000
  true, { :width, :height, :bit_depth }

BMP = P("BM") * P(12) * (BMP_CORE + BMP_INFO)

detect_image_from_bytes = (bytes) ->
  out = PNG\match bytes
  if out
    return "png", out

  out = JPEG\match bytes
  if out
    return "jpeg", out

  out = GIF\match bytes
  if out
    return "gif", out

  out = WEBP\match bytes
  if out
    return "webp", out

  out = BMP\match bytes
  if out
    return "bmp", out

  nil, "failed to detect image"

{ :detect_image_from_bytes, :JPEG, :GIF, :PNG, :WEBP, :BMP, version: "1.0.0" }
