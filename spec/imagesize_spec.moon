
describe "imagesize", ->
  describe "png", ->
    it "detects png size", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/image.png"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "png", format
      assert.same {
        width: 50
        height: 23
        bit_depth: 8
      }, data

    -- image has been run through png quant
    it "detects quant png size", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/quant.png"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "png", format
      assert.same {
        width: 60
        height: 28
        bit_depth: 8
      }, data

  describe "jpg", ->
    it "detects progressive jpg (SOF2)", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/progressive.jpg"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 57
        height: 32
        bit_depth: 8
      }, data

    it "detects baseline jpg (SOF0)", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/baseline.jpg"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 42
        height: 32
        bit_depth: 8
      }, data

  describe "gif", ->
    it "detects global color table", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/global.gif"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "gif", format, "image format"
      assert.same {
        width: 24
        height: 49
      }, data


    it "detects global color table with ext", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/global_ext.gif"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "gif", format, "image format"
      assert.same {
        width: 10
        height: 10
      }, data

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
        import scan_image_from_bytes from require "imagesize"
        gif_bytes = "#{front}#{image_descriptor 27, 18}"

        assert.same {
          "gif"
          {
            width: 27
            height: 18
          }
        }, {
          scan_image_from_bytes gif_bytes
        }

      it "parses gif with large size", ->
        import scan_image_from_bytes from require "imagesize"
        gif_bytes = "#{front}#{image_descriptor 1832, 1600}"

        assert.same {
          "gif"
          {
            width: 1832
            height: 1600
          }
        }, {
          scan_image_from_bytes gif_bytes
        }

      it "parses gif with color table", ->
        import scan_image_from_bytes from require "imagesize"

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
          scan_image_from_bytes gif_bytes
        }

