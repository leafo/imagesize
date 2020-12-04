
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
