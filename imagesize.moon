
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


-- PNG: https://en.wikipedia.org/wiki/Portable_Network_Graphics#File_format

-- the IHDR chunk should be the first chunk and contain the size information
-- entire chunk is 13 bytes but we only care about the front of it
PNG_IHDR = Ct Cg(read_int(4), "width") * Cg(read_int(4), "height") * Cg(read_int(1), "bit_depth")

-- the length, chunk name, then the chunk data
PNG_IHDR_CHUNK = P(4) * P("IHDR") * PNG_IHDR

-- reads over a chunk and does nothing
PNG_CHUNK = Cmt Ct(Cg(read_int(4), "length") * Cg(read_chars(4), "type")), (subject, pos, cap) ->
  -- + 4 to ignore the CRC footer on the chunk
  pos + cap.length + 4, ihdr

-- spec says we should see the IHDR chunk first, but this can be used to pass over other chunks if it's out of order for some reason
PNG = bytes(137, 80, 78, 71, 13, 10, 26, 10) * P {
  PNG_IHDR_CHUNK + PNG_CHUNK * V(1)
}

-- JPG: https://en.wikipedia.org/wiki/JPEG#JPEG_files

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
  -- advance past the dylanmic length of the segment
  -- the length here includes the two bytes for the length field
  real_length = cap.length - 2
  pos + real_length

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
