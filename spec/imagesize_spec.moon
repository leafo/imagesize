
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


