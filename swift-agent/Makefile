PAYLOAD_DIR := ../public/assets/client_installer/payload/usr/local/munkireport

.PHONY: build build-universal clean install test

# Build for current architecture (development)
build:
	swift build

# Build universal binary for distribution (arm64 + x86_64)
build-universal:
	swift build -c release --arch arm64 --arch x86_64

# Run tests
test:
	swift test

# Install the release binary into the payload directory
install: build-universal
	cp .build/apple/Products/Release/munkireport-runner "$(PAYLOAD_DIR)/munkireport-runner"
	@echo "Installed universal binary to $(PAYLOAD_DIR)/munkireport-runner"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
