.PHONY: all setup bridge ios watch clean
.PHONY: install uninstall restart status logs pair
.PHONY: hooks hooks-local hooks-dry hooks-remove

all: setup

# Bootstrap the entire project
setup:
	@echo "==> Installing bridge dependencies..."
	cd bridge && npm install
	@echo "==> Building bridge server..."
	cd bridge && npm run build
	@echo ""
	@echo "Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Install as auto-start daemon: make install   (or: make bridge to run in foreground)"
	@echo "  2. Configure Claude hooks:        make hooks"
	@echo "  3. Open iOS project:              make ios-open"

# ---------------------------------------------------------------- Bridge
# Run the bridge in the foreground
bridge:
	cd bridge && npm start

# Start bridge in dev mode with hot reload
bridge-dev:
	cd bridge && npm run dev

# Build the bridge
bridge-build:
	cd bridge && npm run build

# Run bridge tests
bridge-test:
	cd bridge && npm test

# ---------------------------------------------------------------- Daemon
# Install the bridge as a launchd agent (auto-start on login, keep-alive)
install:
	bash bridge/scripts/daemon.sh install

# Stop and remove the launchd agent
uninstall:
	bash bridge/scripts/daemon.sh uninstall

# Restart the launchd agent
restart:
	bash bridge/scripts/daemon.sh restart

# Show reachability, health, and connection stats
status:
	bash bridge/scripts/daemon.sh status

# Tail the bridge log (pretty-printed)
logs:
	bash bridge/scripts/daemon.sh logs

# Request a fresh pairing code from a running bridge
pair:
	bash bridge/scripts/daemon.sh pair

# ---------------------------------------------------------------- Hooks
# Configure Claude Code hooks (user settings)
hooks:
	bash bridge/scripts/setup-hooks.sh

# Configure Claude Code hooks (project-local)
hooks-local:
	bash bridge/scripts/setup-hooks.sh --local

# Preview hooks config without writing
hooks-dry:
	bash bridge/scripts/setup-hooks.sh --dry-run

# Remove Claude Watch hooks (user settings)
hooks-remove:
	bash bridge/scripts/setup-hooks.sh --remove

# ---------------------------------------------------------------- iOS
# Generate Xcode project
ios-gen:
	cd ios && xcodegen generate

# Open Xcode project
ios-open: ios-gen
	open ios/ClaudeWatch.xcworkspace 2>/dev/null || open ios/ClaudeWatch.xcodeproj

# ---------------------------------------------------------------- Misc
# Clean build artifacts
clean:
	cd bridge && rm -rf dist/ node_modules/
	cd ios && rm -rf *.xcworkspace/ *.xcodeproj/ DerivedData/
	@echo "Cleaned."
