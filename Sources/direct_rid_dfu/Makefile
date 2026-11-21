# Build on macOS. This Linux CI image cannot link the Mach-O.
# mra_sender_protocol.h is vendored at Sources/sender_protocol/ and is
# picked up by #include "../sender_protocol/mra_sender_protocol.h".
CXXFLAGS := -std=c++14
LDFLAGS := -framework CoreFoundation -framework IOKit -lc++

OBJS := main.o

all: direct_rid_dfu

direct_rid_dfu: $(OBJS)
	cc -o $@ $(OBJS) $(LDFLAGS)

ifeq ($(PREFIX),)
    PREFIX := /usr/local
endif

INSTALL := /usr/bin/install

.PHONY: install
install: direct_rid_dfu
	@sudo $(INSTALL) -d "$(PREFIX)/bin/"
	@sudo $(INSTALL) -m 755 -o root -g wheel "$(<)" "$(PREFIX)/bin/"
