# imagesize

![test](https://github.com/leafo/imagesize/workflows/test/badge.svg)

Detect the size of common image formats while trying to read as few bytes as
possible. Byte strings are parsed using LPeg to extract headers from image
formats

Supported types:

* PNG &mdash; Typically needs at least 25 bytes
* JPEG &mdash; Typically needs around 160 for optimized images, upwards to around 1k or more with EXIF, etc.
* GIF &mdash; Uses the logical screen size, or the first frame's size when it is larger or the file is GIF87a, matching browsers. Typically needs around 700+ bytes, depends on how palette is stored
* WebP &mdash; Lossy, lossless, and extended (alpha, animation) files. Needs at most 30 bytes
* BMP &mdash; Windows and OS/2 bitmaps, including top-down. Needs at most 30 bytes

This library will only read the head of the string to identify the format and dimensions, then bail
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
`gif`, `webp`, `bmp`), and a table containing at least a `width` and `height` field.

For JPEGs with an EXIF orientation tag, the table also has an `orientation`
field with a value from 1 to 8. `width` and `height` are always the stored
dimensions, so for orientations 5 through 8 the image is displayed with them
swapped.

On error, `nil` and an error message is returned.

```lua
local imagesize = require("imagesize")

-- this will attempt to detect the image from 200 bytes, but you're also
-- welcome to pass the whole file
local bytes = file.open("some_image.png"):read(200)

local kind, dimensions = imagesize.detect_image_from_bytes(bytes)

-- kind --> png
-- dimensions --> { width = 25, height = 100, bit_depth = 8 }
```



## MP4

MP4 video is handled by a separate module since its metadata box (`moov`) is
often at the end of the file. Instead of a byte prefix, it takes a read
function so only the box headers and `moov` need to be fetched, typically 3 to
5 reads. This makes it suitable for checking a file in remote storage with
ranged requests.

### `detect_mp4(read, file_size)`

`read(offset, length)` must return exactly `length` bytes of the file starting
at the 0-based `offset`, or `nil` on failure. `file_size` is the total size of
the file.

On success, returns a table with:

* `width`, `height` &mdash; the display size from the header of the first video track that has one
* `rotation` &mdash; `90`, `180`, or `270` if the video must be rotated clockwise for display, otherwise `nil`. `width` and `height` are not swapped
* `duration` &mdash; length in seconds, or `nil` if unknown. Fragmented MP4 files store their duration in the fragments, so it is `nil` for them
* `brand` &mdash; the major brand from the `ftyp` box, eg. `isom`
* `tracks` &mdash; every track, each with `handler` (eg. `vide`, `soun`), `codec` (the first sample entry type, eg. `avc1`, `hvc1`, `mp4a`), and `width`, `height`, `rotation` from its header. Audio tracks usually report a `width` and `height` of `0`

On error, `nil` and an error message is returned. Parsing gives up on files
with more than 64 top-level boxes before `moov`, a `moov` over 8MB, or more
than 64 tracks.

```lua
local mp4 = require("imagesize.mp4")

local f = io.open("video.mp4", "rb")
local size = f:seek("end")

local info = assert(mp4.detect_mp4(function(offset, length)
  f:seek("set", offset)
  return f:read(length)
end, size))

-- info --> { width = 1920, height = 1080, duration = 12.5, brand = "isom", tracks = { ... } }
```

### `detect_mp4_from_bytes(byte_string)`

Same as `detect_mp4`, for when the whole file is already in memory.
