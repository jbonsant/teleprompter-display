SWIFT := xcrun swift

.PHONY: bootstrap build test run-app run-harness

bootstrap:
	$(SWIFT) package resolve

build:
	$(SWIFT) build

test:
	$(SWIFT) test

run-app:
	$(SWIFT) run teleprompter-display

run-harness:
	$(SWIFT) run teleprompter-rehearsal
