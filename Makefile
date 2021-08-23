GO_VERSIONS := 1.14 1.15 1.16 1.17

DOCKER_FILES := $(addsuffix .Dockerfile,$(addprefix .go-,$(GO_VERSIONS)))

.PHONY: all
all: $(DOCKER_FILES)

$(DOCKER_FILES): Dockerfile Makefile
	cp Dockerfile $@
	sed -i '1i # This file is auto-generated. Edit Dockerfile instead!!' $@
	sed -i "s/^\(ARG GO_VERSION=\).*/\1$(subst .go-,,$(basename $@))/" $@
