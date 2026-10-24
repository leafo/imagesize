local MAX_TOP_LEVEL_BOXES = 64
local MAX_MOOV_SIZE = 8 * 1024 * 1024
local MAX_TRACKS = 64
local u32
u32 = function(str, pos)
  local a, b, c, d = str:byte(pos, pos + 3)
  if not (d) then
    return 
  end
  return ((a * 256 + b) * 256 + c) * 256 + d
end
local u64
u64 = function(str, pos)
  local hi = u32(str, pos)
  local lo = u32(str, pos + 4)
  if not (hi and lo) then
    return 
  end
  return hi * 0x100000000 + lo
end
local s32
s32 = function(str, pos)
  local n = u32(str, pos)
  if not (n) then
    return 
  end
  return n >= 0x80000000 and n - 0x100000000 or n
end
local read_box_header
read_box_header = function(str, pos, remaining)
  if remaining < 8 then
    return 
  end
  local size = u32(str, pos)
  if not (size) then
    return false
  end
  local box_type = str:sub(pos + 4, pos + 7)
  local header_size = 8
  if size == 1 then
    if remaining < 16 then
      return false
    end
    size = u64(str, pos + 8)
    header_size = 16
  elseif size == 0 then
    size = remaining
  end
  if not size or size < header_size or size > remaining then
    return false
  end
  return box_type, header_size, size
end
local MALFORMED = { }
local each_box
each_box = function(data, start_pos, stop_pos)
  local pos = start_pos
  return function()
    local box_type, header_size, size = read_box_header(data, pos, stop_pos - pos + 1)
    if box_type == false then
      error(MALFORMED)
    end
    if not (box_type) then
      return 
    end
    local body_start = pos + header_size
    local body_stop = pos + size - 1
    pos = pos + size
    return box_type, body_start, body_stop
  end
end
local find_box
find_box = function(data, box_name, start_pos, stop_pos)
  for box_type, body_start, body_stop in each_box(data, start_pos, stop_pos) do
    if box_type == box_name then
      return body_start, body_stop
    end
  end
end
local parse_mvhd
parse_mvhd = function(data, start_pos, stop_pos)
  local timescale, duration_pos, duration_len
  if data:byte(start_pos) == 1 then
    timescale, duration_pos, duration_len = u32(data, start_pos + 20), start_pos + 24, 8
  else
    timescale, duration_pos, duration_len = u32(data, start_pos + 12), start_pos + 16, 4
  end
  if duration_pos + duration_len - 1 > stop_pos then
    return 
  end
  if data:sub(duration_pos, duration_pos + duration_len - 1) == ("\255"):rep(duration_len) then
    return 
  end
  local duration = duration_len == 8 and u64(data, duration_pos) or u32(data, duration_pos)
  if timescale == 0 or duration <= 0 then
    return 
  end
  return duration / timescale
end
local parse_tkhd
parse_tkhd = function(data, start_pos, stop_pos)
  local matrix = start_pos + (data:byte(start_pos) == 1 and 52 or 40)
  if matrix + 43 > stop_pos then
    return 
  end
  local a, b = s32(data, matrix), s32(data, matrix + 4)
  local c, d = s32(data, matrix + 12), s32(data, matrix + 16)
  local rotation
  if a == 0 and d == 0 and b > 0 and c < 0 then
    rotation = 90
  elseif a < 0 and d < 0 and b == 0 and c == 0 then
    rotation = 180
  elseif a == 0 and d == 0 and b < 0 and c > 0 then
    rotation = 270
  end
  local width = math.floor(u32(data, matrix + 36) / 0x10000)
  local height = math.floor(u32(data, matrix + 40) / 0x10000)
  return width, height, rotation
end
local parse_trak
parse_trak = function(data, start_pos, stop_pos)
  local track = { }
  local mdia_start, mdia_stop, minf_start, minf_stop
  for box_type, body_start, body_stop in each_box(data, start_pos, stop_pos) do
    local _exp_0 = box_type
    if "tkhd" == _exp_0 then
      if not (track.width) then
        track.width, track.height, track.rotation = parse_tkhd(data, body_start, body_stop)
      end
    elseif "mdia" == _exp_0 then
      if not (mdia_start) then
        mdia_start, mdia_stop = body_start, body_stop
      end
    end
  end
  if not (mdia_start) then
    return track
  end
  for box_type, body_start, body_stop in each_box(data, mdia_start, mdia_stop) do
    local _exp_0 = box_type
    if "hdlr" == _exp_0 then
      if not track.handler and body_start + 11 <= body_stop then
        track.handler = data:sub(body_start + 8, body_start + 11)
      end
    elseif "minf" == _exp_0 then
      if not (minf_start) then
        minf_start, minf_stop = body_start, body_stop
      end
    end
  end
  if not (minf_start) then
    return track
  end
  local stbl_start, stbl_stop = find_box(data, "stbl", minf_start, minf_stop)
  if not (stbl_start) then
    return track
  end
  local stsd_start, stsd_stop = find_box(data, "stsd", stbl_start, stbl_stop)
  if stsd_start and stsd_start + 7 <= stsd_stop and u32(data, stsd_start + 4) > 0 then
    local entry_start = stsd_start + 8
    local codec = read_box_header(data, entry_start, stsd_stop - entry_start + 1)
    if codec == false then
      error(MALFORMED)
    end
    track.codec = codec
  end
  return track
end
local parse_moov
parse_moov = function(data)
  local info = {
    tracks = { }
  }
  for box_type, body_start, body_stop in each_box(data, 1, #data) do
    local _exp_0 = box_type
    if "mvhd" == _exp_0 then
      info.duration = parse_mvhd(data, body_start, body_stop)
    elseif "trak" == _exp_0 then
      if #info.tracks >= MAX_TRACKS then
        return nil, "too many tracks"
      end
      table.insert(info.tracks, parse_trak(data, body_start, body_stop))
    end
  end
  return info
end
local detect_mp4
detect_mp4 = function(read, file_size)
  local offset = 0
  local brand, moov
  for i = 1, MAX_TOP_LEVEL_BOXES do
    if offset >= file_size then
      break
    end
    local header_len = math.min(16, file_size - offset)
    local header = read(offset, header_len)
    if not (header and #header == header_len) then
      return nil, "failed to read file"
    end
    if i == 1 then
      if not (header:sub(5, 8) == "ftyp" and #header >= 12 and u32(header, 1) >= 12) then
        return nil, "not an mp4 file"
      end
      brand = header:sub(9, 12)
    end
    local box_type, header_size, size = read_box_header(header, 1, file_size - offset)
    if not (box_type) then
      return nil, "malformed mp4 file"
    end
    if box_type == "moov" then
      local moov_size = size - header_size
      if moov_size > MAX_MOOV_SIZE then
        return nil, "mp4 metadata too large"
      end
      local body = read(offset + header_size, moov_size)
      if not (body and #body == moov_size) then
        return nil, "failed to read mp4 metadata"
      end
      local ok, moov_or_err, err = pcall(parse_moov, body)
      if not (ok) then
        if moov_or_err == MALFORMED then
          return nil, "malformed mp4 file"
        end
        error(moov_or_err, 0)
      end
      moov = moov_or_err
      if not (moov) then
        return nil, err
      end
      break
    end
    offset = offset + size
  end
  if not (brand) then
    return nil, "not an mp4 file"
  end
  if not (moov) then
    if offset < file_size then
      return nil, "too many top-level boxes"
    end
    return nil, "missing mp4 metadata"
  end
  local video
  local _list_0 = moov.tracks
  for _index_0 = 1, #_list_0 do
    local track = _list_0[_index_0]
    if track.handler == "vide" and track.width and track.width > 0 and track.height > 0 then
      video = track
      break
    end
  end
  if not (video) then
    return nil, "no video track"
  end
  return {
    brand = brand,
    width = video.width,
    height = video.height,
    rotation = video.rotation,
    duration = moov.duration,
    tracks = moov.tracks
  }
end
local detect_mp4_from_bytes
detect_mp4_from_bytes = function(bytes)
  return detect_mp4((function(offset, length)
    return bytes:sub(offset + 1, offset + length)
  end), #bytes)
end
return {
  detect_mp4 = detect_mp4,
  detect_mp4_from_bytes = detect_mp4_from_bytes
}
