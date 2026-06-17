BINARY = box
PROFILE ?= debug
BUILD_DIR = .build/$(PROFILE)
INSTALL_PREFIX ?= /usr/local

SWIFT = $(shell xcrun -f swift)

.PHONY: all build install clean

all: build

build:
	$(SWIFT) build -c $(PROFILE)

install: all
	install -d $(INSTALL_PREFIX)/bin
	install $(BUILD_DIR)/$(BINARY) $(INSTALL_PREFIX)/bin/$(BINARY)

clean:
	$(SWIFT) package clean
