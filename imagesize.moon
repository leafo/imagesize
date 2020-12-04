
import C, Ct, Cg, P, Cmt from require "lpeg"

bytes = (...) -> P string.char ...

read_chars = (len) -> P len

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

scan_image_from_bytes = (bytes) ->
  out = PNG\match bytes
  if out
    return "png", out

  nil, "failed to detect image"


{ :scan_image_from_bytes }
