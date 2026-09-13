# Blue View OS window snapping plugin for Hyprland.
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0.

ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`

all: bvos-snap.so

bvos-snap.so: main.cpp
	$(CXX) $(CXXFLAGS) $(DEFINES) $(LDFLAGS) $(EXTRA_FLAGS) $(INCLUDES) $^ -o $@

clean:
	rm -f bvos-snap.so

.PHONY: all clean
