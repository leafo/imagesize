unpack = table.unpack or unpack


describe "imagesize", ->
  describe "png", ->
    it "detects png size", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/image.png"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "png", format
      assert.same {
        width: 50
        height: 23
        bit_depth: 8
      }, data

    -- image has been run through png quant
    it "detects quant png size", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/quant.png"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "png", format
      assert.same {
        width: 60
        height: 28
        bit_depth: 8
      }, data

    -- test each lengh from the first 30 bytes
    it "detects from patial bytes", ->
      import detect_image_from_bytes from require "imagesize"

      results = for i=1,30
        f = assert io.open "spec/test_images/image.png"
        bytes = assert f\read i
        { detect_image_from_bytes bytes }


      err = { nil, "failed to detect image" }

      success = {
        "png"
        {
          width: 50
          height: 23
          bit_depth: 8
        }
      }

      assert.same {
        err
        err
        err
        err
        err
        err
        err
        err
        err
        err

        err
        err
        err
        err
        err
        err
        err
        err
        err
        err

        err
        err
        err
        err
        success
        success
        success
        success
        success
        success
      }, results

  describe "jpg", ->
    it "detects progressive jpg (SOF2)", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/progressive.jpg"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 57
        height: 32
        bit_depth: 8
      }, data

    it "detects baseline jpg (SOF0)", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/baseline.jpg"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 42
        height: 32
        bit_depth: 8
      }, data

    it "detects stripped jpeg", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/stripped.jpg"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 57
        height: 32
        bit_depth: 8
      }, data

    it "detects from patial bytes", ->
      import detect_image_from_bytes from require "imagesize"

      err = { nil, "failed to detect image" }

      success = {
        "jpeg"
        {
          width: 57
          height: 32
          bit_depth: 8
        }
      }

      expected = {
        [1]: err
        [20]: err
        [21]: err
        [100]: err
        [150]: err
        [166]: err
        [167]: success
        [168]: success
        [200]: success
      }

      -- 167
      results = for i=1,200
        f = assert io.open "spec/test_images/stripped.jpg"
        bytes = assert f\read i
        out = { detect_image_from_bytes bytes }
        if expected[i]
          out
        else
          nil

      assert.same expected, results

    it "fails on segment length shorter than the length field", ->
      import detect_image_from_bytes from require "imagesize"

      for len in *{0, 1}
        bytes = string.char 0xFF, 0xD8, 0xFF, 0xE0, 0, len
        assert.same {nil, "failed to detect image"}, { detect_image_from_bytes bytes }

    describe "synthesized", ->
      soi = string.char 0xFF, 0xD8
      app0 = string.char(0xFF, 0xE0, 0, 4) .. "XX"

      -- 8 bit depth, 77 high, 44 wide, single component
      frame = (marker) ->
        string.char 0xFF, marker, 0, 11, 8, 0, 77, 0, 44, 1, 1, 0x11, 0

      expected = {
        "jpeg"
        {
          width: 44
          height: 77
          bit_depth: 8
        }
      }

      it "parses every SOF marker", ->
        import detect_image_from_bytes from require "imagesize"

        for marker in *{0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
          assert.same expected, { detect_image_from_bytes "#{soi}#{app0}#{frame marker}" }

      it "does not treat DHT, JPG, or DAC as a frame", ->
        import detect_image_from_bytes from require "imagesize"

        for marker in *{0xC4, 0xC8, 0xCC}
          assert.same expected, { detect_image_from_bytes "#{soi}#{frame marker}#{frame 0xC0}" }

      it "skips fill bytes before markers", ->
        import detect_image_from_bytes from require "imagesize"

        fill = string.char(0xFF)\rep 3
        assert.same expected, { detect_image_from_bytes "#{soi}#{fill}#{app0}#{fill}#{frame 0xC0}" }

      it "stops at SOS preceded by fill bytes", ->
        import detect_image_from_bytes from require "imagesize"

        sos = string.char 0xFF, 0xFF, 0xDA, 0, 2
        assert.same {nil, "failed to detect image"}, { detect_image_from_bytes "#{soi}#{sos}#{frame 0xC0}" }

      describe "exif", ->
        int = (num, len, endian) ->
          bs = for i=len-1,0,-1
            math.floor(num / 256^i) % 256
          bs = [bs[i] for i=#bs,1,-1] if endian == "little"
          string.char unpack bs

        app1 = (data) ->
          "#{string.char 0xFF, 0xE1}#{int #data + 2, 2}#{data}"

        -- tags is a list of {tag, value} stored as SHORT entries in IFD0
        exif = (tags, endian="big", ifd_offset=8) ->
          header = endian == "big" and "MM" or "II"
          entries = for {tag, value} in *tags
            "#{int tag, 2, endian}#{int 3, 2, endian}#{int 1, 4, endian}#{int value, 2, endian}\0\0"

          app1 "Exif\0\0#{header}#{int 42, 2, endian}#{int ifd_offset, 4, endian}#{int #tags, 2, endian}#{table.concat entries}#{int 0, 4, endian}"

        with_orientation = (orientation) ->
          {
            "jpeg"
            {
              width: 44
              height: 77
              bit_depth: 8
              :orientation
            }
          }

        parse_with = (segment) ->
          import detect_image_from_bytes from require "imagesize"
          { detect_image_from_bytes "#{soi}#{segment}#{frame 0xC0}" }

        it "reads big endian orientation", ->
          assert.same with_orientation(6), parse_with exif {{0x0112, 6}}

        it "reads little endian orientation", ->
          assert.same with_orientation(8), parse_with exif {{0x0112, 8}}, "little"

        it "reads orientation after other tags", ->
          assert.same with_orientation(3), parse_with exif {{0x0100, 500}, {0x0101, 300}, {0x0112, 3}}

        it "reads orientation when exif is not the first segment", ->
          assert.same with_orientation(5), parse_with "#{app0}#{exif {{0x0112, 5}}}"

        it "uses the first exif orientation", ->
          assert.same with_orientation(6), parse_with "#{exif {{0x0112, 6}}}#{exif {{0x0112, 8}}}"

        it "ignores exif without orientation", ->
          assert.same expected, parse_with exif {{0x0100, 500}}

        it "ignores out of range orientation", ->
          assert.same expected, parse_with exif {{0x0112, 9}}

        it "ignores IFD offset past the segment", ->
          assert.same expected, parse_with exif {{0x0112, 6}}, "big", 5000

        it "stops at entries past the segment", ->
          bytes = exif {{0x0100, 500}}
          -- the entry count is the 2 bytes after the 6 byte "Exif" header and 8 byte TIFF header
          count_pos = 4 + 6 + 8 + 1
          bytes = "#{bytes\sub 1, count_pos - 1}#{int 1000, 2}#{bytes\sub count_pos + 2}"
          assert.same expected, parse_with bytes

        it "ignores non-exif APP1 segment", ->
          assert.same expected, parse_with app1 "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta/>"

        it "fails on truncated APP1 segment", ->
          import detect_image_from_bytes from require "imagesize"
          bytes = exif {{0x0112, 6}}
          assert.same {nil, "failed to detect image"}, { detect_image_from_bytes "#{soi}#{bytes\sub 1, #bytes - 4}" }

  describe "gif", ->
    it "detects global color table", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/global.gif"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "gif", format, "image format"
      assert.same {
        width: 24
        height: 49
      }, data


    it "detects global color table with ext", ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/global_ext.gif"
      bytes = assert f\read "*a"

      format, data = detect_image_from_bytes bytes

      assert.same "gif", format, "image format"
      assert.same {
        width: 10
        height: 10
      }, data

    it "detects from patial read", ->
      import detect_image_from_bytes from require "imagesize"

      local count

      for i=1,1000
        f = assert io.open "spec/test_images/global.gif"
        bytes = assert f\read i
        f\close!
        format, data = detect_image_from_bytes bytes
        if format


          assert.same "gif", format, "image format"
          assert.same {
            width: 24
            height: 49
          }, data

          count = i
          break

      assert.same 790, count

    describe "synthesized", ->
      --- with no global color table
      front = "GIF89aXXXX#{string.char 0}XX"

      to2bytes = (num) ->
        b1 = num % 256
        b2 = math.floor (num - b1) / 256
        assert b2 < 256, "num is larger than two bytes"
        string.char b1, b2

      image_descriptor = (width, height) ->
        "#{string.char 44, 0, 0, 0, 0}#{to2bytes width}#{to2bytes height}"

      -- no global color table, no extensions or comments, small size
      it "parses simple gif", ->
        import detect_image_from_bytes from require "imagesize"
        gif_bytes = "#{front}#{image_descriptor 27, 18}"

        assert.same {
          "gif"
          {
            width: 27
            height: 18
          }
        }, {
          detect_image_from_bytes gif_bytes
        }

      it "parses gif with large size", ->
        import detect_image_from_bytes from require "imagesize"
        gif_bytes = "#{front}#{image_descriptor 1832, 1600}"

        assert.same {
          "gif"
          {
            width: 1832
            height: 1600
          }
        }, {
          detect_image_from_bytes gif_bytes
        }

      it "parses gif with color table", ->
        import detect_image_from_bytes from require "imagesize"

        len = 3

        packed_byte = string.char 2^7 + len
        screen_descriptor = "XXXX#{packed_byte}XX#{"."\rep 3*2^(len+1)}"
        gif_bytes = "GIF89a#{screen_descriptor}#{image_descriptor 44, 77}"

        assert.same {
          "gif"
          {
            width: 44
            height: 77
          }
        }, {
          detect_image_from_bytes gif_bytes
        }


      it "parses gif with comment", ->
        import detect_image_from_bytes from require "imagesize"

        comment = "#{string.char 33, 254, 5}HELLO#{string.char 0}"

        gif_bytes = "#{front}#{comment}#{image_descriptor 95, 29}"

        assert.same {
          "gif"
          {
            width: 95
            height: 29
          }
        }, {
          detect_image_from_bytes gif_bytes
        }

      describe "extensions", ->
        expected = {
          "gif"
          {
            width: 95
            height: 29
          }
        }

        parse_with = (ext) ->
          import detect_image_from_bytes from require "imagesize"
          { detect_image_from_bytes "#{front}#{ext}#{image_descriptor 95, 29}" }

        it "parses gif with empty comment", ->
          assert.same expected, parse_with string.char 33, 254, 0

        it "parses gif with multi block comment", ->
          assert.same expected, parse_with "#{string.char 33, 254, 5}HELLO#{string.char 3}ABC#{string.char 0}"

        it "parses gif with graphic control extension", ->
          assert.same expected, parse_with string.char 33, 249, 4, 0, 0, 0, 0, 0

        it "parses gif with NETSCAPE looping extension", ->
          assert.same expected, parse_with "#{string.char 33, 255, 11}NETSCAPE2.0#{string.char 3, 1, 0, 0, 0}"

        it "parses gif with XMP application extension", ->
          assert.same expected, parse_with "#{string.char 33, 255, 11}XMP DataXMP#{string.char 5}<xmp>#{string.char 0}"

        it "parses gif with plain text extension", ->
          assert.same expected, parse_with "#{string.char 33, 1, 12}#{"."\rep 12}#{string.char 2}hi#{string.char 0}"

        it "parses gif with unknown extension", ->
          assert.same expected, parse_with "#{string.char 33, 99, 1}?#{string.char 0}"

        it "fails on truncated sub-block", ->
          assert.same {nil, "failed to detect image"}, parse_with "#{string.char 33, 254, 50}HELLO"

  describe "webp", ->
    detect_file = (fname, len="*a") ->
      import detect_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/#{fname}"
      bytes = assert f\read len
      f\close!
      { detect_image_from_bytes bytes }

    it "detects lossy webp (VP8)", ->
      assert.same { "webp", { width: 301, height: 67 } }, detect_file "lossy.webp"

    it "detects lossless webp (VP8L)", ->
      assert.same { "webp", { width: 77, height: 300 } }, detect_file "lossless.webp"

    it "detects webp with alpha (VP8X)", ->
      assert.same { "webp", { width: 45, height: 33 } }, detect_file "alpha.webp"

    it "detects animated webp (VP8X)", ->
      assert.same { "webp", { width: 260, height: 30 } }, detect_file "animated.webp"

    it "detects from partial bytes", ->
      err = { nil, "failed to detect image" }

      for {fname, needed} in *{{"lossy.webp", 30}, {"lossless.webp", 25}, {"alpha.webp", 30}}
        assert.same err, detect_file fname, needed - 1
        assert.same "webp", detect_file(fname, needed)[1]

    describe "synthesized", ->
      le = (num, len) ->
        string.char unpack for i=0,len-1
          math.floor(num / 256^i) % 256

      riff = (chunk) -> "RIFF#{le 4 + #chunk, 4}WEBP#{chunk}"

      it "ignores VP8 scale bits", ->
        import detect_image_from_bytes from require "imagesize"
        -- top 2 bits of each dimension are the upscale factor
        chunk = "VP8 #{le 10, 4}#{string.char 0, 0, 0, 157, 1, 42}#{le 3 * 2^14 + 640, 2}#{le 2^14 + 480, 2}"
        assert.same { "webp", { width: 640, height: 480 } }, { detect_image_from_bytes riff chunk }

      it "reads max VP8L size", ->
        import detect_image_from_bytes from require "imagesize"
        chunk = "VP8L#{le 5, 4}#{string.char 47}#{le 2^28 - 1, 4}"
        assert.same { "webp", { width: 2^14, height: 2^14 } }, { detect_image_from_bytes riff chunk }

      it "reads 24 bit VP8X size", ->
        import detect_image_from_bytes from require "imagesize"
        chunk = "VP8X#{le 10, 4}#{le 0, 4}#{le 99999, 3}#{le 0, 3}"
        assert.same { "webp", { width: 100000, height: 1 } }, { detect_image_from_bytes riff chunk }

      it "fails on VP8 without start code", ->
        import detect_image_from_bytes from require "imagesize"
        chunk = "VP8 #{le 10, 4}#{string.char 0, 0, 0, 0, 0, 0}#{le 640, 2}#{le 480, 2}"
        assert.same { nil, "failed to detect image" }, { detect_image_from_bytes riff chunk }

      it "fails on non-webp RIFF", ->
        import detect_image_from_bytes from require "imagesize"
        assert.same { nil, "failed to detect image" }, { detect_image_from_bytes "RIFF#{le 100, 4}WAVEfmt #{le 16, 4}" }
