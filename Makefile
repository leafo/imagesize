.PHONY: local lint build

local: build
	luarocks make --local --lua-version=5.1 imagesize-dev-1.rockspec

build: 
	moonc imagesize/
 
lint:
	moonc -l imagesize
