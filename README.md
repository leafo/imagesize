
# imagesize

Detect the size of common image formats while trying to read as few bytes as
possible. Byte strings are parsed using LPEG to extract headers from image
formats

Supported types:

* PNG
* JPG
* GIF -- Reads with/height from first image descriptor

This library will only read only of the string to identify the size, then bail
out. It will not verify that the file contains a valid image outside of that.

## Install

`luarocks install imagesize`

## Usage

On successful scan, two values are returned, the type of the image (`png`,
`jpeg`, `gif`), and a table containing at least a `width` and `height` field.

On error, `nil` and an error message is returned.

```lua
local imagesize = require("imagesize")

local bytes = file.open("some_image.png"):read("*")

local kind, dimensions = imagesize.scan_image_from_bytes(bytes)

-- kind --> png
-- dimensions --> { width = 25, height = 100, depth = 8 }
```


