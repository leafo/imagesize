
import C, Ct, Cg, P, Cmt, V from require "lpeg"

bytes = (...) -> P string.char ...

read_chars = (len) -> P len

-- debug function to read the next n bytes off the current position
preview_bytes = (len=10, hex=true) ->
  Cmt C(P(len)), (_, pos, str) ->
    bs = { str\byte 1, len }
    if hex
      bs = [string.format "%x", b for b in *bs]

    print table.concat bs, " "
    true

-- read the bytes and convert it to a number for capture
-- big endian
read_int = (len) ->
  P(len) / (str) ->
    out = 0
    offset = len - 1

    for b in *{ str\byte 1, len }
      out += 2^(8 * offset) * b
      offset -= 1

    out


-- the IHDR chunk should be the first chunk and contain the size information
-- entire chunk is 13 bytes but we only care about the front of it
PNG_IHDR = Ct Cg(read_int(4), "width") * Cg(read_int(4), "height") * Cg(read_int(1), "bit_depth")

PNG_CHUNK = Cmt Ct(Cg(read_int(4), "length") * Cg(read_chars(4), "type")), (subject, pos, cap) ->
  switch cap.type
    when "IHDR"
      chunk_data = subject\sub pos, pos + cap.length - 1
      ihdr = PNG_IHDR\match chunk_data
      unless ihdr
        return nil, "failed to parse ihdr chunk"

      -- + 4 to ignore the CRC footer on the chunk
      return pos + cap.length + 4, ihdr
    else
      error "unknown chunk type: #{cap.type}"

  true

PNG = bytes(137, 80, 78, 71, 13, 10, 26, 10) * PNG_CHUNK

-- segments that do not have a 2 bytes length
JPEG_SOI = bytes 255, 216
JPEG_EOI = bytes 255, 217
JPEG_SOS = bytes 255, 218 -- the length of this goes to end of file

-- this only parses the front of the frame data, more stuff follows but we don't care
JPEG_FRAME = Ct Cg(read_int(1), "bit_depth") * Cg(read_int(2), "height") * Cg(read_int(2), "width")
-- SOF0, SOF1, SOF2
JPEG_FRAME_SEGMENT = bytes(255) * (bytes(192) + bytes(193) + bytes(194)) * P(2) * JPEG_FRAME

-- this reads over a segment and does nothing, we use the frame segment grammar above to parse the data from the frame
JPEG_SEGMENT = bytes(255) * Cmt Ct(Cg(read_int(1), "marker") * Cg(read_int(2), "length")), (subject, pos, cap) ->
  -- print ">>> matched segment @ #{pos} [#{string.format "%x", cap.marker}]"

  -- the length here includes the two bytes for the length field
  real_length = cap.length - 2

  -- example of how you would parse the segment...
  -- segment_data = subject\sub pos, pos + real_length - 1
  -- -- 192: 0xc0 Start Of Frame (baseline DCT)
  -- -- 194: 0xc2 Start Of Frame (progressive DCT)
  -- switch cap.marker
  --   when 192, 194
  --     frame = JPEG_FRAME\match segment_data
  --     require("moon").p frame
  --     unless frame
  --       return nil, "failed to parse frame"
  --   -- 254: 0xFE Comment
  --   when 254
  --     nil

  return pos + real_length

-- try to read segments until we get a frame segments
JPEG = JPEG_SOI * P {
  JPEG_FRAME_SEGMENT + (JPEG_SEGMENT - JPEG_SOS - JPEG_EOI) * V(1)
}

scan_image_from_bytes = (bytes) ->
  out = PNG\match bytes
  if out
    return "png", out

  out = JPEG\match bytes
  if out
    return "jpeg", out

  nil, "failed to detect image"

{ :scan_image_from_bytes }
