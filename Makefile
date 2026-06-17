.PHONY: all setup bridge ios watch clean
.PHONY: install uninstall restart status logs pair check help
.PHONY: hooks hooks-local hooks-dry hooks-remove

# Show this help
help:
	@echo "Claude Watch Bridge — Makefile targets"
	@echo ""
	@echo "  Daemon (always-on)"
	@echo "    make install      Build + install + start launchd agent"
	@echo "    make uninstall    Stop + remove launchd agent"
	@echo "    make restart      Restart the launchd agent"
	@echo "    make status       Reachability + health + connections"
	@echo "    make logs         Tail the bridge log (pretty-printed)"
	@echo "    make pair         Request a fresh pairing code"
	@echo ""
	@echo "  Foreground"
	@echo "    make setup        Install deps + build"
	@echo "    make bridge       Start bridge in foreground"
	@echo "    make bridge-dev   Start with hot reload"
	@echo "    make bridge-build Build only"
	@echo "    make bridge-test  Run unit tests"
	@echo "    make check        Quick smoke test (start, test, stop)"
	@echo ""
	@echo "  Claude Code hooks"
	@echo "    make hooks        Install hooks to ~/.claude/settings.json"
	@echo "    make hooks-local  Install to .claude/settings.local.json"
	@echo "    make hooks-dry    Preview without writing"
	@echo "    make hooks-remove Remove bridge hooks"
	@echo ""
	@echo "  iOS"
	@echo "    make ios-gen      Generate Xcode project (xcodegen)"
	@echo "    make ios-open     Open Xcode project"
	@echo ""
	@echo "  Misc"
	@echo "    make clean        Remove build artifacts"

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

# Quick end-to-end smoke test (starts bridge on a random port, tests the
# critical paths, shuts down). Useful after installation to verify everything
# is wired up.
check:
	bash bridge/scripts/smoke-test.sh

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
