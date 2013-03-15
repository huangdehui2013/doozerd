deps:
	go get code.google.com/p/goprotobuf/proto
	go get code.google.com/p/go.net/websocket


compile: fmt deps
	./version.sh
	./make.sh

fmt:
	go fmt ./...

clean:
	git clean -df

########### local build:

LOCAL_GOPATH=${PWD}/.go_path
DOOZERD_GO_PATH=$(LOCAL_GOPATH)/src/github.com/soundcloud/doozerd
DOOZER_GO_PATH=$(LOCAL_GOPATH)/src/github.com/soundcloud/doozer/cmd/doozer

build: fmt package bump_package_release
	echo ".git" > .pkgignore
	find . -mindepth 1 -maxdepth 1 | grep -v "\.deb" | sed 's/\.\///g' >> .pkgignore
	test -z "$(REPREPRO_SSH)" || for d in $$(ls *.deb); do cat $$d | ssh -o 'StrictHostKeyChecking=no' $(REPREPRO_SSH) reprepro-add; done

$(LOCAL_GOPATH)/src:
	mkdir -p $(LOCAL_GOPATH)/src

$(LOCAL_GOPATH)/src/github.com/soundcloud/doozer: $(LOCAL_GOPATH)/src
	GOPATH=$(LOCAL_GOPATH) go get github.com/soundcloud/doozer

$(LOCAL_GOPATH)/src/github.com/bmizerany/assert: $(LOCAL_GOPATH)/src
	GOPATH=$(LOCAL_GOPATH) go get github.com/bmizerany/assert

local_build: $(LOCAL_GOPATH)/src/github.com/soundcloud/doozer $(LOCAL_GOPATH)/src/github.com/bmizerany/assert
	test -e $(DOOZERD_GO_PATH) || { mkdir -p $$(dirname $(DOOZERD_GO_PATH) ); ln -sf $${PWD} $(DOOZERD_GO_PATH); }
	# instead of patching the make.sh file or tweak the go install command, we ignore errors and call 'go build' afterwards
	-GOPATH=$(LOCAL_GOPATH) go get -v .
	-GOPATH=$(LOCAL_GOPATH) ./make.sh
	 GOPATH=$(LOCAL_GOPATH) go build -o doozerd
	 GOPATH=$(LOCAL_GOPATH) go test -cpu 2 -v ./...
	 cd $(DOOZER_GO_PATH); printf 'package main\n\nconst version = `%s`\n' "$(VERSION)" > vers.go; GOPATH=$(LOCAL_GOPATH) go build; cp doozer $(LOCAL_GOPATH)/../; cd -


########## packaging
FPM_EXECUTABLE:=$$(dirname $$(dirname $$(gem which fpm)))/bin/fpm
FPM_ARGS=-t deb -m 'Doozerd authors (see page), Daniel Bornkessel <daniel@soundcloud.com> (packaging)' --url http://github.com/soundcloud/doozerd -s dir
FAKEROOT=fakeroot
RELEASE=$$(cat .release 2>/dev/null || echo "0")
# this is needed for a push to an empty get repo, when git describe is not working yet
FALLBACK_VERSION=8.51.0
# oh my: please forgive me:
VERSION:=$$({ { git describe >/dev/null 2>/dev/null && $(PWD)/version.sh; } || echo "$(FALLBACK_VERSION)"; } | tr '+' '.' | sed 's/^\.mod$$/$(FALLBACK_VERSION)/g')

package: local_build
	rm -rf $(FAKEROOT)
	mkdir -p $(FAKEROOT)/usr/bin
	cp doozerd $(FAKEROOT)/usr/bin
	cp doozer $(FAKEROOT)/usr/bin
	rm -rf *.deb

	$(FPM_EXECUTABLE) -n "doozerd" \
		-C $(PWD)/$(FAKEROOT) \
		--description "doozerd" \
		$(FPM_ARGS) -t deb -v $(VERSION) --iteration $(RELEASE) .;


bump_package_release:
		echo $$(( $(RELEASE) + 1 )) > .release
