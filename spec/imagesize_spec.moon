
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

    -- test each lengh from the first 30 bytes
    it "detects from patial bytes", ->
      import scan_image_from_bytes from require "imagesize"

      results = for i=1,30
        f = assert io.open "spec/test_images/image.png"
        bytes = assert f\read i
        { scan_image_from_bytes bytes }


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

    it "detects stripped jpeg", ->
      import scan_image_from_bytes from require "imagesize"
      f = assert io.open "spec/test_images/stripped.jpg"
      bytes = assert f\read "*a"

      format, data = scan_image_from_bytes bytes

      assert.same "jpeg", format
      assert.same {
        width: 57
        height: 32
        bit_depth: 8
      }, data

    it "detects from patial bytes", ->
      import scan_image_from_bytes from require "imagesize"

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
        out = { scan_image_from_bytes bytes }
        if expected[i]
          out
        else
          nil

      assert.same expected, results

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

    it "detects from patial read", ->
      import scan_image_from_bytes from require "imagesize"

      local count

      for i=1,1000
        f = assert io.open "spec/test_images/global.gif"
        bytes = assert f\read i
        f\close!
        format, data = scan_image_from_bytes bytes
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


      it "parses gif with comment", ->
        import scan_image_from_bytes from require "imagesize"

        comment = "#{string.char 33, 254, 5}HELLO#{string.char 0}"

        gif_bytes = "#{front}#{comment}#{image_descriptor 95, 29}"

        assert.same {
          "gif"
          {
            width: 95
            height: 29
          }
        }, {
          scan_image_from_bytes gif_bytes
        }
