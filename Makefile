CXX      ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -fPIC
RB_CFLAGS := $(shell pkg-config --cflags rubberband)
RB_LIBS   := $(shell pkg-config --libs rubberband)

all: build/libtekvoice.so

build:
	mkdir -p build

build/libtekvoice.so: src/tekvoice.cpp src/dsp.h src/shifter.h src/ladspa.h | build
	$(CXX) $(CXXFLAGS) $(RB_CFLAGS) -shared -o $@ src/tekvoice.cpp $(RB_LIBS)

build/test_plugin: tests/test_plugin.cpp src/ladspa.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/test_plugin.cpp -ldl

build/test_dsp: tests/test_dsp.cpp src/dsp.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/test_dsp.cpp

build/test_shifter: tests/test_shifter.cpp src/shifter.h | build
	$(CXX) $(CXXFLAGS) $(RB_CFLAGS) -o $@ tests/test_shifter.cpp $(RB_LIBS)

test-plugin: build/libtekvoice.so build/test_plugin
	./build/test_plugin

test-dsp: build/test_dsp
	./build/test_dsp

test-shifter: build/test_shifter
	./build/test_shifter

test-voices:
	node tests/test_voices.cjs

test-model:
	node tests/test_model.cjs

test-cli:
	sh tests/test_cli.sh

test: test-dsp test-shifter test-plugin test-voices test-model

clean:
	rm -rf build

.PHONY: all test test-dsp test-shifter test-plugin test-voices test-model test-cli clean
