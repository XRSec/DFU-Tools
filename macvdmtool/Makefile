CXXFLAGS := -std=c++14
LDFLAGS := -std=c++14 -framework CoreFoundation -framework IOKit -lc++

OBJS := main.o

all: macvdmtool

macvdmtool: $(OBJS)
	cc -o $@ $(OBJS) $(LDFLAGS)
