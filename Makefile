deps:
	git clone https://github.com/nvim-lua/plenary.nvim deps/plenary.nvim

test:
	XDG_CONFIG_HOME=. \
	nvim --headless --clean -u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/test_*.lua" \
		-c "qa"
