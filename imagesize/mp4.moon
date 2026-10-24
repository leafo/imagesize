-- MP4 (ISO BMFF): https://en.wikipedia.org/wiki/ISO_base_media_file_format
-- The metadata box (moov) is often at the end of the file, so reads go
-- through a callback instead of a byte prefix, letting the caller fetch only
-- the box headers and moov from remote storage

MAX_TOP_LEVEL_BOXES = 64
MAX_MOOV_SIZE = 8 * 1024 * 1024
MAX_TRACKS = 64

u32 = (str, pos) ->
  a, b, c, d = str\byte pos, pos + 3
  return unless d
  ((a * 256 + b) * 256 + c) * 256 + d

u64 = (str, pos) ->
  hi = u32 str, pos
  lo = u32 str, pos + 4
  return unless hi and lo
  hi * 0x100000000 + lo

s32 = (str, pos) ->
  n = u32 str, pos
  return unless n
  n >= 0x80000000 and n - 0x100000000 or n

-- remaining is the number of bytes from pos to the end of the parent.
-- Returns box_type, header_size, size, or nil if there is no room for a
-- header, or false if the header is invalid
read_box_header = (str, pos, remaining) ->
  return if remaining < 8
  size = u32 str, pos
  return false unless size
  box_type = str\sub pos + 4, pos + 7
  header_size = 8

  if size == 1
    return false if remaining < 16
    size = u64 str, pos + 8
    header_size = 16
  elseif size == 0
    -- box extends to the end of its parent
    size = remaining

  return false if not size or size < header_size or size > remaining
  box_type, header_size, size

-- thrown by each_box and caught in detect_mp4, so a bad box anywhere fails the
-- whole parse instead of silently ending iteration of its parent
MALFORMED = {}

-- iterates the boxes between start_pos and stop_pos (inclusive), yields
-- box_type, body_start, body_stop. Fewer than 8 trailing bytes are treated
-- as padding
each_box = (data, start_pos, stop_pos) ->
  pos = start_pos
  ->
    box_type, header_size, size = read_box_header data, pos, stop_pos - pos + 1
    error MALFORMED if box_type == false
    return unless box_type
    body_start = pos + header_size
    body_stop = pos + size - 1
    pos += size
    box_type, body_start, body_stop

find_box = (data, box_name, start_pos, stop_pos) ->
  for box_type, body_start, body_stop in each_box data, start_pos, stop_pos
    if box_type == box_name
      return body_start, body_stop

parse_mvhd = (data, start_pos, stop_pos) ->
  local timescale, duration_pos, duration_len
  if data\byte(start_pos) == 1
    timescale, duration_pos, duration_len = u32(data, start_pos + 20), start_pos + 24, 8
  else
    timescale, duration_pos, duration_len = u32(data, start_pos + 12), start_pos + 16, 4

  return if duration_pos + duration_len - 1 > stop_pos

  -- all ones means unknown
  return if data\sub(duration_pos, duration_pos + duration_len - 1) == "\255"\rep duration_len

  duration = duration_len == 8 and u64(data, duration_pos) or u32(data, duration_pos)

  -- fragmented files leave the duration as 0 and store it in the fragments.
  -- A 64 bit value of 2^63 or more wraps negative on Lua 5.3+
  return if timescale == 0 or duration <= 0
  duration / timescale

-- returns width, height, and the clockwise rotation from the display matrix
parse_tkhd = (data, start_pos, stop_pos) ->
  matrix = start_pos + (data\byte(start_pos) == 1 and 52 or 40)
  -- 3x3 matrix of 4 byte values, then 4 byte width and height
  return if matrix + 43 > stop_pos

  a, b = s32(data, matrix), s32(data, matrix + 4)
  c, d = s32(data, matrix + 12), s32(data, matrix + 16)

  rotation = if a == 0 and d == 0 and b > 0 and c < 0
    90
  elseif a < 0 and d < 0 and b == 0 and c == 0
    180
  elseif a == 0 and d == 0 and b < 0 and c > 0
    270

  -- dimensions are 16.16 fixed point
  width = math.floor u32(data, matrix + 36) / 0x10000
  height = math.floor u32(data, matrix + 40) / 0x10000
  width, height, rotation

parse_trak = (data, start_pos, stop_pos) ->
  track = {}
  local mdia_start, mdia_stop, minf_start, minf_stop

  for box_type, body_start, body_stop in each_box data, start_pos, stop_pos
    switch box_type
      when "tkhd"
        unless track.width
          track.width, track.height, track.rotation = parse_tkhd data, body_start, body_stop
      when "mdia"
        mdia_start, mdia_stop = body_start, body_stop unless mdia_start

  return track unless mdia_start

  for box_type, body_start, body_stop in each_box data, mdia_start, mdia_stop
    switch box_type
      when "hdlr"
        if not track.handler and body_start + 11 <= body_stop
          track.handler = data\sub body_start + 8, body_start + 11
      when "minf"
        minf_start, minf_stop = body_start, body_stop unless minf_start

  return track unless minf_start

  stbl_start, stbl_stop = find_box data, "stbl", minf_start, minf_stop
  return track unless stbl_start

  -- the codec is the type of the first sample entry, which follows the 4 byte
  -- version and flags and 4 byte entry count
  stsd_start, stsd_stop = find_box data, "stsd", stbl_start, stbl_stop
  if stsd_start and stsd_start + 7 <= stsd_stop and u32(data, stsd_start + 4) > 0
    entry_start = stsd_start + 8
    codec = read_box_header data, entry_start, stsd_stop - entry_start + 1
    error MALFORMED if codec == false
    track.codec = codec

  track

parse_moov = (data) ->
  info = { tracks: {} }

  for box_type, body_start, body_stop in each_box data, 1, #data
    switch box_type
      when "mvhd"
        info.duration = parse_mvhd data, body_start, body_stop
      when "trak"
        return nil, "too many tracks" if #info.tracks >= MAX_TRACKS
        table.insert info.tracks, parse_trak data, body_start, body_stop

  info

-- read: (offset, length) -> string, offset is 0 based. Must return exactly
-- length bytes, or nil on failure
-- file_size: total size of the file in bytes
detect_mp4 = (read, file_size) ->
  offset = 0
  local brand, moov

  for i=1, MAX_TOP_LEVEL_BOXES
    break if offset >= file_size

    header_len = math.min 16, file_size - offset
    header = read offset, header_len
    return nil, "failed to read file" unless header and #header == header_len

    if i == 1
      -- extended and to-end sizes are 0 and 1, which fail the size check
      unless header\sub(5, 8) == "ftyp" and #header >= 12 and u32(header, 1) >= 12
        return nil, "not an mp4 file"
      brand = header\sub 9, 12

    box_type, header_size, size = read_box_header header, 1, file_size - offset
    return nil, "malformed mp4 file" unless box_type

    if box_type == "moov"
      moov_size = size - header_size
      return nil, "mp4 metadata too large" if moov_size > MAX_MOOV_SIZE
      body = read offset + header_size, moov_size
      return nil, "failed to read mp4 metadata" unless body and #body == moov_size
      ok, moov_or_err, err = pcall parse_moov, body
      unless ok
        return nil, "malformed mp4 file" if moov_or_err == MALFORMED
        error moov_or_err, 0

      moov = moov_or_err
      return nil, err unless moov
      break

    offset += size

  return nil, "not an mp4 file" unless brand

  unless moov
    return nil, "too many top-level boxes" if offset < file_size
    return nil, "missing mp4 metadata"

  local video
  for track in *moov.tracks
    if track.handler == "vide" and track.width and track.width > 0 and track.height > 0
      video = track
      break

  return nil, "no video track" unless video

  {
    :brand
    width: video.width
    height: video.height
    rotation: video.rotation
    duration: moov.duration
    tracks: moov.tracks
  }

detect_mp4_from_bytes = (bytes) ->
  detect_mp4 ((offset, length) -> bytes\sub offset + 1, offset + length), #bytes

{ :detect_mp4, :detect_mp4_from_bytes }
