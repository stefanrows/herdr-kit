SHELL_FILES := herdr-kit $(wildcard lib/*.sh)

.PHONY: check lint test

check: lint test

lint:
	shellcheck $(SHELL_FILES)

test:
	bats tests
