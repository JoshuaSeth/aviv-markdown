.PHONY: check check-list check-one check-probe format

check:
	./scripts/ios_check.py

check-list:
	./scripts/ios_check.py --list

check-one:
	./scripts/ios_check.py --only "$(GATE)"

check-probe:
	./scripts/ios_check.py --probe

format:
	./scripts/ios_format.sh
