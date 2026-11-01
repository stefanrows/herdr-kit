SHELL_FILES := herdr-kit install.sh $(wildcard lib/*.sh)

.PHONY: check lint test

check: lint test

lint:
	shellcheck $(SHELL_FILES)

test:
	bats tests
