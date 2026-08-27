.PHONY: test lint install uninstall

test:
	bash -n install.sh uninstall.sh bin/* tests/*.sh
	bash tests/run.sh

lint:
	shellcheck install.sh uninstall.sh bin/* tests/*.sh

install:
	./install.sh

uninstall:
	./uninstall.sh
