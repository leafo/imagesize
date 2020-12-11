# imagesize

![test](https://github.com/leafo/imagesize/workflows/test/badge.svg)

Detect the size of common image formats while trying to read as few bytes as
possible. Byte strings are parsed using LPeg to extract headers from image
formats

Supported types:

* PNG &mdash; Typically needs at least 25 bytes
* JPEG &mdash; Typically needs around 160 for optimized images, upwards to around 1k or more with EXIF, etc.
* GIF &mdash; Reads with/height from first image descriptor. Typically needs around 700+ bytes, depends on how palette is stored

This library will only read only of the string to identify the size, then bail
out. It will not verify that the file contains a valid image outside of that.

LPeg does not support reading from a stream so you will have to append a buffer
into a string yourself and sequentially test it.

## Install

`luarocks install https://raw.githubusercontent.com/leafo/imagesize/main/imagesize-dev-1.rockspec`

## Usage

### `detect_image_from_bytes(byte_string)`

Attempts to detect the type and dimensions of an image from the bytes passed in. It's
not necessary to pass the whole image, you can pass any amount of bytes and it
will attempt to read the front of the file up until where it can find the
dimensions.

On success, two values are returned: the type of the image (`png`, `jpeg`,
`gif`), and a table containing at least a `width` and `height` field.

On error, `nil` and an error message is returned.

```lua
local imagesize = require("imagesize")

-- this will attempt to detect the image from 200 bytes, but you're also
-- welcome to pass the whole file
local bytes = file.open("some_image.png"):read(200)

local kind, dimensions = imagesize.detect_image_from_bytes(bytes)

-- kind --> png
-- dimensions --> { width = 25, height = 100, depth = 8 }
```


