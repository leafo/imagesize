import detect_mp4, detect_mp4_from_bytes from require "imagesize.mp4"

be32 = (n) ->
  string.char math.floor(n / 0x1000000) % 256, math.floor(n / 0x10000) % 256, math.floor(n / 0x100) % 256, n % 256

box = (box_type, body="") -> "#{be32 8 + #body}#{box_type}#{body}"
large_box = (box_type, body="") -> "#{be32 1}#{box_type}#{be32 0}#{be32 16 + #body}#{body}"

ftyp = box "ftyp", "isom#{be32 512}isomavc1"

mvhd = (timescale, duration) ->
  box "mvhd", "#{"\0"\rep 12}#{be32 timescale}#{be32 duration}#{"\0"\rep 80}"

mvhd_v1 = (timescale, duration, duration_hi=0) ->
  box "mvhd", "\1\0\0\0#{"\0"\rep 16}#{be32 timescale}#{be32 duration_hi}#{be32 duration}#{"\0"\rep 80}"

-- matrix is {a, b, c, d} as integers, scaled to 16.16
tkhd = (width, height, matrix={1, 0, 0, 1}, version=0) ->
  {a, b, c, d} = matrix
  fixed = (n) -> be32 (n * 0x10000) % 0x100000000
  head = version == 1 and "\1\0\0\0#{"\0"\rep 48}" or "#{"\0"\rep 40}"
  box "tkhd", "#{head}#{fixed a}#{fixed b}#{be32 0}#{fixed c}#{fixed d}#{be32 0}#{be32 0}#{be32 0}#{be32 0x40000000}#{fixed width}#{fixed height}"

trak = (handler, codec, header) ->
  hdlr = box "hdlr", "#{"\0"\rep 8}#{handler}#{"\0"\rep 12}"
  stsd = box "stsd", "#{"\0"\rep 4}#{be32 1}#{box codec, "\0"\rep 78}"
  box "trak", "#{header or ""}#{box "mdia", "#{hdlr}#{box "minf", box "stbl", stsd}"}"

video_trak = (...) -> trak "vide", "avc1", tkhd ...

mp4 = (...) -> "#{ftyp}#{box "moov", table.concat {...}}"

detect_file = (fname) ->
  f = assert io.open "spec/test_images/#{fname}", "rb"
  bytes = assert f\read "*a"
  f\close!
  detect_mp4_from_bytes bytes

describe "imagesize.mp4", ->
  describe "files", ->
    it "detects h264 with aac audio and metadata at the end", ->
      assert.same {
        brand: "isom"
        width: 64
        height: 48
        duration: 1
        tracks: {
          { handler: "vide", codec: "avc1", width: 64, height: 48 }
          { handler: "soun", codec: "mp4a", width: 0, height: 0 }
        }
      }, detect_file "h264_aac.mp4"

    it "detects faststart file", ->
      info = detect_file "faststart.mp4"
      assert.same { 64, 48, 1 }, { info.width, info.height, info.duration }

    it "detects rotation", ->
      info = detect_file "rotated.mp4"
      assert.same { 64, 48, 90 }, { info.width, info.height, info.rotation }

    it "detects hevc codec", ->
      info = detect_file "hevc.mp4"
      assert.same "hvc1", info.tracks[1].codec

    it "has no duration for fragmented file", ->
      info = detect_file "fragmented.mp4"
      assert.same { 64, 48 }, { info.width, info.height }
      assert.is_nil info.duration

    it "returns integer dimensions on Lua 5.3+", ->
      return unless math.type
      info = detect_file "h264_aac.mp4"
      assert.same { "integer", "integer" }, { math.type(info.width), math.type(info.height) }

  describe "reads", ->
    it "only reads box headers and moov", ->
      mdat = box "mdat", "\0"\rep 1024 * 1024
      bytes = "#{ftyp}#{mdat}#{box "moov", "#{mvhd 1000, 5000}#{video_trak 640, 480}"}"

      requested = 0
      info = detect_mp4 ((offset, length) ->
        requested += length
        bytes\sub offset + 1, offset + length
      ), #bytes

      assert.same { 640, 480 }, { info.width, info.height }
      assert.true requested < 1024

    it "fails when read returns nil", ->
      bytes = mp4 mvhd(1000, 5000), video_trak 640, 480
      assert.same { nil, "failed to read file" }, { detect_mp4 (-> nil), #bytes }

    it "fails when header read is short", ->
      bytes = mp4 mvhd(1000, 5000), video_trak 640, 480
      assert.same { nil, "failed to read file" }, {
        detect_mp4 ((offset, length) -> bytes\sub offset + 1, offset + length - 1), #bytes
      }

    it "fails when moov read is short", ->
      bytes = mp4 mvhd(1000, 5000), video_trak 640, 480
      read = (offset, length) ->
        length -= 1 if length > 16
        bytes\sub offset + 1, offset + length

      assert.same { nil, "failed to read mp4 metadata" }, { detect_mp4 read, #bytes }

    it "fails on moov over 8MB without reading it", ->
      moov_header = "#{be32 8 * 1024 * 1024 + 9}moov"
      read = (offset, length) ->
        if offset == 0
          ftyp\sub 1, length
        elseif offset == #ftyp
          "#{moov_header}#{"\0"\rep 8}"
        else
          error "should not read moov body"

      assert.same { nil, "mp4 metadata too large" }, { detect_mp4 read, #ftyp + 8 * 1024 * 1024 + 9 }

  describe "synthesized", ->
    it "reads duration", ->
      info = detect_mp4_from_bytes mp4 mvhd(600, 1500), video_trak 640, 480
      assert.same 2.5, info.duration

    it "treats all ones duration as unknown", ->
      info = detect_mp4_from_bytes mp4 mvhd(1000, 0xFFFFFFFF), video_trak 640, 480
      assert.is_nil info.duration

      info = detect_mp4_from_bytes mp4 mvhd_v1(1000, 0xFFFFFFFF, 0xFFFFFFFF), video_trak 640, 480
      assert.is_nil info.duration

    it "never returns a negative duration", ->
      info = detect_mp4_from_bytes mp4 mvhd_v1(1000, 0, 0x80000000), video_trak 640, 480
      assert.true info.duration == nil or info.duration > 0

    it "reads version 1 mvhd and tkhd", ->
      info = detect_mp4_from_bytes mp4 mvhd_v1(1000, 3000), trak "vide", "avc1", tkhd 1280, 720, {0, 1, -1, 0}, 1
      assert.same { 1280, 720, 90, 3 }, { info.width, info.height, info.rotation, info.duration }

    it "reads each rotation", ->
      for {matrix, rotation} in *{
        {{1, 0, 0, 1}, nil}
        {{0, 1, -1, 0}, 90}
        {{-1, 0, 0, -1}, 180}
        {{0, -1, 1, 0}, 270}
      }
        info = detect_mp4_from_bytes mp4 mvhd(1000, 1000), video_trak 640, 480, matrix
        assert.same rotation, info.rotation

    it "uses the first video track", ->
      info = detect_mp4_from_bytes mp4 mvhd(1000, 1000),
        trak("soun", "mp4a", tkhd 0, 0),
        video_trak(640, 480),
        video_trak(320, 240)

      assert.same { 640, 480 }, { info.width, info.height }
      assert.same 3, #info.tracks

    it "skips video tracks without a size", ->
      info = detect_mp4_from_bytes mp4 mvhd(1000, 1000),
        trak("vide", "avc1", box "tkhd", "\0\0\0\0"),
        video_trak(0, 0),
        video_trak(640, 480)

      assert.same { 640, 480 }, { info.width, info.height }

    it "reads 64-bit box sizes", ->
      bytes = "#{ftyp}#{large_box "mdat", "xxxx"}#{large_box "moov", "#{mvhd 1000, 1000}#{video_trak 640, 480}"}"
      info = detect_mp4_from_bytes bytes
      assert.same { 640, 480 }, { info.width, info.height }

    it "reads moov that extends to end of file", ->
      body = "#{mvhd 1000, 1000}#{video_trak 640, 480}"
      info = detect_mp4_from_bytes "#{ftyp}#{be32 0}moov#{body}"
      assert.same { 640, 480 }, { info.width, info.height }

    it "skips many boxes inside moov and trak", ->
      padding = box("free")\rep 10000
      info = detect_mp4_from_bytes mp4 padding, mvhd(1000, 1000), trak "vide", "avc1", "#{padding}#{tkhd 640, 480}"
      assert.same { 640, 480 }, { info.width, info.height }

    it "fails on too many tracks", ->
      assert.same { nil, "too many tracks" }, { detect_mp4_from_bytes mp4 mvhd(1000, 1000), video_trak(640, 480)\rep 65 }

    it "fails on non-mp4", ->
      assert.same { nil, "not an mp4 file" }, { detect_mp4_from_bytes "\137PNG\r\n\26\n#{"\0"\rep 30}" }
      assert.same { nil, "not an mp4 file" }, { detect_mp4_from_bytes "" }

    it "fails without moov", ->
      assert.same { nil, "missing mp4 metadata" }, { detect_mp4_from_bytes "#{ftyp}#{box "mdat", "xxxx"}" }

    it "stops after 64 top-level boxes", ->
      bytes = "#{ftyp}#{box("free")\rep 100}#{box "moov", "#{mvhd 1000, 1000}#{video_trak 640, 480}"}"
      assert.same { nil, "too many top-level boxes" }, { detect_mp4_from_bytes bytes }

    it "fails on box larger than file", ->
      assert.same { nil, "malformed mp4 file" }, { detect_mp4_from_bytes "#{ftyp}#{be32 1000}mdat" }

    it "fails on box smaller than its header", ->
      assert.same { nil, "malformed mp4 file" }, { detect_mp4_from_bytes "#{ftyp}#{be32 4}moov" }

    it "fails without video track", ->
      assert.same { nil, "no video track" }, { detect_mp4_from_bytes mp4 mvhd(1000, 1000), trak "soun", "mp4a", tkhd 0, 0 }

    it "fails on truncated tkhd", ->
      assert.same { nil, "no video track" }, { detect_mp4_from_bytes mp4 mvhd(1000, 1000), trak "vide", "avc1", box "tkhd", "\0\0\0\0" }
