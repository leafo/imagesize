
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



